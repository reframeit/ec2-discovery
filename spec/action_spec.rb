require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')

require 'ec2-discovery/actions/update_hosts'
require 'ec2-discovery/actions/update_haproxy'

describe ReframeIt::EC2::UpdateHosts do
  it "should be able to get the correct value for local_ipv4" do
    discovery1 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    discovery2 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    
    discovery1.sqs.reset
    
    discovery1.stub!(:ec2_user_data).and_return('')
    discovery2.stub!(:ec2_user_data).and_return('')
    
    discovery1.stub!(:provides).and_return(['monitor','service_a'])
    discovery1.stub!(:subscribes).and_return([])
    
    discovery2.stub!(:provides).and_return(['service_b'])
    discovery2.stub!(:subscribes).and_return(['service_a'])

    discovery2.stub!(:action_strs).and_return(['UpdateHosts.new(local_ipv4, local_name, public_ipv4, public_name, false)'])
    
    discovery1.stub!(:local_ipv4).and_return('1.1.1.1')
    discovery2.stub!(:local_ipv4).and_return('2.2.2.2')
    discovery1.stub!(:instance_id).and_return('discovery1')
    discovery2.stub!(:instance_id).and_return('discovery2')

    discovery2.should_receive(:local_name).and_return('discovery2_local')
    discovery2.should_receive(:public_ipv4).and_return('1.2.3.4')
    discovery2.should_receive(:public_name).and_return('discovery2_public')

    discovery2.actions.size.should == 1
    discovery2.actions.first.class.should == ReframeIt::EC2::UpdateHosts
    
    # Ideally, we could just stub out invoke, but this actually tests the logic of invoke,
    # and stubbing it wasn't working (I believe because it's called on a separate thread)
    discovery2.actions.first.pretend = true

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


describe ReframeIt::EC2::UpdateHAProxy do
  it "should update and reload the haproxy config" do
    discovery1 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    discovery2 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    
    discovery1.sqs.reset

    discovery1.stub!(:ec2_user_data).and_return('')
    discovery2.stub!(:ec2_user_data).and_return('')
    
    discovery1.stub!(:provides).and_return(['monitor','service_a:4000', 'service_c'])
    discovery1.stub!(:subscribes).and_return([])
    
    discovery2.stub!(:provides).and_return(['service_b'])
    discovery2.stub!(:subscribes).and_return(['service_a', 'service_c'])

    discovery2.stub!(:action_strs).and_return(['UpdateHAProxy.new'])
    
    discovery1.stub!(:local_ipv4).and_return('1.1.1.1')
    discovery2.stub!(:local_ipv4).and_return('2.2.2.2')
    discovery1.stub!(:instance_id).and_return('discovery1')
    discovery2.stub!(:instance_id).and_return('discovery2')

    action = discovery2.actions.first
    action.class.should == ReframeIt::EC2::UpdateHAProxy

    # it may not update fully the first call, so only do checks on the last
    # document that it updates
    action.pretend = true
    action.pretend_input = ["backend service_b\n", "\n", "backend service_a\n", "\n", "backend service_c\n", "## BEGIN ec2-discovery ##\n", "  server old_server 5.5.5.5"]

    thread1 = Thread.new do
      discovery1.run
    end
    
    thread2 = Thread.new do
      discovery2.run
    end
    
    sleep 5

    reloads = action.pretend_reloads
    output = action.pretend_output

    thread1.kill
    thread2.kill

    reloads.should be >= 1
    output.should =~ /backend service_b\n\nbackend service_a\n## BEGIN ec2-discovery ##\n  server service_a01 1.1.1.1:4000 check inter 1000\n\nbackend service_c\n## BEGIN ec2-discovery ##\n  server service_c01 1.1.1.1 check inter 1000\n/

  end

  it "should remove any old entries" do
    discovery1 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    discovery2 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')

    discovery1.sqs.reset

    discovery1.stub!(:ec2_user_data).and_return('')
    discovery2.stub!(:ec2_user_data).and_return('')
    
    discovery1.stub!(:provides).and_return(['monitor','service_a'])
    discovery1.stub!(:subscribes).and_return([])
    
    discovery2.stub!(:provides).and_return(['service_b'])
    discovery2.stub!(:subscribes).and_return(['service_a'])

    discovery2.stub!(:action_strs).and_return(['UpdateHAProxy.new'])
    
    discovery1.stub!(:local_ipv4).and_return('1.1.1.1')
    discovery2.stub!(:local_ipv4).and_return('2.2.2.2')
    discovery1.stub!(:instance_id).and_return('discovery1')
    discovery2.stub!(:instance_id).and_return('discovery2')

    action = discovery2.actions.first
    action.class.should == ReframeIt::EC2::UpdateHAProxy

    # it may not update fully the first call, so only do checks on the last
    # document that it updates
    action.pretend = true
    action.pretend_input = ["backend service_b\n", "\n", "backend service_a\n", "\n", "backend service_c\n", "## BEGIN ec2-discovery ##\n", "  server old_server 5.5.5.5\n", "\n"]
    updated_file = ''
    
    thread1 = Thread.new do
      discovery1.run
    end
    
    thread2 = Thread.new do
      discovery2.run
    end
    
    sleep 5

    reloads = action.pretend_reloads
    output = action.pretend_output

    thread1.kill
    thread2.kill

    reloads.should be >= 1
    output.should =~ /backend service_b\n\nbackend service_a\n## BEGIN ec2-discovery ##\n  server service_a01 1.1.1.1 check inter 1000\n\nbackend service_c\n\n/
  end

  it "should adhere to per-service overrides" do
    discovery1 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    discovery2 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    
    discovery1.sqs.reset

    discovery1.stub!(:ec2_user_data).and_return('')
    discovery2.stub!(:ec2_user_data).and_return('')
    
    discovery1.stub!(:provides).and_return(['monitor','service_a:4000', 'service_c'])
    discovery1.stub!(:subscribes).and_return([])
    
    discovery2.stub!(:provides).and_return(['service_b'])
    discovery2.stub!(:subscribes).and_return(['service_a', 'service_c'])

    discovery2.stub!(:action_strs).and_return(['UpdateHAProxy.new("haproxy.cfg", "haproxy reload", "check inter 1000", {"service_a" => "check port 22 inter 3000"})'])
    
    discovery1.stub!(:local_ipv4).and_return('1.1.1.1')
    discovery2.stub!(:local_ipv4).and_return('2.2.2.2')
    discovery1.stub!(:instance_id).and_return('discovery1')
    discovery2.stub!(:instance_id).and_return('discovery2')

    action = discovery2.actions.first
    action.class.should == ReframeIt::EC2::UpdateHAProxy

    # it may not update fully the first call, so only do checks on the last
    # document that it updates
    action.pretend = true
    action.pretend_input = ["backend service_b\n", "\n", "backend service_a\n", "\n", "backend service_c\n", "## BEGIN ec2-discovery ##\n", "  server old_server 5.5.5.5"]

    thread1 = Thread.new do
      discovery1.run
    end
    
    thread2 = Thread.new do
      discovery2.run
    end
    
    sleep 5

    reloads = action.pretend_reloads
    output = action.pretend_output

    thread1.kill
    thread2.kill

    reloads.should be >= 1
    output.should =~ /backend service_b\n\nbackend service_a\n## BEGIN ec2-discovery ##\n  server service_a01 1.1.1.1:4000 check port 22 inter 3000\n\nbackend service_c\n## BEGIN ec2-discovery ##\n  server service_c01 1.1.1.1 check inter 1000\n/
  end
end
