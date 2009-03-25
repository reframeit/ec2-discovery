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

  describe "all_ipv4addrs" do
    before(:each) do 
      @proc = ReframeIt::EC2::AvailabilityProcessor.new
    end

    it "should be empty initially" do
      @proc.all_ipv4addrs.should be_empty
    end

    it "should contain the available ip addresses" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service1','service2'], '2.3.4.5'))

      @proc.all_ipv4addrs.has_key?('1.2.3.4').should be_true
      @proc.all_ipv4addrs.has_key?('2.3.4.5').should be_true
    end

    it "should not contain unavailable ip addresses" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service1','service2'], '2.3.4.5'))
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4', false))

      @proc.all_ipv4addrs.has_key?('2.3.4.5').should be_true
      @proc.all_ipv4addrs.has_key?('1.2.3.4').should be_false
    end

    it "should map ip addresses to the available services at those addresses" do
      @proc.process(AvailabilityMessage.new(['service1'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service3'], '2.3.4.5'))
      @proc.process(AvailabilityMessage.new(['service1'], '2.3.4.5'))

      @proc.all_ipv4addrs['1.2.3.4'].should == ['service1','service2']
      @proc.all_ipv4addrs['2.3.4.5'].should == ['service1','service3']
    end

    it "should not map ip addresses to unavailable services at those addresses" do
      @proc.process(AvailabilityMessage.new(['service1'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service1'], '1.2.3.4', false))
      @proc.process(AvailabilityMessage.new(['service3'], '2.3.4.5'))
      @proc.process(AvailabilityMessage.new(['service1'], '2.3.4.5'))

      @proc.all_ipv4addrs['1.2.3.4'].should == ['service2']
      @proc.all_ipv4addrs['2.3.4.5'].should == ['service1','service3']
    end

    it "should map service names to hostnames with two digits appended to the service name" do
      @proc.process(AvailabilityMessage.new(['service'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service'], '2.3.4.5'))

      @proc.all_ipv4addrs(true)['1.2.3.4'].should == ['service01']
      @proc.all_ipv4addrs(true)['2.3.4.5'].should == ['service02']
    end

    it "should be consistent with hostnames" do
      @proc.process(AvailabilityMessage.new(['service'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service'], '2.3.4.5'))

      @proc.all_ipv4addrs(true)['1.2.3.4'].should == ['service01']
      @proc.all_ipv4addrs(true)['2.3.4.5'].should == ['service02']

      @proc.process(AvailabilityMessage.new(['service'], '3.4.5.6'))
      @proc.all_ipv4addrs(true)['1.2.3.4'].should == ['service01']
      @proc.all_ipv4addrs(true)['2.3.4.5'].should == ['service02']
      @proc.all_ipv4addrs(true)['3.4.5.6'].should == ['service03']

      # this is a redundant message and should be ignored by the processor
      @proc.process(AvailabilityMessage.new(['service'], '3.4.5.6'))
      @proc.all_ipv4addrs(true)['1.2.3.4'].should == ['service01']
      @proc.all_ipv4addrs(true)['2.3.4.5'].should == ['service02']
      @proc.all_ipv4addrs(true)['3.4.5.6'].should == ['service03']
      @proc.all_ipv4addrs(true).size.should == 3
    end

  end
end

