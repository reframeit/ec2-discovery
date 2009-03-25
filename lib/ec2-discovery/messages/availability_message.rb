require 'ec2-discovery/message'

module ReframeIt
  module EC2

    ##
    # This message indicates that services are now available/unavailable
    # on a given (internal) ip address
    ##
    class AvailabilityMessage < Message
      attr_accessor :services, :ipv4addr, :available

      def self.serialized_attributes
        [:services, :ipv4addr, :available]
      end

      ##
      # == Params: ==
      #  +services+ - array of services that are (un)available
      #  +ipv4addr+ - the ip address of the services
      #  +available+ - whether or not the services are available
      ##
      def initialize(services=[], ipv4addr='', available = true)
        @services = services
        @ipv4addr = ipv4addr
        @available = available
      end
    end

  end
end
