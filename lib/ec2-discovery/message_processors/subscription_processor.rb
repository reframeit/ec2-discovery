require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'
require 'ec2-discovery/messages/subscription_message'

module ReframeIt
  module EC2
    ##
    # This processor keeps track of subscriptions
    ##
    class SubscriptionProcessor < MessageProcessor
      def initialize
        super(SubscriptionMessage)
        
        # hash of service => Array<response queues>
        @queues = {}
      end

      def process_impl(msg)
        if msg.subscribe
          msg.services.each do |service|
            @queues[service] ||= []
            @queues[service] << msg.response_queue if !@queues[service].include?(msg.response_queue)
          end
        else
          msg.services.each do |service|
            @queues[service].delete(msg.response_queue) if @queues[service]
          end
        end
      end

      ##
      # gets the current list of the response queues for the given +service+
      #
      # Returns: an array (possibly empty) of response queue names
      ##
      def response_queues(service)
        @queues[service] || []
      end

    end
  end
end
