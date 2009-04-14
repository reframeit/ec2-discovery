require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/messages/availability_message'
require 'ec2-discovery/messages/subscription_message'

describe ReframeIt::EC2::AvailabilityMessage do
  describe "serialization" do
    it "should serialize to json" do
      msg = ReframeIt::EC2::AvailabilityMessage.new(['service1', 'service2'], '127.0.0.1', false)
      json = msg.to_json
      json.should_not be_nil
      json.should_not be_empty
    end

    it "should deserialize from serialized json" do
      msg = ReframeIt::EC2::AvailabilityMessage.new(['service1', 'service2'], '127.0.0.1', false)
      json = msg.to_json
      msg2 = JSON.parse json
      msg2.class.should == ReframeIt::EC2::AvailabilityMessage
      msg2.services.should == ['service1', 'service2']
      msg2.ipv4addr.should == '127.0.0.1'
      msg2.available.should be_false
      msg2.timestamp.to_i.should be_close Time.now.to_i, 3
    end
  end
end

