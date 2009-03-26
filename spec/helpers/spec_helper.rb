require 'rubygems'
require 'spec'

$:.push(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'ec2-discovery'
require File.join(File.dirname(__FILE__), 'mock_sqs')

