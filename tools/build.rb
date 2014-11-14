#!/usr/bin/ruby

require '/home/geopeers/sinatra/geopeers/geo.rb'
require 'fileutils'
require 'uglifier'

def write_index_html
  html = create_index()
  target_dir = "/home/geopeers/sinatra/geopeers/public"
  output_file = "#{target_dir}/index.html"
  File.open(output_file, 'w') { |file| file.write(html) }
end

def create_concat_file (dir, type, files=nil)
  master_filename = "geopeers.#{type}"
  master_pathname = "#{dir}/#{master_filename}"
  if ! files
    files = []
    Dir.foreach(dir) { |filename|
      next if /^geopeers\..*/.match(filename)
      next if File.directory?(filename)
      files.push (filename)
    }
  end
  master_file = File.open(master_pathname, 'w')
  files.each { |filename|
    f = File.open("#{dir}/#{filename}")
    master_file.write (f.read)
    f.close
  }
  master_file.close
end

def write_file (pathname, contents)
  f = File.open(pathname, "w")
  f.write (contents)
  f.close
end

def js
  type = 'js'
  dir = "/home/geopeers/sinatra/geopeers/public/#{type}"
  files = ['jquery-1.11.1.js', 'jquery-ui.js', 'jquery.mobile-1.4.5.js',
           'jquery.ui.map.js', 'markerwithlabel.js', 'md5.js',
           'jquery.dataTables.js', 'jquery-ui-timepicker-addon.js',
           'jstz.js', 'db.js', 'menu.js', 'geo.js', 'gps.js']
  create_concat_file(dir, type, files)

  master_pathname = "#{dir}/geopeers.#{type}"
  uglified, source_map = Uglifier.new.compile_with_map(File.read(master_pathname))

  master_min_filename = "geopeers.min.#{type}"
  write_file("#{dir}/#{master_min_filename}", uglified)

  master_map_filename = "geopeers.min.map"
  write_file("#{dir}/#{master_map_filename}", source_map)
end

def css
  type = 'css'
  dir = "/home/geopeers/sinatra/geopeers/public/#{type}"
  files = ['jquery.mobile-1.4.5.min.css', 'geo.css', 'jquery.dataTables.css']
  create_concat_file(dir, type, files)
end

def main
  write_index_html
  js()
  css()
end

main
