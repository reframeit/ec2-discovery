require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/queue_listener'
require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'

class MyMessage < ReframeIt::EC2::Message
  attr_accessor :myfield1
  def self.serialized_attributes
    [:myfield1]
  end

  def initialize(myfield1)
    @myfield1 = myfield1
  end
end
class MyMessage2 < MyMessage
  attr_accessor :myfield1, :myfield2
  def self.serialized_attributes
    [:myfield1, :myfield2]
  end

  def initialize(myfield1, myfield2)
    @myfield1 = myfield1
    @myfield2 = myfield2
  end
end

describe ReframeIt::EC2::QueueListener do
  describe "process" do
    it "should send a message to all relevant processors" do
      queue = ReframeIt::EC2::QueueListener.new(nil)
      proc1_called = false
      proc2_called = false

      proc1 = ReframeIt::EC2::MessageProcessor.new(MyMessage) do |msg|
        proc1_called = true
      end

      proc2 = ReframeIt::EC2::MessageProcessor.new(MyMessage2) do |msg|
        proc2_called = true
      end

      queue.add_processor(proc1)
      queue.add_processor(proc2)

      msg = MyMessage2.new('value1', 'value2')

      queue.process(msg)
      
      proc1_called.should be_true
      proc2_called.should be_true
    end

    it "should not send messages to irrelevant processors" do
      queue = ReframeIt::EC2::QueueListener.new(nil)
      proc1_called = false
      proc2_called = false

      proc1 = ReframeIt::EC2::MessageProcessor.new(MyMessage) do |msg|
        proc1_called = true
      end

      proc2 = ReframeIt::EC2::MessageProcessor.new(MyMessage2) do |msg|
        proc2_called = true
      end

      queue.add_processor(proc1)
      queue.add_processor(proc2)

      msg = MyMessage.new('value1')

      queue.process(msg)
      
      proc1_called.should be_true
      proc2_called.should be_false
    end

  end
end

