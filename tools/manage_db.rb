#!/usr/bin/ruby

require '/home/geopeers/sinatra/geopeers/geo.rb'

class Db
  @@conn = Mysql2::Client.new(:database => 'geopeers',
                              :host     => 'db.geopeers.com',
                              :username => 'geopeers',
                              :password => 'ullamco1')

  def Db.create_datestamp
    d = DateTime.now()
    d.strftime("%Y%m%d")
  end
  
  def self.tables (db)
    rows = @@conn.query "SHOW TABLES IN #{db}";
    tables = []
    rows.each do |row|
      tables.push (row["Tables_in_#{db}"])
    end
    tables
  end

  def self.backup (db)
    datestamp = Db.create_datestamp
    begin
      backup_db = "#{db}_#{datestamp}"
      @@conn.query "CREATE DATABASE IF NOT EXISTS #{backup_db}"
      self.tables(db).each { |table|
        puts "backup #{table}"
        @@conn.query "CREATE TABLE IF NOT EXISTS #{backup_db}.#{table} LIKE geopeers.#{table}";
        @@conn.query "INSERT IGNORE INTO #{backup_db}.#{table} SELECT * FROM geopeers.#{table}";
      }
    rescue Exception => e
      puts "DB Error: #{e}"
    end
  end

  def self.empty (db)
    begin
      self.tables(db).each { |table|
        next if table == 'schema_migrations'
        next if table == 'globals'
        puts "empty #{table}"
        @@conn.query "TRUNCATE TABLE #{table}";
      }
    rescue Exception => e
      puts "DB Error: #{e}"
    end
  end
end

def main
  if ARGV[0]
    if ARGV[0] == 'backup'
      Db.backup ('geopeers')
    elsif ARGV[0] == 'empty'
      Db.empty ('geopeers')
    elsif ARGV[0] == 'tables'
      tables = Db.tables ('geopeers')
      puts tables
    end
  else
    puts "{ 'backup' | 'empty' | 'tables' }"
  end
end


main()
