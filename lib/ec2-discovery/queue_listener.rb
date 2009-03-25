module ReframeIt
  module EC2
    class QueueListener
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
          while @keep_going
            while (sqs_msg = sqs_queue.receive) && @keep_going
              begin
                msg = JSON.parse sqs_msg.body
                process(msg)
                sqs_msg.delete
              rescue Exception => ex
                STDERR.puts "Exception occurred trying to process message #{sqs_msg.inspect}: #{ex}\n\t#{ex.backtrace.join("\n\t")}"
              end
            end
            
            sleep wait_time
          end
        end
        return listen_thread
      end

      ##
      # Stops the listening thread. It should take at most +wait_time+
      # seconds from the time this is called for the thread to terminate.
      ##
      def stop
        @keep_going = false
      end

    end
  end
end
