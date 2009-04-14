require 'net/http'
require 'rubygems'
require 'right_aws'
require 'ec2-discovery/message'
require 'ec2-discovery/queue_listener'
require 'ec2-discovery/message_processor'
require 'ec2-discovery/message_processors/availability_processor'
require 'ec2-discovery/message_processors/subscription_processor'
require 'ec2-discovery/action'

module ReframeIt
  module EC2

    class Discovery
      include ReframeIt::EC2::Logger

      ##
      # Initialize the agent with AWS info
      ##
      def initialize(aws_access_key_id, aws_secret_access_key, logger = nil)
        @aws_access_key_id = aws_access_key_id
        @aws_secret_access_key = aws_secret_access_key
        self.logger = logger if logger
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
        avail_processor = AvailabilityProcessor.new(true)

        listener.add_processor(sub_processor)
        listener.add_processor(avail_processor)

        # add a post-processor to let the subscriber know
        # of all the available services it is interested in, 
        # that we currently know about.
        sub_processor.post_process = Proc.new do |msg|
          begin
            if msg.subscribe
              info { "received subscription from #{msg.response_queue} for #{msg.services.inspect}" }
              debug { "got subscription #{msg.inspect}" }
              queue = sqs.queue(msg.response_queue)

              # determine which services that this subscriber is interested in,
              # and organize them by ipv4 address (so we can send a minimal amount of messages)
              ipv4_services = {}

              msg.services.each do |service|
                # send an availability message for each service
                addrs = avail_processor.available(service)
                addrs.each do |addr|
                  ipv4_services[addr.ipv4] ||= []
                  ipv4_services[addr.ipv4] |= ["#{service}#{addr.port}"]
                end
              end

              ipv4_services.each do |ipv4, services|
                avail_msg = AvailabilityMessage.new(services, ipv4, true)
                debug { "sending availability msg #{avail_msg.inspect}" }
                send_message(queue, avail_msg)
              end
            end
          rescue Exception => ex
            error "Error during post-process for message #{msg.inspect}",  ex
          end
        end

        # add a post-processor to let any subscribers know of
        # updates to availability, even keep-alives.
        avail_processor.post_process = Proc.new do |msg|
          debug { "received availability message #{msg.inspect}" }
          begin
            msg.services.each do |service|
              # service may have included a port, so strip that off when we
              # search for subscribers
              service_minus_port = service.gsub(/:.*$/, '')

              sub_processor.response_queues(service_minus_port).each do |response_queue|
                # original message may have included more services 
                # other than what the subscriber is interested in
                avail_msg = AvailabilityMessage.new([service], msg.ipv4addr, msg.available, msg.ttl)
                debug { "sending availability message #{avail_msg.inspect}" }
                send_message(sqs.queue(response_queue), avail_msg)
              end
            end
          rescue Exception => ex
            error "Error during post-process for message #{msg.inspect}", ex
          end
        end

        # TODO: allow control over this thread
        unavail_thread = Thread.new do
          while true
            begin
              avail_processor.expired.each do |service, addr_list|
                info { "#{service} on #{addr_list.inspect} expired" }
                sub_processor.response_queues(service).each do |response_queue|
                  addr_list.each do |addr|
                    msg = AvailabilityMessage.new(["#{service}#{addr.port}"], addr.ipv4, false, -1)
                    debug { "sending unavailable message #{msg.inspect} to #{response_queue}" }
                    begin
                      send_message(sqs.queue(response_queue), msg)
                    rescue Exception => ex
                      error "Error sending unavailable message #{msg.inspect} to #{response_queue}", ex
                    end
                  end
                end
              end
            rescue Exception => ex
              error "Unexpected exception in expiration thread!", ex
            end
            sleep 1
          end
        end
        

        return listener.listen
      end

      ##
      # Subscribe to the services we're interested in, and listen for
      # any changes in availability for those services, calling any 
      # necessary actions when this occurs.
      #
      # == Params:
      # +subscribes+ - array of services we are subscribing to
      # +queue_name+ - the name of the aws queue we wish to listen on
      # +subscribe_interval+ - how often we should send a subscription message
      #
      # Returns: (running) subscription thread or nil if none was needed
      #
      # TODO: provide a way to stop the subscription thread
      # FIXME: we just leave the listener thread dangling here
      ##
      def subscribe(subscribes = [], queue_name = nil, subscribe_interval=10)
        return nil if subscribes.empty?

        # start listening on our queue
        queue = sqs.queue(queue_name)
        listener = QueueListener.new(queue)
        avail_proc = AvailabilityProcessor.new
        avail_proc.availability_changed = Proc.new do |availability_processor|
          info { "Availability Changed! New list is:\n #{availability_processor.all_available(false, true).inspect}" }
          debug { "received availability message #{availability_processor}" }
          actions.each do |action|
            begin
              action.invoke(availability_processor)
            rescue Exception => ex
              error "Error calling action #{action.inspect} with #{availability_processor.inspect}", ex
            end
          end
        end
        listener.add_processor(avail_proc)
        listener_thread = listener.listen
        
        subscribe_thread = Thread.new do
          while true 
            # subscribe to all the services we're interested in
            begin
              sub_msg = SubscriptionMessage.new(subscribes, queue_name, true)
              debug{ "sending subscription message #{sub_msg.inspect}" }
              send_message(monitor_queue, sub_msg)
              debug{ "sleeping for #{subscribe_interval}s" }
              sleep subscribe_interval
            rescue Exception => ex
              error "Error sending subscription message: #{sub_msg.inspect}", ex
            end
          end
        end
          
        return subscribe_thread
      end

      ##
      # broadcast our availability
      #
      # == Params:
      #  +provides+ array of services we claim to provide
      #  +interval+ how often we should broadcast our availability. set to -1
      #             to indicate a one-time broadcast
      #
      # Returns: broadcast thread, or nil if there is nothing to broadcast or
      # this is a one-time broadcast
      ##
      def broadcast_availability(provides = [], interval=10)
        return nil if provides.empty?

        avail_msg = AvailabilityMessage.new(provides, local_ipv4, true, interval*3)
        if interval == -1
          send_message(monitor_queue, avail_msg)
          return nil
        end

        # let everyone know we're available
        avail_thread = Thread.new do
          while true
            begin
              debug { "sending availability message #{avail_msg.inspect}" }
              send_message(monitor_queue, avail_msg)
            rescue Exception => ex
              error "Error trying to send availability message #{avail_msg.inspect}", ex
            end
            sleep interval
          end
        end

        return avail_thread
      end

      ##
      # Runs a pub/sub client. If one of the services listed is
      # 'monitor', then we launch a monitor as well.
      #
      # If using the UpdateHosts action, then this script will update
      # /etc/hosts every few seconds with the latest ip address
      # of the named services that the client is interested in.
      # Multiple addresses for the same service will have the service names
      # appended with 00-99
      ##
      def run()
        # first see if we should just exit
        if !ec2_user_data('disable', '').empty?
          info "disable flag is set, so returning...\n\n"
          return
        end

        run_pre_scripts

        is_monitor = provides.include?('monitor')
        
        # evaluate our actions
        # this is important as it can both notify us of errors early on,
        # and it also allows the actions to perform any initialization code
        actions

        if is_monitor
          monitor_thread = monitor()
          ## TODO: don't just leave this thread dangling, 
          ## do something if it crashes!
        end
        
        listener_thread = subscribe(subscribes, instance_id, 10)

        # even if we're a monitor, we may provide some other services as well.
        avail_thread = broadcast_availability(provides, 3)

        sleep 3
        run_post_scripts

        # keep listening...
        listener_thread.join if listener_thread
        avail_thread.join if avail_thread
      end

      ##
      # executes any pre_script scripts passed in via user-data
      ##
      def run_pre_scripts
        pre_ruby_scripts.each do |script|
          begin
            info "Executing pre_ruby_script: #{script}"
            eval(script)
          rescue Exception => ex
            error "Error executing pre_ruby_script: #{script}", ex
          end
        end

        pre_scripts.each do |script|
          info "Executing pre_script: #{script}"
          info `#{script}`
        end
      end

      ##
      # executes any post_script scripts passed in via user-data
      ##
      def run_post_scripts
        post_scripts.each do |script|
          info "Executing post_script: #{script}"
          info `#{script}`
        end

        post_ruby_scripts.each do |script|
          begin
            info "Executing post_ruby_script: #{script}"
            eval(script)
          rescue Exception => ex
            error "Error executing post_ruby_script: #{script}", ex
          end
        end
      end
      
      ##
      # Our RightAws::SqsGen2 object
      ##
      def sqs
        @sqs ||= RightAws::SqsGen2.new(@aws_access_key_id, @aws_secret_access_key, :multi_thread => true, :logger => logger)
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
      def ec2_meta_data(key = '', default='')
        value = default
        Net::HTTP.start("169.254.169.254") do |http|
          value = http.get("/latest/meta-data/#{key}").body
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
            @user_data_str = http.get("/latest/user-data").body
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
          next if line =~ /^#/ # skip comments
          next if line.empty? # skip blank lines
          parts = line.split("=")
          if parts.length < 2
            warn "user-data line #{line_no} does not conform to specification: '#{line}'"
          else
            key = parts.first
            value = parts[1..-1].join('=') # in case there was an '=' in the value
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
      #           If the service runs on a specific port (N), it should be specified as 
      #           service:N, or if it runs on a range of ports (N-M), service:N-M
      # subscribe - like provide, but declaring a service that this instance
      #             is interested in getting updates about
      #
      # pre_script - a standard bash script that should be executed before
      #              any pub/sub takes place
      # post_script - a standard bash script that should be executed after
      #               the discovery has started
      # pre_ruby_script - like pre_script, but this gets eval'd as ruby code, so it 
      #                   can do things like call ReframeIt::EC2::Discovery methods (it has access to self).
      #                   These are eval'd before the pre_scripts.
      # post_ruby_script - like post_script, but this gets eval'd as ruby code, so it 
      #                    can do things like call ReframeIt::EC2::Discovery methods (it has access to self).
      #                    These are eval'd after the post_scripts.
      # disable - if this key is present (the value doesn't matter), then
      #           no pub/sub will take place
      # local_name - a hostname to assign to the local ipv4 address.
      #              If unspecified, this is set to 'local_name'
      # public_name - a hostname to assign to the public ipv4 address.
      #               If unspecified, this is set to 'public_name'
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
      # the aws external ipv4, as read fromt he ec2 meta-data
      ##
      def public_ipv4
        return ec2_meta_data('public-ipv4')
      end

      ##
      # the user-defined services that this instance provides,
      # as read from the ec2 user-data
      #
      # Returns: array of strings
      ##
      def provides
        @provides ||= user_data_as_array('provide')
        @provides
      end

      ##
      # the user-defined services that this instance is interested in,
      # as read from the ec2 user-data
      #
      # Returns: array of strings
      ##
      def subscribes
        @subscribes ||= user_data_as_array('subscribe')
        @subscribes
      end

      ##
      # the user-defined actions that this instance should take when its host
      # list is updated,
      # as read from the ec2 user-data
      #
      # Returns: array of strings
      ##
      def action_strs
        @action_strs ||= user_data_as_array('action')
        @action_strs
      end

      ##
      # the user-defined pre-scripts to execute before any discovery takes place,
      # as read from the ec2-user-data
      #
      # Returns: array of strings
      ##
      def pre_scripts
        @pre_scripts ||= user_data_as_array('pre_script')
        @pre_scripts
      end

      ##
      # the user-defined post-scripts to execute after the discovery has begun,
      # as read from the ec2-user-data
      #
      # Returns: array of strings
      ##
      def post_scripts
        @post_scripts ||= user_data_as_array('post_script')
        @post_scripts
      end

      ##
      # just like pre_scripts, except ruby code that should be eval'd
      ##
      def pre_ruby_scripts
        @pre_ruby_scripts ||= user_data_as_array('pre_ruby_script')
        @pre_ruby_scripts
      end

      ##
      # just like post_scripts, except ruby code that should be eval'd
      ##
      def post_ruby_scripts
        @post_ruby_scripts ||= user_data_as_array('post_ruby_script')
        @post_ruby_scripts
      end

      ##
      # This wraps the fetching of a user-data param, and ensures
      # that the result is an (possibly empty) array
      ##
      def user_data_as_array(key)
        val = ec2_user_data(key)
        if !val || val.empty?
          val = []
        elsif !val.is_a?(Array)
          val = [val]
        end

        val
      end
      

      ##
      # The action objects that should be invoked when the list of available
      # services that we care about changes.
      #
      # 
      # The first time this is called, it tries to evaluate the +action_strs+ 
      # strings by calling eval on each of them in order to get the desired object.
      # So an action_str could be, for example, 
      # "ReframeIt::EC2::UpdateHosts.new('127.0.0.1', 'local_name')"
      #
      ##
      def actions
        if !@actions
          # make sure we've loaded all the actions we know about
          Dir.glob(File.join(File.dirname(__FILE__), 'ec2-discovery', 'actions', '*.rb')).each do |file|
            req_name = "ec2-discovery/actions/#{File.basename(file).gsub(/\.rb^/, '')}"
            info "Requiring #{req_name}"
            require req_name
          end

          @actions = []
          action_strs.each do |action_str|
            begin
              action = eval(action_str)
              if action.is_a?(ReframeIt::EC2::Action)
                @actions << action
                info { "Loaded action #{action.inspect}" }
              else
                error "Actions must inherit from ReframeIt::EC2::Action, but #{action.inspect} does not!"
              end
            rescue Exception => ex
              error "Error trying to eval #{action_str}", ex
            end
          end
        end

        @actions
      end


      ##
      # manually set the list of services provided by this instance, 
      # rather than having to look in the ec2 user-data
      ##
      def provides=(services)
        @provides = services
        if !@provides.is_a?(Array)
          @provides = [@provides]
        end
      end

      ##
      # manually set the list of services this instance is interested in,
      # rather than having to look in the ec2 user-data
      ##
      def subscribes=(services)
        @subscribes = services
        if !@subscribes.is_a?(Array)
          @subscribes = [@subscribes]
        end
      end

      ##
      # manually set the list of actions this instance should take,
      # rather than having to look in the ec2 user-data
      ##
      def action_strs=(actions)
        @action_strs = actions
        if !@action_strs.is_a?(Array)
          @action_strs = [@action_strs]
        end
      end

      ##
      # the user-data supplied name for the internal ipv4 address
      #
      # may be a string or an array of strings
      ##
      def local_name
        ec2_user_data('local_name', 'local_name')
      end

      ##
      # the user-data supplied name for the external ipv4 address
      #
      # may be a string or an array of strings
      ##
      def public_name
        ec2_user_data('public_name', 'public_name')
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

