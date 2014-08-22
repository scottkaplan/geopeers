#!/usr/bin/ruby

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

set :public_folder, 'public'
class Sighting < ActiveRecord::Base
end
class Device < ActiveRecord::Base
end
class Beacon < ActiveRecord::Base
end
class Share < ActiveRecord::Base
end
class Redeem < ActiveRecord::Base
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
  db_str = "#{db_config['adapter']}://#{db_config['username']}:#{db_config['password']}@#{db_config['host']}:#{db_config['port']}/#{db_config['database']}"
  set :database, db_str
#  ActiveRecord::Base.establish_connection(
#                                          :adapter  => db_config.adapter,
#                                          :database => 'geopeers',
#                                          :host     => 'db.geopeers.com',
#                                          :username => 'geopeers',
#                                          :password => 'ullamco1'
#                                          )
#  $DB_SPEC = ActiveRecord::Base.specification
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

  def Protocol.create_share_url (share, params)
    "http://www.geopeers.com/api?cred="+share.share_cred
  end

  def Protocol.format_expire_time (share, params)
    return unless share.expire_time
    expire_time = share.expire_time.in_time_zone(params['tz'])
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

  def Protocol.create_share_msg (share, params)
    device = Device.where("device_id=?", params['device_id']).first
    url = Protocol.create_share_url(share, params)
    expire_time = Protocol.format_expire_time(share, params)
    name = device.name
    if (share.share_via == 'sms')
      template_file = 'views/text_msg.erb'
    else
      require 'securerandom'
      boundary_random = SecureRandom.base64(21)
      template_file = 'views/email_body.erb'
      msg_erb = File.read(template_file)
      html_body = ERB.new(msg_erb).result(binding)
      require 'mail'
      quoted_html_body = Mail::Encodings::QuotedPrintable.encode(html_body)
      template_file = 'views/email_msg.erb'
    end
    msg_erb = File.read(template_file)
    ERB.new(msg_erb).result(binding)
  end

  def Protocol.send_share_sms (share, params)
    sms_obj = Sms.new;
    msg = Protocol.create_share_msg(share, params)
    err = sms_obj.send(share.share_to, msg)
    if (err)
      {'message' => err, 'style' => {'color' => 'red'}}
    else
      {'message' => 'Location Shared', 'style' => {'color' => 'blue'}}
    end
  end

  def Protocol.send_share_email (share, params)
    $LOG.debug share
    $LOG.debug params
    device = Device.where("device_id=?", params['device_id']).first
    $LOG.debug device

    
    subject = "#{device.name} shared a location with you"
    from = "#{device.name} <#{device.email}>"
    to = share.share_to
    msg = "From: #{from}\nTo: #{to}\nSubject: #{subject}\n"
    msg += Protocol.create_share_msg(share, params)
    begin
      Net::SMTP.start('127.0.0.1') do |smtp|
        smtp.send_message msg, device.email, share.share_to
      end
    rescue Exception => e  
      $LOG.error e
      {'message' => 'There was a problem sending your email.  Support has been contacted', 'style' => {'color' => 'red'}}
    end  
    {'message' => 'Email sent', 'style' => {'color' => 'blue'}}
  end

  def Protocol.send_share_facebook (share, params)
    {message: "Facebook shares are not implemented yet"}
  end

  def Protocol.send_share_twitter (share, params)
    {message: "Twitter shares are not implemented yet"}
  end

  def Protocol.send_share (share, params)
    $LOG.debug (share)
    procname = 'send_share_' + share['share_via']
    if (defined? procname)
      (method procname).call(share, params)
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
      if (params['location'])
        longitude = params['location']['longitude']
        latitude  = params['location']['latitude']
      else
        longitude = params['gps_longitude']
        latitude = params['gps_latitude']
      end

      sighting = Sighting.new(device_id:     params['device_id'],
                              gps_longitude: longitude,
                              gps_latitude:  latitude,
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
    # Go through all the redeems with our device_id
    # get the associated shares and the device_id in the shares
    # return sightings of that device_id
    sql = "SELECT shares.device_id, shares.id
           FROM shares, redeems
           WHERE redeems.device_id = '#{params["device_id"]}' AND
                 shares.id = redeems.share_id AND
                 NOW() < shares.expire_time
          "
    device_ids = []
    Share.find_by_sql(sql).each { |share|
      $LOG.debug share.id
      device_ids.push(share.device_id)
    }

    return if (device_ids.length == 0)
    begin
      device_ids_str = device_ids.collect {|did| Share.sanitize(did)}.join(',')
      $LOG.debug device_ids_str
      sql = "SELECT devices.name, sightings.device_id, sightings.gps_longitude, sightings.gps_latitude, MAX(sightings.updated_at) AS max_updated_at
             FROM sightings, devices
             WHERE sightings.device_id IN (#{device_ids_str}) AND
                   sightings.device_id = devices.device_id AND
                   devices.name IS NOT NULL
             GROUP BY sightings.device_id"
      $LOG.debug sql
      elems = []
      Sighting.find_by_sql(sql).each { |row|
        elems.push ({ 'name'          => row.name,
                      'device_id'     => row.device_id,
                      'gps_longitude' => row.gps_longitude,
                      'gps_latitude'  => row.gps_latitude,
                      'sighting_time' => row.max_updated_at,
                      # 'expire_time'   => share.expire_time,
                    })
      }
      $LOG.debug elems
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
      {'message' => 'Device Registered<br>You can share your location now by pressing the flying pin', 'style' => {'color' => 'blue'}}
    else
      # This shouldn't happen.  If there is a device_id, it should be in the DB
      # Script kiddies?
      $LOG.error ("No record for "+params['device_id'])
      error_response "Unknown device ID"
    end
  end

  def Protocol.process_request_share_location (params)
    # create a share and send it
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
    share = Share.new(expire_time:  expire_time,
                      device_id:    params["device_id"],
                      share_via:    params["share_via"],
                      share_to:     params["share_to"],
                      share_cred:   share_cred,
                      num_uses_max: params["num_uses"],
                      )
    share.save
    Protocol.send_share(share, params)
  end

  def Protocol.process_request_cred (params)
    # a share URL has been clicked
    # using the cred, create a redeem
    share = Share.where("share_cred=?",params["cred"]).first
    $LOG.debug share
    redirect_url = 'https://geopeers.com'

    if (! share)
      msg = "That credential is not valid.  You can't view the location.  You can still use the other features of GeoPeers"
      msg = URI.escape (msg)
      redirect_url += "?alert=#{msg}"
    elsif (! share.num_uses_max || share.num_uses < share.num_uses_max)	# null num_uses_max -> unlimited uses
      # it's a good share

      # does params['device_id'] (seer) already have access to a share for share.device_id (seen)
      sql = "SELECT shares.expire_time, redeems.id AS redeem_id FROM shares, redeems
             WHERE shares.device_id  = '#{share.device_id}' AND
                   redeems.device_id = '#{params['device_id']}' AND
                   redeems.share_id  = shares.id AND
                   NOW() < shares.expire_time
            "
      current_share = Share.find_by_sql(sql).first
      $LOG.debug current_share
      $LOG.debug sql
      if (current_share)
        if ( ! current_share.expire_time ||
             current_share.expire_time >= share.expire_time)
          # this current_share expires after the new share, ignore the new share
          $LOG.debug "using existing share"
          return {:redirect_url => redirect_url}
        else
          # the new share expires after the current share, update the redeem with the new share
          $LOG.debug "updating redeem with new share"
          redeem = Redeem.find (current_share.redeem_id)
        end
      else
        $LOG.debug "no existing share"
        redeem = Redeem.new(share_id:  share.id,
                            device_id: params["device_id"])
      end
      $LOG.debug redeem
      redeem.save
      share.num_uses = share.num_uses ? share.num_uses+1 : 1
      share.save
    end
    {:redirect_url => redirect_url}
  end

  def Protocol.process_request_get_shares (params)
    begin
      # get a list of device_ids that are registered with the same device.email as params['device_id']
      # and create a comma-separate list, suitable for putting in the SQL IN clause
      device = Device.find_by(device_id: params['device_id'])
      devices = Device.select("device_id").where(email: device.email)
      device_ids = devices.map { |device_row| device_row.device_id }
      device_ids_str = device_ids.collect {|did| Device.sanitize(did)}.join(',')
      $LOG.debug device_ids_str

      # get all the shares with those device_ids
      # and a list of the device_id that redeemed the shares
      sql = "SELECT shares.share_to, shares.share_via, devices.name, shares.expire_time,
                    shares.updated_at, shares.created_at,
                    redeems.id AS redeem_id,
                    redeems.device_id AS redeem_name,
                    redeems.created_at AS redeem_time
             FROM shares
             LEFT JOIN devices ON shares.device_id = devices.device_id
             LEFT JOIN redeems ON shares.id = redeems.share_id
             WHERE shares.device_id IN (#{device_ids_str})
            "
      # Find the names associated with the redeemed device_ids
      elems = []
      Share.find_by_sql(sql).each { |row|
        if (row.redeem_name)
          # at this point, it is not redeem_name, it's really the device_id
          device = Device.find_by(device_id: row.redeem_name)
          # Now it's the redeem name :-)
          row[:redeem_name] = device.name
        end
        elems.push (row)
      }
      {'shares' => elems }
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

  def get_device_id ()
    # The device_id is stored in the client's cookie
    # retrieve it if one already has been assigned,
    # create and send a new device_id if one was not sent by the client
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
    params['device_id'] = params['device_id'] ? params['device_id'] : get_device_id()
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
    if (request.content_type == 'application/json')
        params.merge!(JSON.parse(request.body.read))
    end
    params['device_id'] = params['device_id'] ? params['device_id'] : get_device_id()
    params['user_agent'] = request.user_agent
    resp = Protocol.process_request params
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

  ['/', '/geo/?'].each do |path|
    get path do
      if request.secure?
        # we don't need the device_id to build the page
        # but we do want to make sure the client gets a device_id
        # in case they don't have one
        params['device_id'] = get_device_id()
        erb :index
      else
        redirect request.url.gsub(/^http/, "https")
      end
    end
  end

  after do
    # if we don't do this,
    # bad things when we run under passenger
    ActiveRecord::Base.clear_active_connections!
  end

end

init()
