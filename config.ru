require 'rubygems'
require 'sinatra'

root_dir = File.dirname(__FILE__)

set :environment, :development
set :root,  root_dir

FileUtils.mkdir_p 'log' unless File.exists?('log')
log = File.new("log/sinatra.log", "a")
$stdout.reopen(log)
$stdout.sync = true
$stderr.reopen(log)
$stderr.sync = true

disable :run, :reload

require './geo'
run ProtocolEngine.new
