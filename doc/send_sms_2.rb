[magtogo.com@chula-vista geo]$ grep -R 4567 *
INSTALL:shotgun --port 4567 --host 0.0.0.0
public/geo.js~:    var url = "http://www.geopeers.com:4567/api";
[magtogo.com@chula-vista geo]$ ruby geo.rb
[2014-07-23 04:56:02] INFO  WEBrick 1.3.1
[2014-07-23 04:56:02] INFO  ruby 2.0.0 (2014-02-24) [x86_64-linux]
== Sinatra/1.4.5 has taken the stage on 4567 for development with backup from WEBrick
[2014-07-23 04:56:02] INFO  WEBrick::HTTPServer#start: pid=5354 port=4567
  C-c C-c== Sinatra has ended his set (crowd applauds)
[2014-07-23 04:56:04] INFO  going to shutdown ...
[2014-07-23 04:56:04] INFO  WEBrick::HTTPServer#start done.
[magtogo.com@chula-vista geo]$ perl geo.rb
Semicolon seems to be missing at geo.rb line 23.
Semicolon seems to be missing at geo.rb line 24.
syntax error at geo.rb line 2, near "require "
Unterminated <> operator at geo.rb line 25.
[magtogo.com@chula-vista geo]$ ruby geo.rb
[2014-07-23 05:21:47] INFO  WEBrick 1.3.1
[2014-07-23 05:21:47] INFO  ruby 2.0.0 (2014-02-24) [x86_64-linux]
== Sinatra/1.4.5 has taken the stage on 4567 for development with backup from WEBrick
[2014-07-23 05:21:47] INFO  WEBrick::HTTPServer#start: pid=5886 port=4567
  C-c C-c== Sinatra has ended his set (crowd applauds)
[2014-07-23 05:21:51] INFO  going to shutdown ...
[2014-07-23 05:21:51] INFO  WEBrick::HTTPServer#start done.
[magtogo.com@chula-vista geo]$ ruby test.rb
test.rb:7:in `<main>': undefined local variable or method `done' for main:Object (NameError)
[magtogo.com@chula-vista geo]$ ruby test.rb
done
[magtogo.com@chula-vista geo]$ ruby test.rb
No device ID
done
[magtogo.com@chula-vista geo]$ ruby geo.rb
geo.rb:191: syntax error, unexpected tIDENTIFIER, expecting ')'
                        share_via: params["share_via"],
                                 ^
geo.rb:192: syntax error, unexpected tLABEL, expecting '='
                        share_to: params["share_to"],
                                 ^
geo.rb:193: syntax error, unexpected tLABEL, expecting '='
                        shar_cred: share_cred,
                                  ^
[magtogo.com@chula-vista geo]$ ruby geo.rb
geo.rb:190: syntax error, unexpected tIDENTIFIER, expecting ')'
                        share_via: params["share_via"],
                                 ^
geo.rb:191: syntax error, unexpected tLABEL, expecting '='
                        share_to: params["share_to"],
                                 ^
geo.rb:192: syntax error, unexpected tLABEL, expecting '='
                        shar_cred: share_cred,
                                  ^
[magtogo.com@chula-vista geo]$ ruby geo.rb
[2014-07-23 05:32:36] INFO  WEBrick 1.3.1
[2014-07-23 05:32:36] INFO  ruby 2.0.0 (2014-02-24) [x86_64-linux]
== Sinatra/1.4.5 has taken the stage on 4567 for development with backup from WEBrick
[2014-07-23 05:32:36] INFO  WEBrick::HTTPServer#start: pid=6123 port=4567
  C-c C-c== Sinatra has ended his set (crowd applauds)
[2014-07-23 05:32:38] INFO  going to shutdown ...
[2014-07-23 05:32:38] INFO  WEBrick::HTTPServer#start done.
[magtogo.com@chula-vista geo]$ ruby geo.rb
geo.rb:25: syntax error, unexpected keyword_end, expecting ';' or '\n'
geo.rb:26: syntax error, unexpected keyword_end, expecting ';' or '\n'
geo.rb:27: syntax error, unexpected keyword_end, expecting ';' or '\n'
geo.rb:305: syntax error, unexpected end-of-input, expecting keyword_end
[magtogo.com@chula-vista geo]$ bin/rails generate migration AddField1ToBeacons share_cred:string
[1m[37m      invoke[0m  active_record
[1m[32m      create[0m    db/migrate/20140723054625_add_field1_to_beacons.rb
[magtogo.com@chula-vista geo]$ bundle exec rake db:migrate
== 20140723054625 AddField1ToBeacons: migrating ===============================
-- add_column(:beacons, :share_cred, :string)
   -> 0.2149s
== 20140723054625 AddField1ToBeacons: migrated (0.2151s) ======================

[magtogo.com@chula-vista geo]$ ruby geo.rb
[2014-07-23 05:47:53] INFO  WEBrick 1.3.1
[2014-07-23 05:47:53] INFO  ruby 2.0.0 (2014-02-24) [x86_64-linux]
== Sinatra/1.4.5 has taken the stage on 4567 for development with backup from WEBrick
[2014-07-23 05:47:53] INFO  WEBrick::HTTPServer#start: pid=6452 port=4567
  C-c C-c== Sinatra has ended his set (crowd applauds)
[2014-07-23 05:47:55] INFO  going to shutdown ...
[2014-07-23 05:47:55] INFO  WEBrick::HTTPServer#start done.
[magtogo.com@chula-vista geo]$ ls
app  config	db	 Gemfile~      geo.rb	INSTALL  Rakefile     send_sms.rb~  test.rb   views
bin  config.ru	Gemfile  Gemfile.lock  geo.rb~	public	 send_sms.rb  test	    test.rb~
[magtogo.com@chula-vista geo]$ cat > send_sms.rb
#!/usr/bin/env ruby
require 'net/https'
require 'uri'

url = URI.parse('https://app.eztexting.com/api/sending')

#prepare post data
req = Net::HTTP::Post.new(url.path)
req.set_form_data({'user'=>'username', 'pass'=>'userpassword' , 'phonenumber'=>'2125551234', 'subject'=>'test', 'message'=>'test message', 'express'=>'1'})


http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true if url.scheme == "https"  # enable SSL/TLS
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
http.start {
  http.request(req) {|res|
    puts res.body
  }
}

[magtogo.com@chula-vista geo]$ ruby send_sms.rb
1
[magtogo.com@chula-vista geo]$ sudo gem install eztexting
Fetching: multi_xml-0.5.5.gem (100%)
Successfully installed multi_xml-0.5.5
Fetching: httparty-0.13.1.gem (100%)
When you HTTParty, you must party hard!
Successfully installed httparty-0.13.1
Fetching: eztexting-0.3.4.gem (100%)
Successfully installed eztexting-0.3.4
Parsing documentation for eztexting-0.3.4
Installing ri documentation for eztexting-0.3.4
Parsing documentation for httparty-0.13.1
Installing ri documentation for httparty-0.13.1
Parsing documentation for multi_xml-0.5.5
Installing ri documentation for multi_xml-0.5.5
Done installing documentation for eztexting, httparty, multi_xml after 2 seconds
3 gems installed
[magtogo.com@chula-vista geo]$ yardoc
bash: yardoc: command not found
[magtogo.com@chula-vista geo]$ rdoc eztexting
Parsing sources...
100% [87/87]  views/index.erb~                                                                      

Generating Darkfish format into /home/magtogo.com/sinatra/geo/doc...

  Files:      87

  Classes:    31 (31 undocumented)
  Modules:     3 ( 3 undocumented)
  Constants:   1 ( 1 undocumented)
  Attributes:  0 ( 0 undocumented)
  Methods:    41 (20 undocumented)

  Total:      76 (55 undocumented)
   27.63% documented

  Elapsed: 1.6s

[magtogo.com@chula-vista geo]$ cd doc
[magtogo.com@chula-vista doc]$ ls
ActiveRecord.html	    DevicesController.html	Protocol.html
AddField1ToBeacons.html     DevicesControllerTest.html	public
AddIndexToDevices.html	    DevicesHelper.html		Rakefile.html
AddTheseToBeacons.html	    DevicesHelperTest.html	rdoc.css
AddThis2ToBeacons.html	    DeviceTest.html		RemoveTheseFromBeacons.html
AddThis3ToBeacons.html	    fonts			RemoveThis2FromBeacons.html
app			    fonts.css			RemoveThis3FromBeacons.html
Beacon.html		    Gemfile~.html		RemoveThis4FromDevices.html
BeaconsController.html	    Gemfile.html		RemoveThisFromBeacons.html
BeaconsControllerTest.html  Gemfile_lock.html		Show
BeaconsHelper.html	    geo_rb~.html		Show.html
BeaconsHelperTest.html	    images			Sighting.html
BeaconTest.html		    index.html			SightingsController.html
config			    INSTALL.html		SightingsControllerTest.html
config_ru.html		    js				SightingsHelper.html
CreateBeacons.html	    Net				SightingsHelperTest.html
CreateDevices.html	    Net.html			SightingTest.html
created.rid		    Object.html			table_of_contents.html
CreateSightings.html	    OpenSSL			test_rb~.html
db			    OpenSSL.html		views
Device.html		    ProtocolEngine.html
[magtogo.com@chula-vista doc]$ 