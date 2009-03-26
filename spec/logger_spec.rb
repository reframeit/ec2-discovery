require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')
require 'ec2-discovery/logger'

include ReframeIt::EC2::Logger

describe "Logger" do
  describe "default" do
    it "should not be nil" do
      logger.should_not be_nil
    end

    it "should be a ::Logger" do
      logger.class.should == ::Logger
    end
  end

  describe "info" do
    it "should log a message and not throw an exception" do
      info_msg = 'this is an info message'
      logger.should_receive(:add).with(::Logger::INFO, info_msg)
      info(info_msg)
    end

    it "should evaluate blocks at the time of logging" do
      a = 0
      info_block = Proc.new{"value is #{a += 1}"}
      a.should == 0
      info &info_block
      a.should == 1
    end

    it "should log exceptions" do
      my_ex = nil

      # grab a nice stacktrace
      begin
        raise Exception.new('my_ex')
      rescue Exception => ex
        my_ex = ex
      end

      logger.should_receive(:add).with(::Logger::INFO, "msg1")
      logger.should_receive(:add).with(::Logger::INFO, "msg2")
      logger.should_receive(:add).with(::Logger::INFO, my_ex)
      info("msg1", "msg2", my_ex)
    end
  end

  describe "debug" do
    it "should log a message and not throw an exception" do
      debug_msg = 'this is a debug message'
      logger.should_receive(:add).with(::Logger::DEBUG, debug_msg)
      debug(debug_msg)
    end
  end

  describe "singleton" do
    it "should always have the same Logger instance" do
      class A
        include ReframeIt::EC2::Logger
        attr_reader :my_logger
        def initialize
          @my_logger = logger
        end
      end

      class B
        include ReframeIt::EC2::Logger
        attr_reader :my_logger
        def initialize
          @my_logger = logger
        end
      end

      A.new.my_logger.object_id.should == B.new.my_logger.object_id
    end
  end
end

