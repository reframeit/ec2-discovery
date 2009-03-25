require 'rubygems'
require 'rake'
require 'echoe'
require 'spec/rake/spectask'

task :dist => [:manifest, :repackage]

Echoe.new('ec2-discovery') do |p|
  p.clean_pattern.delete('lib/*-*')
  p.ignore_pattern = Regexp.union(p.ignore_pattern, /nbproject/)
  p.ignore_pattern = Regexp.union(p.ignore_pattern, /logs/)
  p.author = 'Reframe It'
  p.summary = 'Pub/Sub discovery mechanism for EC2'
  p.runtime_dependencies = [
                            'right_aws =1.10.0',
                            'json >=1.1.2'
                           ]
  p.development_dependencies = [
                                "echoe >=3",
                                "rake =0.8.3",
                                "rspec >=1.1.11"
                               ]
end

desc "Run all rspec tests"
Spec::Rake::SpecTask.new('spec') do |t|
  t.spec_files = FileList['spec/**/*_spec.rb']
end
