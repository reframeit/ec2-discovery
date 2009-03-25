require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'
require 'ec2-discovery/messages/availability_message'

module ReframeIt
  module EC2
    ##
    # This processor keeps track of service availabilities
    ##
    class AvailabilityProcessor < MessageProcessor
      def initialize
        super(AvailabilityMessage)

        # hash of service name => Array<available ipv4 addresses>
        @available = {}
      end

      def process_impl(msg)
        if msg.available
          msg.services.each do |service|
            @available[service] ||= []
            @available[service] << msg.ipv4addr if !@available[service].include?(msg.ipv4addr)
          end
        else
          msg.services.each do |service|
            @available[service].delete(msg.ipv4addr) if @available[service]
          end
        end
      end

      ##
      # gets the current list of available ipv4 addresses for the given service
      #
      # Returns: an array (possibly empty) of ipv4 addresses (as strings)
      ##
      def ipv4addrs(service)
        @available[service] || []
      end

    end
  end
end
