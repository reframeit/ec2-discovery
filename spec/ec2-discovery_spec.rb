require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')

describe ReframeIt::EC2::Discovery do
  before(:each) do 
    @discovery = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    @discovery.sqs.reset
  end

  def inject_ec2_user_data_str(user_data_str, discovery = nil)
    discovery ||= @discovery

    # first clear the @user_data hash
    discovery.instance_eval("@user_data = nil")
    
    # then inject a new unparsed data string
    discovery.instance_eval("@user_data_str = '#{user_data_str}'")
  end

  # tests the string parsing
  describe "parse_user_data_str" do
    it "should parse empty string" do
      h = @discovery.parse_user_data_str("")
      h.should be_empty
    end

    it "should parse single key=value pair" do
      h = @discovery.parse_user_data_str("key=value")
      h.should_not be_empty
      h['key'].should == 'value'
    end

    it "should parse multiple key=value pairs" do
      h = @discovery.parse_user_data_str("key1=value1\nkey2=value2")
      h.should_not be_empty
      h.size.should == 2
      h['key1'].should == 'value1'
      h['key2'].should == 'value2'
    end
    it "shouls skip comments" do
      h = @discovery.parse_user_data_str("key1=value1\n # here is a comment\nkey2=value2")
      h.should_not be_empty
      h.size.should == 2
      h['key1'].should == 'value1'
      h['key2'].should == 'value2'
    end

    it "should skip bad lines" do
      h = @discovery.parse_user_data_str("key1=value1\nbad line here!\nkey2=value2")
      h.should_not be_empty
      h.size.should == 2
      h['key1'].should == 'value1'
      h['key2'].should == 'value2'
    end

    it "should group multiple occurrances into an array" do
      h = @discovery.parse_user_data_str("key1=value1a\nkey1=value1b\nkey2=value2")
      h.should_not be_empty
      h.size.should == 2
      h['key1'].class.should == Array
      h['key1'].size.should == 2
      h['key1'].first.should == 'value1a'
      h['key1'].last.should == 'value1b'
      h['key2'].should == 'value2'
    end
  end

  # tests the logic that calls the string parsing
  describe "ec2_user_data" do
    it "should give me the correct value" do
      inject_ec2_user_data_str("key1=value1\nkey2=value2")
      @discovery.ec2_user_data('key1').should == 'value1'
      @discovery.ec2_user_data('key2').should == 'value2'
    end

    it "should give me the default value when there is no value" do
      inject_ec2_user_data_str("key1=value1")
      @discovery.ec2_user_data('key2', 'default value').should == 'default value'
    end

    it "should give me an array when there are multiple values" do
      inject_ec2_user_data_str("key1=value1a\nkey1=value1b")
      @discovery.ec2_user_data('key1').should == ['value1a', 'value1b']
    end
  end

  describe "monitor" do
    it "should receive existing subscription messages" do
      @discovery.should_not_receive(:update_hosts)
      msg = ReframeIt::EC2::SubscriptionMessage.new(['service1'], 'response_queue1', true)
      @discovery.send_message(@discovery.monitor_queue, msg)
      @discovery.monitor_queue.size.should == 1
      monitor_thread = @discovery.monitor
      sleep 2
      @discovery.monitor_queue.size.should == 0
    end

    it "should receive existing availability messages" do
      @discovery.should_receive(:update_hosts).once
      msg = ReframeIt::EC2::AvailabilityMessage.new(['service1'], '1.2.3.4', true)
      @discovery.send_message(@discovery.monitor_queue, msg)
      @discovery.monitor_queue.size.should == 1
      monitor_thread = @discovery.monitor
      sleep 2
      @discovery.monitor_queue.size.should == 0
    end

    it "should receive new subscription messages" do
      @discovery.should_not_receive(:update_hosts)
      monitor_thread = @discovery.monitor
      sleep 1
      msg = ReframeIt::EC2::SubscriptionMessage.new(['service1'], 'response_queue1', true)
      @discovery.send_message(@discovery.monitor_queue, msg)
      @discovery.monitor_queue.size.should == 1
      sleep 1
      @discovery.monitor_queue.size.should == 0
    end

    it "should receive new availability messages" do
      @discovery.should_receive(:update_hosts).once
      monitor_thread = @discovery.monitor
      sleep 1

      msg = ReframeIt::EC2::AvailabilityMessage.new(['service1'], '1.2.3.4', true)
      @discovery.send_message(@discovery.monitor_queue, msg)
      @discovery.monitor_queue.size.should == 1
      sleep 1
      @discovery.monitor_queue.size.should == 0
    end

    it "should send availability messages to interested subscribers" do
      @discovery.stub!(:update_hosts)
      @discovery.stub!(:local_ipv4).and_return('1.2.3.4')
      monitor_thread = @discovery.monitor
      sleep 1
      sub_msg = ReframeIt::EC2::SubscriptionMessage.new(['service1'], 'response_queue1', true)
      avail_msg = ReframeIt::EC2::AvailabilityMessage.new(['service1'], '1.2.3.4', true)

      @discovery.send_message(@discovery.monitor_queue, sub_msg)
      sleep 1
      @discovery.send_message(@discovery.monitor_queue, avail_msg)
      sleep 1
      @discovery.sqs.queue('response_queue1').size.should == 1

      received_msg = JSON.parse(@discovery.sqs.queue('response_queue1').pop.body)
      received_msg.available.should be_true
      received_msg.ipv4addr.should == '1.2.3.4'
      received_msg.services.should == ['service1']
    end

    it "should send an unavailable message to interested subscribers when a service is no longer available" do
      @discovery.stub!(:update_hosts)
      @discovery.stub!(:local_ipv4).and_return('1.2.3.4')
      monitor_thread = @discovery.monitor
      sleep 1
      sub_msg = ReframeIt::EC2::SubscriptionMessage.new(['service1'], 'response_queue1', true)
      avail_msg = ReframeIt::EC2::AvailabilityMessage.new(['service1'], '1.2.3.4', true, 3)

      @discovery.send_message(@discovery.monitor_queue, sub_msg)
      @discovery.send_message(@discovery.monitor_queue, avail_msg)
      sleep 1
      @discovery.sqs.queue('response_queue1').pop.should_not be_nil
      sleep 2*avail_msg.ttl
      @discovery.sqs.queue('response_queue1').size.should == 1
      msg = JSON.parse(@discovery.sqs.queue('response_queue1').pop.body)
      msg.available.should be_false
      msg.ipv4addr.should == '1.2.3.4'
      msg.services.should == ['service1']
    end
  end

  describe "run" do
    it "should allow two hosts to coordinate availability" do
      discovery1 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
      discovery2 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
      
      discovery1.stub!(:ec2_user_data).and_return('')
      discovery2.stub!(:ec2_user_data).and_return('')

      discovery1.stub!(:provides).and_return(['monitor','service_a'])
      discovery1.stub!(:subscribes).and_return([])

      discovery2.stub!(:provides).and_return(['service_b'])
      discovery2.stub!(:subscribes).and_return(['service_b'])

      discovery1.stub!(:local_ipv4).and_return('1.1.1.1')
      discovery2.stub!(:local_ipv4).and_return('2.2.2.2')
      discovery2.stub!(:instance_id).and_return('discovery2')

      discovery1.should_receive(:update_hosts).at_least(:once) { |avail_proc|
        all_ips = avail_proc.all_ipv4addrs(true)
        all_ips.has_key?('1.1.1.1').should be_true
        all_ips.has_key?('2.2.2.2').should be_true
        all_ips['1.1.1.1'].include?('monitor01').should be_true
        all_ips['1.1.1.1'].include?('service_a01').should be_true
        all_ips['2.2.2.2'].include?('service_b01').should be_true
      }
      
      discovery2.should_receive(:update_hosts).at_least(:once) { |avail_proc|
        all_ips = avail_proc.all_ipv4addrs(true)
        all_ips.has_key?('1.1.1.1').should be_true
        all_ips.has_key?('2.2.2.2').should be_false # we're not subscribing to our own services
        all_ips['1.1.1.1'].should == ['service_a01']
      }
      
      thread1 = Thread.new do
        discovery1.run
      end

      thread2 = Thread.new do
        discovery2.run
      end

      sleep 5
      thread1.kill
      thread2.kill      
    end
  end

end
