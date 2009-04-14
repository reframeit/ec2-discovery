require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/queue_listener'
require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'

class MyMessage < ReframeIt::EC2::Message
  attr_accessor :myfield1
  def self.serialized_attributes
    [:myfield1]
  end

  def initialize(myfield1='')
    @myfield1 = myfield1
  end
end
class MyMessage2 < MyMessage
  attr_accessor :myfield1, :myfield2
  def self.serialized_attributes
    [:myfield1, :myfield2]
  end

  def initialize(myfield1='', myfield2='')
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
    
    it "should skip old messages" do
      queue = ReframeIt::EC2::QueueListener.new(nil, 1, 5)
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

      old_msgs = []
      10.times do |i|
        old_msg = MyMessage.new("value#{i}")
        old_msg.timestamp = Time.now - 10
        old_msgs << old_msg

        old_msg = MyMessage2.new("value#{i}")
        old_msg.timestamp = Time.now - 10
        old_msgs << old_msg
      end

      queue.process(old_msgs)
      
      proc1_called.should be_false
      proc2_called.should be_false

      queue.process(MyMessage.new("value1"))
      proc1_called.should be_true
      proc2_called.should be_false

      queue.process(MyMessage2.new("value2"))
      proc2_called.should be_true
    end
  end

  describe "listen" do
    before(:each) do
      # this is our mock sqs
      @sqs = RightAws::SqsGen2.new()
      @queue = @sqs.queue('test-queue')
    end

    it "should process any available messages as they come in" do
      queue_listener = ReframeIt::EC2::QueueListener.new(@queue)
      @msgs = []
      my_proc = ReframeIt::EC2::MessageProcessor.new(MyMessage) do |msg|
        @msgs << msg
      end
      queue_listener.add_processor(my_proc)

      listening_thread = queue_listener.listen
      @queue.send_message(MyMessage.new('msg1').to_json)
      @queue.send_message(MyMessage.new('msg2').to_json)

      sleep 2
      queue_listener.stop
      sleep 2
      
      @msgs.size.should == 2
      @msgs.first.myfield1.should == 'msg1'
      @msgs.last.myfield1.should == 'msg2'
    end
  end
end

