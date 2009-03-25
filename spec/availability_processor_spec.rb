require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/message_processors/availability_processor'

include ReframeIt::EC2

describe ReframeIt::EC2::AvailabilityProcessor do
  describe "ipv4addrs" do
    before(:each) do
      @proc = ReframeIt::EC2::AvailabilityProcessor.new
    end

    it "should be empty initially" do
      @proc.ipv4addrs('some_service').should be_empty
    end

    it "should contain addresses for available services" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2','service3'], '2.3.4.5'))
      
      @proc.ipv4addrs('service1').should == ['1.2.3.4']
      @proc.ipv4addrs('service2').should == ['1.2.3.4','2.3.4.5']
      @proc.ipv4addrs('service3').should == ['2.3.4.5']
    end

    it "should not contain addresses for unavailable services" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2', 'service3'], '1.2.3.4', false))
      
      @proc.ipv4addrs('service1').should == ['1.2.3.4']
      @proc.ipv4addrs('service2').should == []
      @proc.ipv4addrs('service3').should == []
    end

  end
end

