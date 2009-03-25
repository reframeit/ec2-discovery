require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/message_processors/subscription_processor'

include ReframeIt::EC2

describe ReframeIt::EC2::SubscriptionProcessor do
  describe "response_queues" do
    before(:each) do
      @proc = ReframeIt::EC2::SubscriptionProcessor.new
    end

    it "should be empty initially" do
      @proc.response_queues('some_service').should be_empty
    end

    it "should contain queues for subscribed services" do
      @proc.process(SubscriptionMessage.new(['service1','service2'], 'queue1'))
      @proc.process(SubscriptionMessage.new(['service2','service3'], 'queue2'))
      
      @proc.response_queues('service1').should == ['queue1']
      @proc.response_queues('service2').should == ['queue1','queue2']
      @proc.response_queues('service3').should == ['queue2']
    end

    it "should not contain subscriptions for unsubscribed services" do
      @proc.process(SubscriptionMessage.new(['service1','service2'], 'queue1'))
      @proc.process(SubscriptionMessage.new(['service2', 'service3'], 'queue1', false))
      
      @proc.response_queues('service1').should == ['queue1']
      @proc.response_queues('service2').should == []
      @proc.response_queues('service3').should == []
    end

  end
end

