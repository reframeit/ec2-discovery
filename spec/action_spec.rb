require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')

require 'ec2-discovery/actions/update_hosts'

describe ReframeIt::EC2::UpdateHosts do
  it "should be able to get the correct value for local_ipv4" do
    discovery1 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    discovery2 = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
    
    discovery1.stub!(:ec2_user_data).and_return('')
    discovery2.stub!(:ec2_user_data).and_return('')
    
    discovery1.stub!(:provides).and_return(['monitor','service_a'])
    discovery1.stub!(:subscribes).and_return([])
    
    discovery2.stub!(:provides).and_return(['service_b'])
    discovery2.stub!(:subscribes).and_return(['service_a'])

    discovery2.stub!(:action_strs).and_return(['UpdateHosts.new(local_ipv4, local_name, public_ipv4, public_name)'])
    
    discovery1.stub!(:local_ipv4).and_return('1.1.1.1')
    discovery2.stub!(:local_ipv4).and_return('2.2.2.2')
    discovery1.stub!(:instance_id).and_return('discovery1')
    discovery2.stub!(:instance_id).and_return('discovery2')

    discovery2.should_receive(:local_name).and_return('discovery2_local')
    discovery2.should_receive(:public_ipv4).and_return('1.2.3.4')
    discovery2.should_receive(:public_name).and_return('discovery2_public')
    
    discovery2.actions.first.class.should == ReframeIt::EC2::UpdateHosts
    discovery2.actions.first.should_receive(:invoke).at_least(:once)
    
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
