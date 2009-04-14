require 'ec2-discovery/logger'

module ReframeIt
  module EC2
    class QueueListener
      include ReframeIt::EC2::Logger

      ##
      # the queue that this listener listens to
      ##
      attr_reader :sqs_queue

      ##
      # the number of seconds to wait before polling again
      # if there are no messages in the queue
      ##
      attr_accessor :wait_time

      ##
      # +sqs_queue+ The RightAws::SqsGen2::Queue that this listener listens to
      ##
      def initialize(sqs_queue, wait_time = 1)
        @sqs_queue = sqs_queue
        @wait_time = wait_time

        # a hash of message class => Array<msg processors for that class>
        @processors = {}
      end

      ##
      # adds a ReframeIt::EC2::MessageProcessor for this listener
      ##
      def add_processor(msg_processor)
        msg_clazz = msg_processor.msg_clazz

        @processors[msg_clazz] ||= []
        @processors[msg_clazz] << msg_processor
      end

      ##
      # process a single ReframeIt::EC2::Message
      ##
      def process(msg)
        clazz = msg.class

        # process all superclasses that are compatible with Message
        while clazz && clazz <= Message
          processors = @processors[clazz] || []
          processors.each do |processor|
            processor.process(msg)
          end
          clazz = clazz.superclass
        end
      end
      
      ##
      # starts this listener
      #
      # Return: the listening thread
      ##
      def listen
        @keep_going = true
        listen_thread = Thread.new do
          block_size = 10 # process this many at a time (limit is currently 10)

          while @keep_going
            sqs_msgs = nil
            begin
              info { "queue size (#{sqs_queue.name}): #{sqs_queue.size}" }
              sqs_msgs = sqs_queue.receive_messages(block_size)
              debug { "msgs retrieved: #{sqs_msgs.inspect}" }
            rescue Exception => ex
              error "Error retrieving messages from queue #{sqs_queue}", ex
            end
            if sqs_msgs && !sqs_msgs.empty? && @keep_going
              to_delete = []
              sqs_msgs.each do |sqs_msg|
                begin
                  msg = JSON.parse sqs_msg.body
                  process(msg)
                  to_delete << sqs_msg
                rescue Exception => ex
                  error "Exception occurred trying to process message #{sqs_msg.inspect}", ex
                end
              end
              to_delete.each do |sqs_msg|
                begin
                  sqs_msg.delete
                rescue Exception => ex
                  warn "Error trying to delete message #{sqs_msg.inspect}", ex
                end
              end
            end

            if !sqs_msgs || sqs_msgs.empty?
              debug { "nothing to process, so waiting #{wait_time}s" }
              sleep wait_time
            end
          end
          info { "listener stopped!" }
        end
        return listen_thread
      end

      ##
      # Stops the listening thread. It should take at most +wait_time+
      # seconds from the time this is called for the thread to terminate.
      ##
      def stop
        debug { "stop requested" }
        @keep_going = false
      end

    end
  end
end
