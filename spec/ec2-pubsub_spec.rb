require File.join(File.dirname(__FILE__), 'helpers', 'spec_helper')

describe ReframeIt::EC2::Discovery do
  before(:all) do 
    @discovery = ReframeIt::EC2::Discovery.new('aws_id', 'secret_key')
  end

  def inject_ec2_user_data_str(user_data_str)
    # first clear the @user_data hash
    @discovery.instance_eval("@user_data = nil")
    
    # then inject a new unparsed data string
    @discovery.instance_eval("@user_data_str = '#{user_data_str}'")
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
end
