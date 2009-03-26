require 'rubygems'
require 'json'
require 'ec2-discovery/logger'

module ReframeIt
  module EC2
    ##
    # Message is the base class for all our messages that will
    # be serialized and put on the queue. It contains methods for
    # serializing/deserializing the data.
    #
    # == Subclassing ==
    # Subclasses should override serialized_attributes, and must also
    # provide a parameterless constructor 
    # (or a constructor that can be called with no params)
    ##
    class Message
      include ReframeIt::EC2::Logger

      ##
      # the attributes we want to serialize on the queue
      # This should be overridden for subclasses
      #
      # returns: Array
      ##
      def self.serialized_attributes
        warn "serialized_attributes called on base ReframeIt::EC2::Message class!"
        []
      end

      def self.json_create(o)
        obj = eval("#{o['json_class']}.new")
        o['data'].each do |attr, val|
          obj.send("#{attr}=", val)
        end

        obj
      end

      def to_json(*a)
        data = {}
        self.class.serialized_attributes.each do |attr|
          data[attr] = self.send(attr)
        end

        {
          'json_class' => self.class.name,
          'data' => data
        }.to_json(*a)
      end
    end

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
      def initialize(services='', ipv4addr='', available = true)
        @services = services
        @ipv4addr = ipv4addr
        @available = available
      end
    end
    
  end
end
