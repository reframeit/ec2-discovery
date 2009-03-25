require 'net/http'
require 'rubygems'
require 'right_aws'
require 'ec2-discovery/message'
require 'ec2-discovery/queue_listener'
require 'ec2-discovery/message_processor'
require 'ec2-discovery/message_processors/availability_processor'
require 'ec2-discovery/message_processors/subscription_processor'

module ReframeIt
  module EC2
    class Discovery
      ##
      # Initialize the agent with AWS info
      ##
      def initialize(aws_access_key_id, aws_secret_access_key)
        @aws_access_key_id = aws_access_key_id
        @aws_secret_access_key = aws_secret_access_key
      end

      ##
      # The master monitor is responsible for listening to the
      # monitor queue and letting subscribers know about events 
      # that are relevant to them.
      #
      # Currently we only have support for a single master monitor.
      # Future versions will have support for backup monitors, as well
      # as a more distributed setup.
      #
      # This method launches a monitor thread and returns the thread
      # that was created.
      ##
      def monitor()
        listener = QueueListener.new(monitor_queue)
        sub_processor = SubscriptionProcessor.new
        avail_processor = AvailabilityProcessor.new
        
        listener.add_processor(sub_processor)
        listener.add_processor(avail_processor)

        # add a post-processor to let the subscriber know
        # of all the available services it is interested in, 
        # that we currently know about.
        sub_processor.post_process = Proc.new do |msg|
          if msg.subscribe
            queue = sqs.queue(msg.response_queue)
            msg.services.each do |service|
              # send an availability message for each service
              ipv4addrs = avail_processor.ipv4addrs(service)
              ipv4addrs.each do |ipv4addr|
                avail_msg = AvailabilityMessage.new([service],ipv4addr,true)
                send_message(queue, avail_msg)
              end
            end
          end
        end

        # add a post-processor to let any subscribers know of
        # chanes in availability
        avail_processor.post_process = Proc.new do |msg|
          msg.services.each do |service|
            sub_processor.response_queues(service).each do |response_queue|
              send_message(sqs.queue(response_queue), msg)
            end
          end
        end

        # TODO: add logic for updating system files.

        return listener.listen
      end

      ##
      # Runs a pub/sub client. If one of the services listed is
      # 'monitor', then we launch a monitor as well.
      #
      # Currently, this script updates /etc/resolv.conf every few seconds
      # with the latest ip addresses of the named services that the client
      # is interested in (or everything if it is a monitor).
      # Multiple addresses for the same service will have the service names
      # appended with 00-99
      ##
      def run()
        # first see if we should just exit
        if user_data('disable')
          return
        elsif (pre_script = user_data('pre_script'))
          puts "Executing pre_script: '#{pre_script}'"
          puts `pre_script`
        end

        # TODO: if we're a monitor, we need to have different behavior!

        # start listening on our instance_queue
        listener = QueueListener.new(instance_queue)
        avail_proc = AvailabilityProcessor.new
        avail_proc.post_process = Proc.new do |msg|
          # TODO: update /etc/resolv.conf here?
        end
        listener.add_processor(avail_proc)
        listener_thread = listener.listen

        # subscribe to all the services we're interested in
        sub_msg = SubscriptionMessage.new(subscribes, instance_queue, true)
        send_message(monitor_queue, sub_msg)

        # let everyone know we're available
        avail_msg = AvailabilityMessage.new(provides, local_ipv4, true)
        send_message(monitor_queue, avail_msg)

        # keep listening...
        listener_thread.join
      end

      ##
      # Our RightAws::SqsGen2 object
      ##
      def sqs
        @sqs ||= RightAws::SqsGen2.new(@aws_access_key_id, @aws_secret_access_key)
        return @sqs
      end

#       def sdb
#         @sdb ||= RightAws::SdbInterface.new(@aws_access_key_id, @aws_secret_access_key)
#         return @sdb
#       end

#       def ec2
#         @ec2 ||= RightAws::Ec2.new(@aws_access_key_id, @aws_secret_access_key)
#         return @ec2
#       end

      ##
      # retrieves the ec2 instance data for the specified key
      ##
      def ec2_meta_data(key = '')
        Net::HTTP.start("169.254.169.254") do |http|
          value = http.get("/latest/meta-data/#{key}")
        end

        return value
      end

      ##
      # grab the unparsed user_data that was supplied when this
      # instance was created.
      # (this is separated out to ease with testing)
      #
      # See: ec2_user_data
      ##
      def ec2_fetch_user_data_str
        if !@user_data_str
          Net::HTTP.start("169.254.169.254") do |http|
            @user_data_str = http.get("/latest/user-data")
          end
        end
      end

      ##
      # parses the user-supplied data (when the instance was launched)
      # into a nice hash for us.
      #
      # See: ec2_user_data
      ##
      def parse_user_data_str(user_data_str)
        user_data = {}
        line_no = 0
        user_data_str.each_line do |line|
          line_no += 1
          line = line.strip
          parts = line.split("=")
          if parts.length < 2
            STDERR.puts "Warning, user-data line #{line_no} does not conform to specification: '#{line}'"
          else
            key = parts.first
            value = parts[1..-1].join('') # in case there was an '=' in the value
            # already have a value, so make sure we have an array
            if user_data[key]
              if !user_data[key].is_a?(Array)
                user_data[key] = [user_data[key]]
              end
              user_data[key] << value
            else
              user_data[key] = value
            end
          end
        end

        return user_data
      end

      ##
      # retrieves the ec2 user data that was supplied when the
      # current instance was launched.
      #
      # The user data should (for now, at least) follow this strict format:
      #
      # <user-data> ::= <entry>*
      # <entry> ::= <key> "=" <value> <EOL>
      # <key> ::= [a-zA-Z0-9_-]*
      # <value> ::= <text>
      #
      #
      # In addition, this gem uses some pre-determined user data types:
      # provide - a service that this instance provides
      #           specify multiple services by multiple provide=<name> lines.
      # subscribe - like provide, but declaring a service that this instance
      #             is interested in getting updates about
      #
      # pre_script - a standard bash script that should be executed before
      #              any pub/sub takes place
      # disable - if this key is present (the value doesn't matter), then
      #           no pub/sub will take place
      #
      # == a note about scripts ==
      # remember that they have to be listed as a single line!
      #
      # == defaults ==
      # If no user_data exists for the given key, then the default
      # will be returned, if specified.
      #
      ##
      def ec2_user_data(key = '', default = '')
        ec2_fetch_user_data_str
        @user_data = parse_user_data_str(@user_data_str) if !@user_data

        if @user_data[key]
          return @user_data[key]
        else
          return default
        end
      end

      ##
      # the aws instance id, as read from the ec2 meta-data
      ##
      def instance_id
        return ec2_meta_data('instance-id')
      end

      ##
      # the aws internal ipv4, as read fromt he ec2 meta-data
      ##
      def local_ipv4
        return ec2_meta_data('local-ipv4')
      end

      ##
      # the user-defined services that this instance provides,
      # as read from the ec2 user-data
      #
      # Returns: array of strings
      ##
      def provides
        provides = ec2_user_data('provide')
        if !provides || provides.empty?
          return []
        else
          return provides.is_a?(Array) ? provides : [provides]
        end
      end

      ##
      # the user-defined services that this instance is interested in,
      # as read from the ec2 user-data
      #
      # Returns: array of strings
      ##
      def subscribes
        subscribes = ec2_user_data('subscribe')
        if !subscribes || subscribes.empty?
          return []
        else
          return subscribes.is_a?(Array) ? subscribes : [subscribes]
        end
      end

      ##
      # the pub queue where we send messages
      ##
      def monitor_queue
        @monitor_queue ||= sqs.queue('monitor')
        return @monitor_queue
      end

      ##
      # the sub queue where we receive messages
      ##
      def instance_queue
        @instance_queue ||= sqs.queue(instance_id)
        return @instance_queue
      end

      ##
      # sends a message to the given queue
      #
      # == Params: ==
      # +queue+ the RightAws::SqsGen2::Queue to send the message to
      # +msg+ a ReframeIt::EC2::Message to send
      ##
      def send_message(queue, msg)
        queue.send_message(msg.to_json)
      end

    end
  end
end
