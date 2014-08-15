require 'rubygems'
require 'sinatra'

root_dir = File.dirname(__FILE__)

set :environment, :development
set :root,  root_dir

# FileUtils.mkdir_p 'log' unless File.exists?('log')
# log = File.new("log/sinatra.log", "a")
# $stdout.reopen(log)
# $stdout.sync = true
# $stderr.reopen(log)
# $stderr.sync = true

ENV['GEM_PATH'] = "/home/geopeers/.gem/ruby/2.0:/usr/share/ruby/gems/2.0:/usr/local/share/ruby/gems/2.0"

disable :run, :reload

require './geo'
run ProtocolEngine.new
