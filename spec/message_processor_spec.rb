require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'

class MyMessage < ReframeIt::EC2::Message
  attr_accessor :myfield1
  def self.serialized_attributes
    [:myfield1]
  end

  def initialize(myfield1= '')
    @myfield1 = myfield1
  end
end

class MyMessageProcessor < ReframeIt::EC2::MessageProcessor
  attr_accessor :processed

  def initialize
    super(MyMessage)
    @processed = false
  end

  def process(msg)
    @processed = true
  end
end

describe ReframeIt::EC2::MessageProcessor do
  describe "process" do
    it "should process a message when given a block" do
      processed = false

      proc = ReframeIt::EC2::MessageProcessor.new(MyMessage) do |msg|
        processed = true
      end

      proc.process(MyMessage.new('val'))

      processed.should be_true
    end

    it "should process a message when subclassed and overridden" do 
      proc = MyMessageProcessor.new
      proc.process(MyMessage.new('val1'))
      proc.processed.should be_true
    end
  end
end

