require 'right_aws'
require 'sqs/right_sqs_gen2'

module RightAws
  class SqsGen2
    def initialize(aws_access_key=nil, aws_secret_access_key=nil, params={})
      @queues = {}
    end

    def queue(queue_name, create=true, visibility=nil)
      if !@queues[queue_name] && create
        @queues[queue_name] = Queue.new
      end

      return @queues[queue_name]
    end

    class Queue
      attr_reader :name, :url, :sqs
      attr_accessor :visibility
      
      def initialize(sqs=nil, url_or_name=nil)
        @msgs = []
      end
      
      def size
        @msgs.length
      end
      
      def clear
        @msgs.clear
      end
      
      def delete
        @msgs.clear
      end
      def send_message(message)
        msg = Message.new(self, '0000000', nil, message.to_s)
        @msgs << msg
      end
      alias_method :push, :send_message
      
      def receive_messages(num = 1, visibility = nil)
        msgs = @msgs[0..(num-1)]
        return msgs
      end
      def receive(visibility=nil)
        list = receive_messages(1, visibility)
        list.empty? ? nil : list[0]
      end
      def pop
        return @msgs.shift
      end
      
      def set_attribute(attribute, value)
        value
      end
      
      def get_attribute(attribute='All')
        nil
      end
      
    end
  

    
  end
end
