#!/usr/bin/ruby

# require 'github_api'
require 'git'
require 'fileutils'
require 'uglifier'

Phonegap_dir = "/home/geopeers/phonegap/geopeers"
Webapp_dir   = "#{Phonegap_dir}/webapp"

def create_concat_file (dir, type, files=nil)
  master_filename = "geopeers.#{type}"
  master_pathname = "#{dir}/#{master_filename}"
  if ! files
    # collect all the files (! dirs) in dir
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
  dir = "#{Webapp_dir}/geopeers/public/#{type}"
  files = ['jquery-1.11.1.js', 'jquery-ui.js', 'jquery.mobile-1.4.5.js',
           'jquery.ui.map.js', 'markerwithlabel.js', 'md5.js',
           'jquery.dataTables.js', 'jquery-ui-timepicker-addon.js',
           'jstz.js', 'db.js', 'menu.js',
#           'gps.js',
#           'geo.js',
          ]
  create_concat_file(dir, type, files)

  master_pathname = "#{dir}/geopeers.#{type}"
  uglified, source_map = Uglifier.new.compile_with_map(File.read(master_pathname))

  master_min_filename = "geopeers.min.#{type}"
  write_file("#{dir}/#{master_min_filename}", uglified)

  master_map_filename = "geopeers.min.map"
  write_file("#{dir}/#{master_map_filename}", source_map)

  FileUtils.cp("#{dir}/geo.js", "#{Phonegap_dir}/#{type}")
  FileUtils.cp("#{dir}/gps.js", "#{Phonegap_dir}/#{type}")
end

def css
  type = 'css'
  dir = "#{Webapp_dir}/geopeers/public/#{type}"
  files = ['jquery.mobile-1.4.5.min.css', 'geo.css', 'jquery.dataTables.css']
  create_concat_file(dir, type, files)
end

def write_phonegap_index_html
  html = create_index({is_phonegap: true, is_production: true})
  output_file = "#{Phonegap_dir}/index.html"
  File.open(output_file, 'w') { |file| file.write(html) }
end

def edit_config_xml
  config_xml_file = "#{Phonegap_dir}/config.xml"
  config_xml = File.read(config_xml_file)
  build_id = get_build_id()
  puts build_id
  config_xml.sub! /versionCode\s*=\s*"\d+"/, "versionCode = \"#{build_id}\""
  version = get_version
  puts version
  # Search for d.d.d, not [.d]+ so we don't match the xml version attribute
  config_xml.sub! /<widget\s+version\s*=\s*"\d+\.\d+\.?\d*"/, "<widget version = \"#{version}\""
  File.open(config_xml_file, 'w') { |file| file.write(config_xml) }
end

def run_cmd cmd
  puts cmd
  result = `#{cmd}`
  puts result
  result
end

def pull_webapp
  github_rep = 'https://github.com/scottkaplan/geopeers'
  cmd = "cd #{Webapp_dir}; rm -rf *; git clone #{github_rep}"
  run_cmd (cmd)
end

def copy_local_assets
  for asset_type in ['images', 'images/res', 'images/res/ios', 'images/res/android']
    puts asset_type

    phonegap_subdir = "#{Phonegap_dir}/#{asset_type}"
    FileUtils.rm_r phonegap_subdir if File.exists? phonegap_subdir
    FileUtils.mkdir phonegap_subdir

    webapp_subdir = "#{Webapp_dir}/geopeers/public/#{asset_type}"

    Dir.foreach (webapp_subdir) { |filename|
      webapp_filename = "#{webapp_subdir}/#{filename}"
      next if File.directory?(webapp_filename)

      phonegap_filename = "#{phonegap_subdir}/#{filename}"

      FileUtils.cp(webapp_filename, phonegap_filename)
    }
  end
  # make sure JS and CSS files are refreshed
  js_file  = "#{Webapp_dir}/geopeers/public/js/geopeers.min.js"
  FileUtils.cp(js_file,  "#{Phonegap_dir}/js")
  css_file = "#{Webapp_dir}/geopeers/public/css/geopeers.css"
  FileUtils.cp(css_file, "#{Phonegap_dir}/css")

  # upload to production
  cmd = "cd #{Phonegap_dir}; /usr/bin/scp -i /home/geopeers/.ssh/geopeers css/geopeers.css geopeers.com:src/public/css"
  run_cmd cmd
  cmd = "cd #{Phonegap_dir}; /usr/bin/scp -i /home/geopeers/.ssh/geopeers js/geopeers.min.js geopeers.com:src/public/js"
  run_cmd cmd
end

def update_phonegap_repo
  cmd = "cd #{Phonegap_dir}; git commit -a -m 'Phonegap'"
  run_cmd cmd
  github_rep = 'https://scott@kaplans.com:scottkaplan1@github.com/scottkaplan/geopeers_phonegap'
  puts "Username is 'scott@kaplans.com', password is 'scottkaplan1'"
  cmd = "cd #{Phonegap_dir}; git push"
  run_cmd cmd
end

def build
  puts "Pull webapp repo"
  pull_webapp()

  require "#{Webapp_dir}/geopeers/geo.rb"
  init()

  puts "Write Phonegap index.html"
  write_phonegap_index_html()

  puts "Create integrated/minified JS"
  js()

  puts "Create integrated/minified CSS"
  css()

  puts "Edit config XML"
  edit_config_xml()

  puts "Copy local assets"
  copy_local_assets()

  puts "Update Phonegap repo"
  update_phonegap_repo()

  # unlock phonegap certs
  # start phonegap build and wait
  # download ios and apk to distribution server
  # upload apk to Google Play
  
  puts "Done"
end

build()
