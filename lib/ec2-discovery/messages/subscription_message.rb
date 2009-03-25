require 'ec2-discovery/message'

module ReframeIt
  module EC2

    ##
    # This type of message indicates that this instance is interested
    # in any changes to the listed set of services, and will be listening
    # on the given queue for responses. It should receive initial messages
    # indicating all the known available services as well as any updates.
    #
    # This can also be used to unsubscribe, for example, when a subscriber
    # no longer seems to exist.
    ##
    class SubscriptionMessage < Message
      attr_accessor :services, :response_queue, :subscribe

      def self.serialized_attributes
        [:services, :response_queue, :subscribe]
      end

      ##
      # == Params: ==
      #  +services+ - the services that this instance is interested in
      #  +response_queue+ - the queue that this instance will be listening on
      ##
      def initialize(services=[], response_queue='', subscribe = true)
        @services = services
        @response_queue = response_queue
        @subscribe = subscribe
      end
    end
  end
end
