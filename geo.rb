require 'sinatra'
require 'sinatra/activerecord'
require 'json'
require 'erb'
require 'logger'
require 'yaml'
require 'date'
require 'eztexting'
require 'net/smtp'
require 'uri'

# TODO

#   View Beacons table - Name, Status (active, unopened, expires), Last Viewed, Expires

#   create test plan w/multiple devices

#   spin up eng1.geopeers.com
#   setup on port 80 through apache/passenger

#   Use HTML5 web workers to send position in background

#   app with webview and send_position in background
#   select contact from list

#   make beacon.share_cred UNIQUE
#   Permissions:
#     allow seer to view seen history
#     allow seen to view seer viewed history
#     allow seer to know that seen is watching
#   share location via facebook and twitter
#   use symbols instead of strings in hashs

set :public_folder, 'public'
class Sighting < ActiveRecord::Base
end
class Device < ActiveRecord::Base
end
class Beacon < ActiveRecord::Base
end

class Sms
  def initialize
    Eztexting.connect!('magtogo', 'Codacas')
  end

  def send (num, msg)
    options = {
      :message => msg,
      :phonenumber => num,
    }
    msg = Eztexting::Sms.single(options).first
    return if msg == "Message sent"
    return msg
  end
end

def init
  $LOG = Logger.new(STDOUT)
  # $LOG = Logger.new(log_file, 'daily')
  $LOG.datetime_format = "%Y-%m-%d %H:%M:%S.%L"
  $LOG.formatter = proc { |severity, datetime, progname, msg|
    path, line, method = caller[4].split(/(?::in `|:|')/)
    whence = $:.detect { |p| path.start_with?(p) }
    if whence
      file = path[whence.length + 1..-1]
    else
      # We get here if the path is not in $:
      file = path
    end
    "[#{datetime.strftime($LOG.datetime_format)} #{severity} #{file}:#{line}]: #{msg.inspect}\n"
  }
  db_config = YAML::load_file('config/database.yml')
  set :database, "#{db_config['adapter']}://#{db_config['username']}:#{db_config['password']}@#{db_config['host']}:#{db_config['port']}/#{db_config['database']}"

end

class Protocol

  private

  def Protocol.compute_expire_time (params)
    multiplier = {
      'minute' => 1,
      'hour'   => 60,
      'day'    => 60*24,
      'week'   => 60*24*7
    }
    raise ArgumentError.new("No share unit")   unless params.has_key?('share_duration_unit')
    return if params['share_duration_unit'] == 'manual'
    raise ArgumentError.new("No share number") unless params.has_key?('share_duration_number')
    raise ArgumentError.new("No multiplier")   unless multiplier.has_key?(params['share_duration_unit'])
    multiplier[params['share_duration_unit']] * params['share_duration_number'].to_i * 60
  end

  def Protocol.create_share_url (beacon, params)
    "http://geopeers.com/api?cred="+beacon.share_cred
  end

  def Protocol.format_expire_time (beacon, params)
    return unless beacon.expire_time
    expire_time = beacon.expire_time.in_time_zone(params['tz'])
    now = Time.now.in_time_zone(params['tz'])

    if (expire_time.year != now.year)
      "on " + expire_time.strftime("%d %B, %Y at %I:%M %p")
    elsif (expire_time.month != now.month)
      "on " + expire_time.strftime("%d %B, at %I:%M %p")
    elsif (expire_time.day != now.day)
      if (expire_time.day == now.day+1)
        "tomorrow at " + expire_time.strftime("%I:%M %p")
      else
        "on " + expire_time.strftime("%d %B, at %I:%M %p")
      end
    else
      "today at " + expire_time.strftime("%I:%M %p")
    end
  end

  def Protocol.create_share_msg (beacon, params)
    device = Device.where("device_id=?", params['device_id']).first
    url = Protocol.create_share_url(beacon, params)
    expire_time = Protocol.format_expire_time(beacon, params)
    name = device.name
    if (beacon.share_via == 'sms')
      template_file = 'views/text_msg.erb'
    else
      template_file = 'views/email_msg.erb'
    end
    msg_erb = File.read(template_file)
    ERB.new(msg_erb).result(binding)
  end

  def Protocol.send_beacon_sms (beacon, params)
    sms_obj = Sms.new;
    msg = Protocol.create_share_msg(beacon, params)
    err = sms_obj.send(beacon.share_to, msg)
    if (err)
      {'message' => err, 'style' => {'color' => 'red'}}
    else
      {'message' => 'Location Shared', 'style' => {'color' => 'blue'}}
    end
  end

  def Protocol.send_beacon_email (beacon, params)
    $LOG.debug beacon
    $LOG.debug params
    device = Device.where("device_id=?", params['device_id']).first
    $LOG.debug device
    subject = "#{device.name} shared a location with you"
    from = "#{device.name} <#{device.email}>"
    to = beacon.share_to
    msg = "From: #{from}\nTo: #{to}\nSubject: #{subject}\nContent-type: text/html\n\n"
    msg += Protocol.create_share_msg(beacon, params)
    begin
      Net::SMTP.start('127.0.0.1') do |smtp|
        smtp.send_message msg, device.email, beacon.share_to
      end
    rescue Exception => e  
      $LOG.error e
      {'message' => 'There was a problem sending your email.  Support has been contacted', 'style' => {'color' => 'red'}}
    end  
    {'message' => 'Email sent', 'style' => {'color' => 'blue'}}
  end

  def Protocol.send_beacon_facebook (beacon, params)
    {message: "Facebook beacons are not implemented yet"}
  end

  def Protocol.send_beacon_twitter (beacon, params)
    {message: "Twitter beacons are not implemented yet"}
  end

  def Protocol.send_beacon (beacon, params)
    $LOG.debug (beacon)
    procname = 'send_beacon_' + beacon['share_via']
    if (defined? procname)
      (method procname).call(beacon, params)
    else
      error_response "Bad method " + procname
    end
  end

  def Protocol.error_response (error_msg)
    # { error: error_msg, backtrace: caller }
    { 'message' => error_msg, 'style' => {'color' => 'red'}}
  end

  def Protocol.process_request_send_position (params)
    # parms: device_id, gps_*
    # returns: OK/ERROR
    begin
      sighting = Sighting.new(device_id:     params['device_id'],
                              gps_longitude: params['gps_longitude'],
                              gps_latitude:  params['gps_latitude'],
                              )
      sighting.save
      {}
    rescue => err
      error_response err.to_s
    end
  end

  def Protocol.process_request_get_positions (params)
    # params: device_id
    # returns: [{name_1, latest gps_*_1, sighting_time_1},
    #           {name_2, latest gps_*_2, sighting_time_2}, ...]
    return (error_response "No device ID") unless params.has_key?('device_id')
    # Go through all the beacons with our seer_device_id
    # get the seen_device_ids the seer_device_id has current beacons for
    device_ids = []
    Beacon.where("(expire_time IS NULL OR expire_time > NOW()) AND seer_device_id=?",params["device_id"]).each { |beacon|
      device_ids.push(beacon.seen_device_id)
    }
    return if (device_ids.length == 0)
    begin
      device_ids_str = device_ids.collect {|did| "'" + did + "'"}.join(',')
      sql = "SELECT devices.name, sightings.device_id, sightings.gps_longitude, sightings.gps_latitude, MAX(sightings.updated_at) AS max_updated_at
             FROM sightings, devices
             WHERE sightings.device_id IN (#{device_ids_str}) AND
                   sightings.device_id = devices.device_id AND
                   devices.name IS NOT NULL
             GROUP BY sightings.device_id"
      elems = []
      Sighting.find_by_sql(sql).each { |row|
        device = Device.where("device_id=?", params['device_id']).first
        elems.push ({ 'name'          => row.name,
                      'device_id'     => row.device_id,
                      'gps_longitude' => row.gps_longitude,
                      'gps_latitude'  => row.gps_latitude,
                      'sighting_time' => row.max_updated_at,
                    })
      }
      {'sightings' => elems }
    rescue => err
      error_response err.to_s
    end
  end

  def Protocol.process_request_get_registration (params)
    return (error_response "No device ID") unless params.has_key?('device_id')
      
    device = Device.where("device_id=?", params['device_id']).first
    if defined? device
      device
    else
      # This shouldn't happen.  If there is a device_id, it should be in the DB
      $LOG.error ("No record for "+params['device_id'])
      error_response "Unknown device ID"
    end
  end

  def Protocol.process_request_register_device (params)
    $LOG.debug (params.inspect)
    return (error_response "Please supply your name")  unless params.has_key?('name') && params['name'].length > 0
    return (error_response "Please supply your email") unless params.has_key?('email') && params['email'].length > 0
    return (error_response "No device ID")             unless params.has_key?('device_id') && params['device_id'].length > 0

    device = Device.where("device_id=?", params['device_id']).first
    $LOG.debug device
    if defined? device
      device.name = params['name']
      device.email = params['email']
      device.save
      {'message' => 'Device Registered', 'style' => {'color' => 'blue'}}
    else
      # This shouldn't happen.  If there is a device_id, it should be in the DB
      # Script kiddies?
      $LOG.error ("No record for "+params['device_id'])
      error_response "Unknown device ID"
    end
  end

  def Protocol.process_request_share_location (params)
    # create a beacon and send it
    begin
      raise ArgumentError.new("No share via") unless params.has_key?("share_via") && params["share_via"].length > 0
      raise ArgumentError.new("No device ID")  unless params.has_key?("device_id")
      
      raise ArgumentError.new("Please supply the address to send the share to") unless params.has_key?("share_to") && (params["share_to"].length > 0)

      if params["share_via"] == 'sms'
        raise ArgumentError.new("The phone number (share to) must be 10 digits") unless /^\d{10}$/.match(params["share_to"])
      end

      if params["share_via"] == 'email'
        # In general, RFC-822 email validation can't be done with regex
        # For now, just make sure it has an '@'
        raise ArgumentError.new("Email should be in the form 'fred@company.com'") unless /.+@.+/.match(params["share_to"])
      end
    rescue ArgumentError => e
      $LOG.debug e
      return (error_response(e.message))
    end
    require 'securerandom'
    share_cred = SecureRandom.urlsafe_base64(10)
    expire_time = compute_expire_time params
    expire_time = Time.now + expire_time if expire_time
    beacon = Beacon.new(expire_time:    expire_time,
                        seen_device_id: params["device_id"],
                        share_via:      params["share_via"],
                        share_to:       params["share_to"],
                        share_cred:     share_cred,
                        )
    beacon.save
    Protocol.send_beacon(beacon, params)
  end

  def Protocol.process_request_cred (params)
    # a share URL has been clicked
    # assign the seer's device_id to the beacon for that cred
    beacon = Beacon.where("share_cred=? AND seer_device_id IS NULL",params["cred"]).first
    $LOG.debug beacon
    redirect_url = 'http://www.geopeers.com:4567/geo'
    if ( beacon )
      beacon.seer_device_id = params['device_id']
      beacon.save
    else
      msg = "That link has already been used, but you can still use GeoPeers"
      msg = URI.escape (msg)
      redirect_url += "?alert=#{msg}"
    end
    {:redirect_url => redirect_url}
  end

  def Protocol.process_request_get_beacons (params)
    begin
      sql = "SELECT beacons.share_to, beacons.share_via, devices.name, beacons.expire_time, beacons.seer_device_id IS NOT NULL AS activated, beacons.updated_at AS activate_time, beacons.created_at
             FROM beacons
             LEFT JOIN devices ON beacons.seen_device_id = devices.device_id
             WHERE seen_device_id = '#{params['device_id']}'"
      elems = []
      Beacon.find_by_sql(sql).each { |row|
        elems.push (row)
      }
      {'beacons' => elems }
    rescue => err
      error_response err.to_s
    end
  end

  public
  def Protocol.process_request (params)
    begin
      $LOG.info (params)

      if params.has_key?('cred')
        return (method 'process_request_cred').call(params)
      end

      return (error_response "No method") unless params.has_key?('method')
      procname = 'process_request_' + params['method']
      if (defined? procname)
        (method procname).call(params)
      else
        error_response "Bad method " + procname
      end
    rescue Exception => e
      $LOG.error e
      error_response "There was a problem with your request.  Support has been contacted"
    end
  end
end

class ProtocolEngine < Sinatra::Base
  set :static, true

  def get_device_id (params)
    if (request.cookies['device_id'])
      request.cookies['device_id']
    else
      device_id = create_device_id(request.user_agent)
      response.set_cookie('device_id',
                          { :value   => device_id,
                            :domain  => 'geopeers.com',
                            :expires => Time.new(2038,1,17),
                          })
      device_id
    end
  end

  def parse_backtrace (backtrace) 
    ar = Array.new
    backtrace.each { |x|
      /(?<path>.*?):(?<line_num>\d+):in `(?<routine>.*)'/ =~ x
      file_base = File.basename(path);
      ar.push({file_base: file_base, line_num: line_num, routine: routine})
    }
    ar
  end

  def log_error_msg (resp)
    backtrace = parse_backtrace resp[:backtrace]
    backtrace_str = backtrace[0][:file_base] + ':' + backtrace[0][:line_num] + ' ' + backtrace[0][:routine]
    msg = resp[:error] + " at " + backtrace_str
    $LOG.error msg
  end

  def create_error_html (resp)
    template_file = 'views/error.erb'
    template = File.read(template_file)
    @error = resp[:error]
    @backtrace = parse_backtrace resp[:backtrace]
    @env = ENV.to_hash
    renderer = ERB.new(template)
    renderer.result(binding)
  end

  def create_device_id (user_agent)
    require 'securerandom'
    device_id = SecureRandom.uuid
    $LOG.debug device_id
    begin
      device_record = Device.new(device_id: device_id,
                                 user_agent: user_agent)
      device_record.save
    rescue => err
      $LOG.error (err)
    end
    device_id
  end

  get '/api' do
    params['device_id'] = get_device_id params
    params['user_agent'] = request.user_agent
    resp = Protocol.process_request params
    if (resp[:error])
      html = create_error_html (resp)
      halt 500, {'Content-Type' => 'text/html'}, html
    elsif (resp[:redirect_url])
      redirect resp[:redirect_url]
    else
      content_type :json
      resp.to_json
    end
  end

  post '/api' do
    params['device_id'] = get_device_id params
    params['user_agent'] = request.user_agent
    resp = Protocol.process_request params
    $LOG.debug (resp)
    if (resp && resp.class == 'Hash' && resp[:error])
      # Don't send JSON to 500 ajax response
      # resp[:error_html] = create_error_html (resp)
      # content_type :json
      # resp.to_json
      log_error_msg (resp)
      status 500
    else
      content_type :json
      resp.to_json
    end
  end

  get '/geo' do
    # we don't need the device_id to build the page
    # but we do want to make sure the client gets a device_id
    # in case they don't have one
    params['device_id'] = get_device_id params
    erb :index
  end
end

init()
