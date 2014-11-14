#!/usr/bin/ruby

require '/home/geopeers/sinatra/geopeers/geo.rb'
require 'fileutils'


def write_index_html
  html = create_index()
  target_dir = "/home/geopeers/sinatra/geopeers/public"
  output_file = "#{target_dir}/index.html"
  File.open(output_file, 'w') { |file| file.write(html) }
end

write_index_html

