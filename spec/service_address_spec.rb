require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/service_address'

include ReframeIt::EC2

describe ReframeIt::EC2::ServiceAddress do
  describe "initialize" do
    it "should add a colon to the beginning of a port if it is missing" do
      ServiceAddress.new('1.2.3.4', '80').port.should == ':80'
      ServiceAddress.new('1.2.3.4', '80-85').port.should == ':80-85'
    end

    it "should not add a color to the beginning of a port if it is present" do
      ServiceAddress.new('1.2.3.4', ':80').port.should == ':80'
      ServiceAddress.new('1.2.3.4', ':80-85').port.should == ':80-85'
    end
  end

  describe "==" do
    it "should be true when both ips and ports match" do
      ServiceAddress.new('1.2.3.4', ':80').should == ServiceAddress.new('1.2.3.4', ':80')
    end

    it "should be false when ips match but ports don't" do
      ServiceAddress.new('1.2.3.4', ':80').should_not == ServiceAddress.new('1.2.3.4', ':81')
    end

    it "should be false when ips don't match but ports do" do
      ServiceAddress.new('1.2.3.4', ':80').should_not == ServiceAddress.new('1.1.1.1', ':80')
    end

    it "should be false when neither ips nor ports match" do
      ServiceAddress.new('1.2.3.4', ':80').should_not == ServiceAddress.new('1.1.1.1', ':81')
    end
    
    it "should be true when ips are nil and ports match" do
      ServiceAddress.new(nil, ':80').should == ServiceAddress.new(nil, ':80')
    end

    it "should be true when ips match and ports are nil" do
      ServiceAddress.new('1.2.3.4', nil).should == ServiceAddress.new('1.2.3.4', nil)
    end
    it "should be true when both ips and ports are nil" do
      ServiceAddress.new(nil, nil).should == ServiceAddress.new(nil, nil)
    end

    it "should be false when ips are nil and ports don't match" do
      ServiceAddress.new(nil, ':80').should_not == ServiceAddress.new(nil, ':81')
    end

    it "should be false when ips don't match and ports are nil" do
      ServiceAddress.new('1.2.3.4', nil).should_not == ServiceAddress.new('1.1.1.1', nil)
    end
  end

  describe "eql?" do
    it "should be true when both ips and ports match" do
      ServiceAddress.new('1.2.3.4', ':80').eql?(ServiceAddress.new('1.2.3.4', ':80')).should be_true
    end

    it "should be false when ips match but ports don't" do
      ServiceAddress.new('1.2.3.4', ':80').eql?(ServiceAddress.new('1.2.3.4', ':81')).should be_false
    end

    it "should be false when ips don't match but ports do" do
      ServiceAddress.new('1.2.3.4', ':80').eql?(ServiceAddress.new('1.1.1.1', ':80')).should be_false
    end

    it "should be false when neither ips nor ports match" do
      ServiceAddress.new('1.2.3.4', ':80').eql?(ServiceAddress.new('1.1.1.1', ':81')).should be_false
    end    
  end

  describe "hash" do
    it "should allow use as a key in a Hash" do
      s1 = ServiceAddress.new('1.2.3.4', ':80')
      s2 = ServiceAddress.new('1.2.3.4', ':80')
      s3 = ServiceAddress.new('1.1.1.1')
      s4 = ServiceAddress.new('1.1.1.1')

      h = {}
      h[s1] = 1
      h[s2] += 1
      h[s3] = 10
      h[s4] += 1
      
      h.size.should == 2
      h[s1].should == 2
      h[s3].should == 11
    end
  end

end

