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
    # All messages have a timestamp, which is in unix time.
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

      ##
      # unix timestamp
      ##
      def timestamp
        @timestamp ||= Time.now.to_i
        @timestamp
      end

      ##
      # sets the timestamp.
      # to_i will be called on the object given, so it acceptable
      # to pass a Time object here.
      ##
      def timestamp=(ts)
        @timestamp = ts.to_i
      end

      def to_json(*a)
        data = {}
        self.class.serialized_attributes.each do |attr|
          data[attr] = self.send(attr)
        end

        data[:timestamp] = timestamp

        {
          'json_class' => self.class.name,
          'data' => data
        }.to_json(*a)
      end
    end

  end
end
