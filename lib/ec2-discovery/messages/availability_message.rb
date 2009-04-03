require 'ec2-discovery/message'

module ReframeIt
  module EC2

    ##
    # This message indicates that services are now available/unavailable
    # on a given (internal) ip address
    #
    # The +ttl+ for an availability message should be longer than 
    # the time between sending availability updates. If no message
    # is received within +ttl+ seconds, then the service can be
    # considered down
    ##
    class AvailabilityMessage < Message
      attr_accessor :services, :ipv4addr, :available, :ttl

      def self.serialized_attributes
        [:services, :ipv4addr, :available, :ttl]
      end

      ##
      # == Params: ==
      #  +services+ - array of services that are (un)available
      #               the service names may include port specifiers of the 
      #               form :port or :port1-port2
      #  +ipv4addr+ - the ip address of the services
      #  +available+ - whether or not the services are available
      #  +ttl+ - time-to-live seconds, after which others may consider
      #          these services down if no new availability messages
      #          are received
      ##
      def initialize(services=[], ipv4addr='', available = true, ttl = 10)
        @services = services
        @ipv4addr = ipv4addr
        @available = available
        @ttl = ttl
      end
    end

  end
end
