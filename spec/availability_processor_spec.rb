require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/message_processors/availability_processor'

include ReframeIt::EC2

describe ReframeIt::EC2::AvailabilityProcessor do
  describe "availabile" do
    before(:each) do
      @proc = ReframeIt::EC2::AvailabilityProcessor.new
    end

    it "should be empty initially" do
      @proc.available('some_service').should be_empty
    end

    it "should contain addresses for available services" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2','service3'], '2.3.4.5'))
      
      @proc.available('service1').should == [ServiceAddress.new('1.2.3.4')]
      @proc.available('service2').should == [ServiceAddress.new('1.2.3.4'),ServiceAddress.new('2.3.4.5')]
      @proc.available('service3').should == [ServiceAddress.new('2.3.4.5')]
    end

    it "should not contain addresses for unavailable services" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2', 'service3'], '1.2.3.4', false))
      
      @proc.available('service1').should == [ServiceAddress.new('1.2.3.4')]
      @proc.available('service2').should == []
      @proc.available('service3').should == []
    end

    it "should keep port information" do
      @proc.process(AvailabilityMessage.new(['service1:101','service2:102'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2:202','service3:203'], '2.3.4.5'))
      
      @proc.available('service1').should == [ServiceAddress.new('1.2.3.4', ':101')]
      @proc.available('service2').should == [ServiceAddress.new('1.2.3.4', ':102'),ServiceAddress.new('2.3.4.5', '202')]
      @proc.available('service3').should == [ServiceAddress.new('2.3.4.5', '203')]
    end

  end

  describe "all_available" do
    before(:each) do 
      @proc = ReframeIt::EC2::AvailabilityProcessor.new
    end

    it "should be empty initially" do
      @proc.all_available.should be_empty
    end

    it "should contain the available addresses" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service1','service2'], '2.3.4.5'))

      @proc.all_available.has_key?('1.2.3.4').should be_true
      @proc.all_available.has_key?('2.3.4.5').should be_true
    end

    it "should not contain unavailable ip addresses" do
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service1','service2'], '2.3.4.5'))
      @proc.process(AvailabilityMessage.new(['service1','service2'], '1.2.3.4', false))

      @proc.all_available.has_key?('2.3.4.5').should be_true
      @proc.all_available.has_key?('1.2.3.4').should be_false
    end

    it "should map ip addresses to the available services at those addresses" do
      @proc.process(AvailabilityMessage.new(['service1'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service3'], '2.3.4.5'))
      @proc.process(AvailabilityMessage.new(['service1'], '2.3.4.5'))

      @proc.all_available['1.2.3.4'].should == ['service1','service2']
      @proc.all_available['2.3.4.5'].should == ['service1','service3']
    end

    it "should not map ip addresses to unavailable services at those addresses" do
      @proc.process(AvailabilityMessage.new(['service1'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service2'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service1'], '1.2.3.4', false))
      @proc.process(AvailabilityMessage.new(['service3'], '2.3.4.5'))
      @proc.process(AvailabilityMessage.new(['service1'], '2.3.4.5'))

      @proc.all_available['1.2.3.4'].should == ['service2']
      @proc.all_available['2.3.4.5'].should == ['service1','service3']
    end

    it "should map service names to hostnames with two digits appended to the service name" do
      @proc.process(AvailabilityMessage.new(['service'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service'], '2.3.4.5'))

      @proc.all_available(true)['1.2.3.4'].should == ['service01']
      @proc.all_available(true)['2.3.4.5'].should == ['service02']
    end

    it "should keep port information when requested" do
      @proc.process(AvailabilityMessage.new(['service:80'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service:81'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service:80'], '2.3.4.5'))

      @proc.all_available(true, true)['1.2.3.4'].should == ['service01:80', 'service01:81']
      @proc.all_available(true, true)['2.3.4.5'].should == ['service02:80']
    end

    it "should be consistent with hostnames" do
      @proc.process(AvailabilityMessage.new(['service'], '1.2.3.4'))

      @proc.all_available(true)['1.2.3.4'].should == ['service01']

      @proc.process(AvailabilityMessage.new(['service'], '2.3.4.5'))

      @proc.all_available(true)['1.2.3.4'].should == ['service01']
      @proc.all_available(true)['2.3.4.5'].should == ['service02']

      @proc.process(AvailabilityMessage.new(['service'], '3.4.5.6'))
      @proc.all_available(true)['1.2.3.4'].should == ['service01']
      @proc.all_available(true)['2.3.4.5'].should == ['service02']
      @proc.all_available(true)['3.4.5.6'].should == ['service03']

      # this is a redundant message and should be ignored by the processor
      @proc.process(AvailabilityMessage.new(['service'], '3.4.5.6'))
      @proc.all_available(true)['1.2.3.4'].should == ['service01']
      @proc.all_available(true)['2.3.4.5'].should == ['service02']
      @proc.all_available(true)['3.4.5.6'].should == ['service03']
      @proc.all_available(true).size.should == 3
    end

  end


  describe "availability_changes" do
    before(:each) do 
      @proc = ReframeIt::EC2::AvailabilityProcessor.new
    end

    it "should be called when the availability list changes" do 
      called = false
      @proc.availability_changed = Proc.new do |avail_proc|
        called = true
      end

      @proc.process(AvailabilityMessage.new(['service'], '1.2.3.4'))
      called.should be_true

      called = false
      @proc.process(AvailabilityMessage.new(['service'], '2.3.4.5'))
      called.should be_true

      called = false
      @proc.process(AvailabilityMessage.new(['service_b'], '1.2.3.4'))
      called.should be_true

      called = false
      @proc.process(AvailabilityMessage.new(['service'], '1.2.3.4', false))
      called.should be_true
    end

    it "should not be called when the availability list does not change" do

      @proc.process(AvailabilityMessage.new(['service_a', 'service_b'], '1.2.3.4'))
      @proc.process(AvailabilityMessage.new(['service_c'], '1.2.3.4'))

      called = false
      @proc.availability_changed = Proc.new do |avail_proc|
        called = true
      end

      @proc.process(AvailabilityMessage.new(['service_a'], '1.2.3.4'))
      called.should be_false

      @proc.process(AvailabilityMessage.new(['service_b', 'service_c'], '1.2.3.4'))
      called.should be_false
    end
  end

end

