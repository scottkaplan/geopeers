#!/usr/bin/ruby

# The backend server for Geopeers
#
# Author:: Scott Kaplan (mailto:scott@kaplans.com)
# Copyright:: Copyright (c) 2014 Scott Kaplan

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
require 'securerandom'
require 'socket'
require 'mysql2'
# require 'pry'
# require 'pry-debugger'

set :public_folder, 'public'
ActiveRecord::Base.logger = nil
class Sighting < ActiveRecord::Base
end
class Device < ActiveRecord::Base
  before_destroy { |record|
    Sighting.destroy_all(device_id: record.device_id)
    Share.destroy_all(device_id: record.device_id)
    # Delete account if device.account_id is last reference?
  }
end
class Share < ActiveRecord::Base
  before_destroy { |share|
    Redeem.destroy_all(share_id: share.id)
  }
end
class Redeem < ActiveRecord::Base
end
class Account < ActiveRecord::Base
  before_destroy { |record|
    Device.destroy_all(account_id: record.id)
    Auth.destroy_all(account_id: record.id)
  }
end
class Auth < ActiveRecord::Base
end
class Global < ActiveRecord::Base
end

class ERBContext
  def initialize(hash)
    hash.each_pair do |key, value|
      instance_variable_set('@' + key.to_s, value)
    end
  end

  def get_binding
    binding
  end
end

class Sms
  def initialize
    Eztexting.connect!('magtogo', 'Codacas')
  end

  def Sms.clean_num(num)
    num.gsub(/[\s\-\(\)]/,'')
  end

  def send (num, msg)
    options = {
      :message => msg,
      :phonenumber => Sms.clean_num(num),
    }
    msg = Eztexting::Sms.single(options).first
    return if msg == "Message sent"
    return msg
  end
end

def clear_shares (device_id)
  # delete all the shares that track device_id
  Share.where("device_id=?",device_id).find_each do |share|
    share.destroy
  end
end

def clear_redeems (device_id, share_id)
  Redeem.where("share_id=? AND device_id=?",share_id, TEST_VALUES[:device_id_2]).each do
    | redeem |
    $LOG.debug redeem
    redeem.destroy
  end
end

def create_share (seen_device_id, params)
  response = call_api('share_location', seen_device_id, params)
  response
end

def clear_device_id (device_id)
  return unless device_id
  device = Device.find_by(device_id: device_id)
  return unless device
  account = Protocol.get_account_from_device (device)
  account.destroy if account
  device.destroy
end

def log_dos(msg)
  $LOG.error msg
  return
end

def parse_backtrace (backtrace) 
  ar = Array.new
  backtrace.each { |x|
    /(?<path>.*?):(?<line_num>\d+):in `(?<routine>.*)'/ =~ x
    file_base = File.basename(path)
    ar.push({file_base: file_base, line_num: line_num, routine: routine})
  }
  ar
end

def log_info(msg)
  $LOG.info msg
  Protocol.send_email(msg, 'support@geopeers.com', 'Geopeers Support', 'support@geopeers.com', 'Geopeers Server Info')
  msg
end

def log_error(err)
  msg = "On " + Socket.gethostname + "\n\n"
  if (err.respond_to?(:backtrace))
    msg += "Error: " + err.message + "\n\n" + err.backtrace.join("\n")
  else
    backtrace = parse_backtrace caller
    backtrace_str = backtrace[0][:file_base] + ':' + backtrace[0][:line_num] + ' ' + backtrace[0][:routine]
    backtrace_str += backtrace.join("\n")
    msg += "Error: " + err.inspect + "\n\n" + backtrace_str
  end
  $LOG.info msg
  Protocol.send_email(msg, 'support@geopeers.com', 'Geopeers Support', 'support@geopeers.com', 'Geopeers Server Error')
  msg
end

def parse_params (params_str)
  params_str = /\??(.*)/.match(params_str).to_s	# strip optional leading '?'

  params = {}
  params_str.split('&').each { |param_str|
    key, val = param_str.split('=')
    params[key] = val
  }
  params
end

def create_alert_url(url, msg, message_type=nil)
  message_type ||= 'message_success'
  msg = URI.escape (msg)
  url = "#{url}/?alert=#{msg}"
  url += "&message_type=#{message_type}" if message_type
  url
end

def create_and_send_share(share_params, tz, response)
  $LOG.debug share_params
  share_params['share_cred'] = SecureRandom.urlsafe_base64(10)
  share = Share.new(share_params)
  share.save

  # Can't have tz in Share.new (share_params)
  # Need it in send_share, so add it now
  share_params['tz'] = tz
  share_response = Protocol.send_share(share, share_params)
  $LOG.debug share_response

  # deal with accumulating messages
  # concatenate the message text
  # error/warning takes precedence for message_class
  if response[:message] && share_response[:message]
    response[:message] = response[:message] + '<br>' + share_response[:message]
    share_response.delete (:message)
    if  response[:message_class] &&
        share_response[:message_class] &&
        response[:message_class] == 'message_ok' &&
        share_response[:message_class] != 'message_ok'
    end
  end
  response.merge! (share_response)
  response
end

def init
  Dir.chdir ("/home/geopeers/sinatra/geopeers")
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
  ActiveRecord::Base.establish_connection(
                                          :adapter  => db_config['adapter'],
                                          :database => 'geopeers',
                                          :host     => 'db.geopeers.com',
                                          :username => 'geopeers',
                                          :password => 'ullamco1'
                                          )

  # For debugging, allow this script to be called with a URL parm:
  #   geo.rb 'method=config&device_id=DEV_42'
  # Unfortunately, things like rspec also call us
  # So make sure the thing on the command line is a URL parm with a 'method' key
  # The keys of params must be strings, that's what sinatra sends us
  puts ARGV[0]
  if ARGV[0]
    params = parse_params(ARGV[0])
    if params && params['method']
      resp = Protocol.process_request params
      puts resp.inspect
      # if we return, sinatra will listen for connections
      exit
    end
  end
end

DOWNLOAD_URLS = {
  ios:     'https://www.geopeers.com/bin/ios/index.html',
  android: 'https://www.geopeers.com/bin/android/index.html',
#  web:     'https://www.geopeers.com/bin/android/index.html',
}

def get_client_type (device_id)
  device = Device.find_by(device_id: device_id)
  user_agent = device.user_agent
  $LOG.debug user_agent
  return (:web) unless user_agent
  if (user_agent.match(/android/i))
    $LOG.debug 'Android'
    :android
  elsif (user_agent.match(/iphone/i) ||
         user_agent.match(/ipad/i) ||
         user_agent.match(/ios/i))
    $LOG.debug 'ios'
    :ios
  else
    $LOG.debug 'web'
    :web
  end
end

def get_global (key)
  row = Global.find_by(key:key)
  return unless row
  row['value']
end

def set_global (key, value)
  row = Global.find_by(key:key)
  if row
    row.update(value:value)
  else
    row = Global.new(key:key, value:value)
  end
  row.save
end

def global_test ()
  value = get_global('build_id')
  puts value
  set_global('build_id', 1)
  value = get_global('build_id')
  puts value
end

def get_build_id
  build_id = get_global('build_id')
  build_id ? build_id.to_i : 1
end

def bump_build_id
  build_id = get_build_id()
  build_id = build_id.to_i + 1
  set_global('build_id', build_id)
  build_id
end

##
#
# class which implements the geopeers protocol server
#
# The protocol consists of a series of REST API request/responses.
# The server implements each method of the request with a corresponding private method in this class.
# There is a single, public method, process_request()
# which dispatches the request to appropriate private method.
# The naming convention for the private routines is:
#   process_request_<method>
# 
class Protocol
  private

  def Protocol.compute_expire_time (params)
    multiplier = {
      'second' => 1,
      'minute' => 60,
      'hour'   => 60*60,
      'day'    => 60*60*24,
      'week'   => 60*60*24*7
    }
    raise ArgumentError.new("No share unit")   unless params.has_key?('share_duration_unit')
    return if params['share_duration_unit'] == 'manual'
    raise ArgumentError.new("No share number") unless params.has_key?('share_duration_number')
    raise ArgumentError.new("No multiplier")   unless multiplier.has_key?(params['share_duration_unit'])
    multiplier[params['share_duration_unit']] * params['share_duration_number'].to_i
  end

  def Protocol.create_share_url (share, params)
    "https://eng.geopeers.com/api?method=redeem&cred="+share.share_cred
  end

  def Protocol.create_verification_url (params)
    "https://eng.geopeers.com/api?method=verify&cred=#{params['cred']}&device_id=#{params['device_id']}"
  end

  def Protocol.create_download_url (params)
    "https://eng.geopeers.com/api?method=download_app&device_id=#{params['device_id']}"
  end

  def Protocol.create_unsolicited_url (params)
    "https://eng.geopeers.com/api?method=unsolicited&cred=#{params['cred']}&device_id=#{params['device_id']}"
  end

  def Protocol.format_expire_time (share, params)
    return unless share.expire_time
    expire_time = share.expire_time.in_time_zone(params['tz'])
    now = Time.now.in_time_zone(params['tz'])

    if (expire_time.year != now.year)
      "on " + expire_time.strftime("%d %B, %Y at %l:%M %p %Z")
    elsif (expire_time.month != now.month)
      "on " + expire_time.strftime("%d %B, at %l:%M %p %Z")
    elsif (expire_time.day != now.day)
      if (expire_time.day == now.day+1)
        "tomorrow at " + expire_time.strftime("%l:%M %p %Z")
      else
        "on " + expire_time.strftime("%d %B, at %l:%M %p %Z")
      end
    else
      "today at " + expire_time.strftime("%l:%M %p %Z")
    end
  end

  def Protocol.create_share_msg (share, params)
    url = Protocol.create_share_url(share, params)
    expire_time = Protocol.format_expire_time(share, params)
    account = Protocol.get_account_from_device_id (params['device_id'])
    name = account && account.name ? account.name : 'Someone'
    possessive = account && account.name ? "#{account.name}'s" : 'their'
    message = params['share_message']
    if (share.share_via == 'mobile')
      template_file = 'views/share_text_msg.erb'
    else
      boundary_random = SecureRandom.base64(21)
      template_file = 'views/share_email_body.erb'
      msg_erb = File.read(template_file)
      html_body = ERB.new(msg_erb).result(binding)
      require 'mail'
      quoted_html_body = Mail::Encodings::QuotedPrintable.encode(html_body)
      template_file = 'views/share_email_msg.erb'
    end
    msg_erb = File.read(template_file)
    ERB.new(msg_erb).result(binding)
  end

  def Protocol.send_sms (msg, num)
    sms_obj = Sms.new
    sms_obj.send(num, msg)
  end

  def Protocol.send_html_email(body_template, msg_template, subject, email_addr, erb_params)
    # This is done with nested ERB templates
    # msg_template is a multipart MIME template
    # body_template is the HTML 
    erb_params[:boundary_random] = SecureRandom.base64(21)
    msg_erb = File.read(body_template)
    html_body = ERB.new(msg_erb).result(ERBContext.new(erb_params).get_binding)
    require 'mail'
    erb_params[:quoted_html_body] = Mail::Encodings::QuotedPrintable.encode(html_body)
    msg_erb = File.read(msg_template)
    msg = ERB.new(msg_erb).result(ERBContext.new(erb_params).get_binding)
    Protocol.send_email(msg, 'sherpa@geopeers.com', 'Geopeers Helper', email_addr, subject)
  end

  def Protocol.send_verification_msg (params, type)
    url = Protocol.create_verification_url(params)
    if (type == 'email')
      Protocol.send_html_email('views/verify_email_body.erb', 'views/verify_email_msg.erb',
                               "Please verify your email with Geopeers", params['email'],
                               { url: url,
                                 url_unsolicited: Protocol.create_unsolicited_url(params)})
    elsif (type == 'mobile')
      msg = "Press this #{url} to verify your Geopeers account"
      Protocol.send_sms(msg, params['mobile'])
    end
  end

  def Protocol.send_share_mobile (share, params)
    sms_obj = Sms.new
    msg = Protocol.create_share_msg(share, params)
    err = sms_obj.send(share.share_to, msg)
    if (err)
      error_response err
    else
      {message: "Sent location share to #{share.share_to}"}
    end
  end

  def Protocol.send_email (msg, from_email, from_name, to_email, subject, is_html=nil)
    from = "#{from_name} <#{from_email}>"
    header = "From: #{from}\nTo: #{to_email}\nSubject: #{subject}\n"
    header += "MIME-Version: 1.0\nContent-type: text/html\n" if is_html
    begin
      Net::SMTP.start('127.0.0.1') do |smtp|
        smtp.send_message header+msg, from_email, to_email
        $LOG.info "Sent email to #{to_email}"
      end
    rescue Exception => e  
      log_error e
      return true
    end
    nil
  end

  def Protocol.send_share_email (share, params)
    $LOG.debug params
    $LOG.debug share
    account = Protocol.get_account_from_device_id (params['device_id'])
    if (! account)
      log_error ("No account")
      {message: 'There was a problem sending your email.  Support has been contacted', css_class: 'message_error'}
    else
      name = account.name ? account.name : 'Someone'
      subject = "#{name} shared their location with you"
      msg = Protocol.create_share_msg(share, params)
      $LOG.debug account
      email = account.email ? account.email : 'anon_user@geopeers.com'
      $LOG.debug email
      err = Protocol.send_email(msg, email, account.name, share.share_to, subject)
      if (err)
        log_error (err)
        {message: 'There was a problem sending your email.  Support has been contacted', message_class: 'message_error'}
      else
        {message: "Sent location share to #{share.share_to}"}
      end
    end
  end

  def Protocol.send_share_facebook (share, params)
    {message: "Facebook shares are not implemented yet"}
  end

  def Protocol.send_share_twitter (share, params)
    {message: "Twitter shares are not implemented yet"}
  end

  def Protocol.error_response (error_msg)
    # { error: error_msg, backtrace: caller }
    { message: error_msg, style: {color: 'red'}}
  end

  def Protocol.send_share (share, params)
    procname = 'send_share_' + share['share_via']
    if (defined? procname)
      (method procname).call(share, params)
    else
      error_response "Bad method " + procname
    end
  end

  def Protocol.create_device(device_id, user_agent)
    device = Device.new(device_id:  device_id,
                        user_agent: user_agent)
    account = Account.new()
    account.save
    device[:account_id] = account.id
    device.save
    
    log_info ("created device #{device_id}, user agent=#{user_agent.to_s}, account=#{account.id}, params=#{$params.inspect}")
    device
  end

  def Protocol.create_device_id (user_agent)
    require 'securerandom'
    device_id = SecureRandom.uuid
    Protocol.create_device(device_id, user_agent)
  end

  def Protocol.process_request_device_id_bind (params)
    ##
    # device_id_bind
    #
    # This routine is the server-side of a handshake
    # initiated by a mobile device to merge the accounts for
    # a web app and a native app running on the same device
    #
    # In practice, this means that shares that are redeemed by the web app
    # will be available in the native app.
    # This is important because we send URLs to the device to redeem a share.
    # These URLs will be opened in the device browser.
    # If we don't join the accounts, we don't have a way to get state into the native app
    #
    # The handshake looks like this:
    #   1) at first startup, the native app creates a URL to call this API:
    #        /api?method=device_id_bind&my_device_id=<native app device_id>
    #      Next, it sends (redirects) that URL to be opened in the device's browser (e.g. Safari)
    #      as opposed to a webview in the native app
    #   2) the device's browser opens the URL which causes a request to this API
    #   3) this routine has both the native app device_id from the URL parms and
    #      the webapp device_id from the cookie.
    #      If the web app cookie hasn't been set yet, that is done here.
    #      This routine does the bookkeeping to merge the device_ids into the same account
    #      This routine then creates a deeplink URL which it returns as a redirect to
    #      the device's browser, completing the handshake and returning the user to the native app
    #
    # params
    #   native_device_id   - device id of the native app
    #
    # returns
    #   redirect_url - deeplink to get back to the native app
    #   - or -
    #   HTML
    #     

    native_app_deeplink = "geopeers://api?method=device_id_bind"

    native_app_device = Device.find_by(device_id: params['native_device_id'])
    $LOG.debug native_app_device
    if ! native_app_device
      log_error ("No native app device")
      url = create_alert_url("https://eng.geopeers.com",
                             "There was a problem with your request.  Support has been contacted.")
      return {redirect_url: url}
    end

    # manage_device_id should have been called already, so if there isn't a device_id set,
    # something has gone very wrong
    if ! params['device_id']
      log_error ("No web app device id")
      url = create_alert_url("https://eng.geopeers.com",
                             "There was a problem with your request.  Support has been contacted.")
    end

    web_app_device = Device.find_by(device_id: params['device_id'])
    $LOG.debug web_app_device

    # The deeplink includes these parameters for completeness.
    # Since we will merge the accounts here,
    # the native app doesn't need to do anything with these params

    if native_app_device.account_id == web_app_device.account_id
      # This was already done
      msg = "Your shared locations have been transferred to the native app<p><div class='message_button' onclick='native_app_redirect()'><div class='message_button_text'>Switch to Native App</div></div>";
      error_url = create_alert_url("https://eng.geopeers.com", msg);
      {redirect_url: error_url}
    else
      errs = Protocol.merge_accounts(Account.find(native_app_device.account_id),
                                     Account.find(web_app_device.account_id))
      if ! errs.empty?
        msg = errs.join('<br>')
        native_app_deeplink = create_alert_url(native_app_deeplink, msg);
        native_app_deeplink += "&message_type=message_info"
      end
      
      {redirect_url: native_app_deeplink}
    end
  end

  def Protocol.process_request_config (params)
    ##
    # config
    #
    # client sends config request at startup
    #
    # params
    #   device_id
    #   version          - current client version
    #
    # returns
    #   js      - client will execute this js
    #     

    response = {}
    # handle upgrade
    if (params['version'] && params['version'].to_f < 1.0)
      response.merge! ({js: "alert('If we had an upgrade, this would be it')"})
    end

    response
  end

  def Protocol.process_request_send_position (params)
    # params: device_id, gps_*
    # returns: OK/ERROR
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
    {status:'OK'}
  end

  def Protocol.process_request_get_positions (params)
    # params: device_id
    # returns: [{name_1, latest gps_*_1, sighting_time_1},
    #           {name_2, latest gps_*_2, sighting_time_2}, ...]
    if ! params.has_key?('device_id')
      log_dos "No device ID"
      return (error_response "No device ID")
    end
    device = Device.find_by(device_id: params['device_id'])
    if ! device
      log_dos "No device for #{params['device_id']}"
      return (error_response "No device for #{params['device_id']}")
    end
    if ! device.account_id
      log_dos "No device account for #{params['device_id']}"
      return (error_response "No device account for #{params['device_id']}")
    end
    $LOG.debug device

    sql = "SELECT sightings.device_id,
                  sightings.gps_longitude, sightings.gps_latitude,
                  sightings.updated_at,
                  current_sightings.share_expire_time,
                  accounts.name AS account_name,
                  accounts.email AS account_email,
                  accounts.mobile AS account_mobile
           FROM   accounts, devices, sightings
           JOIN (
                  SELECT sightings.device_id,
                         MAX(sightings.updated_at) AS max_updated_at,
                         shares.expire_time AS share_expire_time
                  FROM sightings, devices, shares, redeems
                  WHERE  devices.account_id = #{device.account_id} AND
                         redeems.device_id = devices.device_id AND
                         redeems.share_id = shares.id AND
                         shares.device_id = sightings.device_id AND
                         (NOW() < shares.expire_time OR shares.expire_time IS NULL)
                  GROUP BY sightings.device_id
                ) current_sightings
           ON current_sightings.device_id = sightings.device_id AND
              current_sightings.max_updated_at = sightings.updated_at
           WHERE sightings.device_id = devices.device_id AND
                 devices.account_id = accounts.id
          "
    $LOG.debug sql.gsub("\n"," ")
    elems = []
    Sighting.find_by_sql(sql).each { |row|
      elems.push ({ 'name'          => row.account_name ? row.account_name : 'Anonymous',
                    'have_addr'     => row.account_email || row.account_mobile ? 1 : 0,
                    'device_id'     => row.device_id,
                    'gps_longitude' => row.gps_longitude,
                    'gps_latitude'  => row.gps_latitude,
                    'sighting_time' => row.updated_at,
                    'expire_time'   => row.share_expire_time,
                  })
    }
    response = {'sightings' => elems }

    # get the most recent location of device_id
    my_latest_location = Sighting.where("device_id=?", device.device_id)
      .order(created_at: :desc)
      .limit(1)
      .first
    if my_latest_location
      response['current_position'] = {
        'coords' => {
          'longitude' => my_latest_location.gps_longitude,
          'latitude'  => my_latest_location.gps_latitude,
          },
        'timestamp' => my_latest_location.updated_at,
      }
    end
    response
  end

  def Protocol.process_request_get_registration (params)
    if params['device_id']
      device = Device.find_by(device_id: params['device_id'])
      if device
        if device.account_id
          Account.find(device.account_id)
        else
          {}
        end
      else
        # This shouldn't happen.  If there is a device_id, it should be in the DB
        $LOG.debug params['device_id']
        log_dos ("No record for "+params['device_id'])
        error_response "Unknown device ID"
      end
    else
      log_dos ("No device_id")
      return (error_response "No device ID")
    end
  end

  def Protocol.validate_register_params (params)
    msgs = []
    if ! params['device_id']
      msgs.push "No device ID"
    end
    if params['new_account'] == 'yes'
      if ! params['name']
        msgs.push "Please supply your name"
      end
    end

    if params['email']
      if ! /.+@.+/.match(params["email"])
        msgs.push "Email should be in the form 'fred@company.com'"
      end
      has_email_or_mobile = true
    end

    if (params['mobile'])
      # We are not just validating, but actually normalizing (changing) the user input
      # We have to do this so that (415) 555-1212 matches 415-5551212
      params['mobile'] = Sms.clean_num(params['mobile'])
      if (! /^\d{10}$/.match(params['mobile']))
        msgs.push ("The mobile number must be 10 digits")
      end
      has_email_or_mobile = true
    end

    # don't return an empty array
    msgs = nil if msgs.empty?
    return msgs
  end

  def Protocol.get_latest_auth(account_id, type)
    # get the most recent, un-verified auth for this account/type
    auth = Auth.where("account_id = ? AND auth_type = ? AND auth_time IS NULL", account_id, type)
      .order(auth_time: :desc)
      .limit(1)
      .first
  end

  def Protocol.send_verification_by_type (params, type)
    # params:
    #   device_id
    #   account_id
    #   email | mobile
    #
    # returns:
    #   <err_msg>, <user_msg>
    #
    # create cred and put in auth record
    # email/text verification

    new_val = params[type]
    return unless (new_val)

    account = Protocol.get_account_from_device_id (params['device_id'])
    return unless (account)

    $LOG.debug account
    $LOG.debug new_val
    # Don't send if there is no change
    return if account[type] == new_val

    auth = Protocol.get_latest_auth(account.id,type)
    if auth
      params['cred'] = auth.cred
      if auth.auth_key == new_val
        # User is trying to verify the same value, resend the verification
        user_msg = "#{new_val} has not been verified yet.  The verification has been re-sent"
      else
        # user wants to verify a different value
        # create a new auth
        # the old auth
        params['cred'] = SecureRandom.urlsafe_base64(10)
        auth = Auth.new(account_id: account.id,
                        auth_type:  type,
                        auth_key:   new_val,
                        cred:       params['cred'],
                        issue_time: Time.now,
                        )
        auth.save
        user_msg = "We were waiting for a verification for #{auth.auth_key}"
        user_msg += "That verification will now verify #{new_val}.  And a new verification was sent to #{new_val}"
        auth.auth_key = new_val
        auth.save
      end
    else
      params['cred'] = SecureRandom.urlsafe_base64(10)
      auth = Auth.new(account_id: account.id,
                      auth_type:  type,
                      auth_key:   new_val,
                      cred:       params['cred'],
                      issue_time: Time.now,
                      )
      auth.save
      user_msg = "A verification was sent to #{new_val}"
    end
    err = Protocol.send_verification_msg(params, type)
    if (err)
      log_error (err)
      verification_type = (type == 'email') ? 'email' : 'text msg'
      return ("There was a problem sending your verification #{verification_type}.  Support has been contacted")
    else
      return nil, user_msg
    end
  end

  def Protocol.send_verifications (params)
    errs = []
    user_msgs = []
    ['mobile','email'].each do | type |
      err, user_msg = Protocol.send_verification_by_type(params, type)
      errs.push err if err
      user_msgs.push user_msg if user_msg
    end
    return errs, user_msgs
  end

  def Protocol.get_existing_account (params, type)
    if (params[type])
      return Account.where(type+"=? AND active = 1", params[type]).first
    end
    return
  end

  def Protocol.process_new_account (params)
    # The user has indicated that these parameters (email/mobile) are for a new account
    # So if they are used for another account, we throw an error
    # If the user wanted to merge this device into another account,
    # then they should not have checked 'Yes' to new_account

    device = Device.find_by(device_id: params['device_id'])
    $LOG.debug device
    if (! device)
      log_dos ("No device")
      return ["There was a problem with your request."], nil
    end

    err_msgs = []

    # The account is now created when the device is created
    # err_msgs.push ("Your device is already registered") if device.account_id

    # make sure account (email and/or mobile) doesn't already exist
    account = Protocol.get_existing_account(params, 'mobile')
    err_msgs.push (params['mobile']+" is already registered") if account && account.id != device.account_id
    account = Protocol.get_existing_account(params, 'email')
    err_msgs.push (params['email']+" is already registered") if account && account.id != device.account_id
    return err_msgs, nil if err_msgs && ! err_msgs.empty?

    account = Account.find(device.account_id)
    account[:name] = params['name']
    account.save

    Protocol.send_verifications (params)
  end

  def Protocol.bind_to_account (params)
    # associate device_id with an existing account
    # since we have email and/or mobile, this requires a few twists

    $LOG.debug "bind_to_account"
    user_msgs = []
    errs = []
    accounts = {}
    ['mobile','email'].each do | type |
      if params[type]
        account = Protocol.get_existing_account(params, type)
        if account
          err_msg, user_msg = Protocol.send_verification_by_type(params, type)
          errs.push (err_msg) if (err_msg)
          user_msgs.push (user_msg) if (user_msg)
          accounts[type] = account
        else
          log_dos ("No account for #{params[type]}")
          user_msgs.push ("There is no account associated with #{params[type]}")
        end
      end
    end

    if (! params['mobile'] && ! params['email'])
      # we couldn't find an account
      # The error message is already in user_msgs
      errs.push ("Please supply either mobile or email")
    elsif (accounts['mobile'] && accounts['email'] && (accounts['mobile'].id != accounts['email'].id))
      # This is a problem, the email points to one account and the mobile to another
      errs.push ("Please supply either email or mobile but not both to register this device with your account.  To create a new account, check 'New'.")
    else
      # at this point we are guaranteed that
      # if we have an account for both mobile and email
      # then they are the same
      account = accounts['mobile'] ? accounts['mobile'] : accounts['email']
      # it's possible that we don't have any accounts if we got a param with no account
      if account
        params['account_id'] = account.id
        #
        # Don't do this.  See:
        #   #4302 - Only add a device to an account after verification
        #
        device = Device.find_by(device_id: params['device_id'])
        device[:account_id] = account.id
        device.save
        user_msgs.push ("Your device has been added to the account #{account.name}")
      end
    end
    return errs, user_msgs
  end

  def Protocol.get_download_app_info (params)
    $LOG.debug params
    if (params['download_app'])
      client_type = get_client_type (params['device_id'])
      redirect_url = DOWNLOAD_URLS[client_type]
      if (redirect_url)
        return nil, redirect_url
      else
        return "There is no native app available for your device", nil
      end
    end
  end

  def Protocol.manage_account(params, account)
    if ! account
      log_error "No account"
      return ["No Account"]
    end
    # Update account with name/email/mobile in parms
    device = Device.find_by(device_id: params['device_id'])
    if ! device
      log_error "No device"
      return ["No device"]
    end
    msgs = []
    errs = []

    if (params['name'] && params['name'] != account.name)
      account.name = params['name']
      account.save
      msgs.push ("Account name changed to #{account.name}")
    end

    ['mobile','email'].each do | type |
      if params[type] && (params[type] != account[type])
        params['account_id'] = account.id
        err, user_msg = Protocol.send_verification_by_type(params, type)
        if err
          log_error err
          errs.push (err)
        end
        msgs.push (user_msg) if user_msg
      end
    end
    return errs, msgs
  end

  def Protocol.process_request_register_device (params)
    # params:
    #   method = 'register_device'
    #   new_account = [ 'yes' | 'no' ]	
    #   name
    #   email
    #   mobile
    # register name/email/mobile with an account
    # send the verification
    #

    if ! params['device_id']
      log_dos ("No device ID")
      return;
    end

    device = Device.find_by(device_id: params['device_id'])

    # The device should have been created in manage_device_id()
    if ! device
      log_error ("No device")
      return;
    end

    errs = Protocol.validate_register_params (params)
    return error_response errs.join('<br>') if (errs)

    # There are three possibilities
    #   1) create new account
    #   2) register a new device to an existing account
    #   3) edit the account parameters (after verification if needed)
    if (params['new_account'] == 'yes')
      errs, user_msgs = Protocol.process_new_account (params)
    else
      account = Protocol.get_account_from_device (device)
      if account
        # This device is already associated with an account
        # params are changes to that account
        errs, user_msgs = Protocol.manage_account(params, account)
      else
        # This device does not have an account yet (i.e. never got new_account == 'yes')
        # use params (email and/or mobile) to find an account
        errs, user_msgs = Protocol.bind_to_account(params)
      end
    end
    $LOG.debug user_msgs if ! user_msgs.empty?
    $LOG.debug errs if ! errs.empty?

    response = {}
    if (errs && ! errs.empty?)
      response = error_response errs.join('<br>')
    else
      response = {message: user_msgs.join('<br>'), style: {color:"red"}} if (user_msgs)
    end
    response
  end

  def Protocol.merge_response (cum_response,response)
  end

  def Protocol.process_request_share_location (params)

    # there are three ways to specify a share:
    #   1) seer_device_id
    #   2) share_via/share_to
    #   3) my_contacts_mobile and/or my_contacts_email
    
    raise ArgumentError.new("No device ID")  unless params['device_id']

    # create a share and send it
    expire_time = compute_expire_time params
    expire_time = Time.now + expire_time if expire_time
    share_parms = {
      expire_time:  expire_time,
      num_uses:     0,
      num_uses_max: params["num_uses"],
      active:       1,
    }
    share_parms['device_id'] = params["device_id"]

    response = {}
    if params['seer_device_id']
      # share location of requesting device
      # with account associated with a share
      # (i.e. share my location with pin)
      #
      # An account does not need an email or mobile
      # 
      account = Protocol.get_account_from_device_id (params['seer_device_id'])
      ['mobile','email'].each do | type |
        if account[type]
          response = create_and_send_share(share_parms.merge({ share_via: type,
                                                               share_to:  account[type],
                                                             }),
                                           params['tz'],
                                           response)
        end
      end
      # TODO: This only returns the last response
      #       if both mobile and email are set in account, the first response is ignored
    end

    ['mobile','email'].each do | type |
      if params["my_contacts_#{type}"]
        $LOG.debug params["my_contacts_#{type}"]
        response = create_and_send_share(share_parms.merge({ share_via: type,
                                                             share_to:  params["my_contacts_#{type}"],
                                                           }),
                                         params['tz'],
                                         response)
      end
    end
      
    if params['share_via'] && params['share_to']
      # supply mobile
      raise ArgumentError.new("Please supply the address to send the share to") unless params['share_to']

      if params["share_via"] == 'mobile'
        sms_num = Sms.clean_num(params["share_to"])
        raise ArgumentError.new("The phone number (share to) must be 10 digits") unless /^\d{10}$/.match(sms_num)
      end

      if params["share_via"] == 'email'
        # In general, RFC-822 email validation can't be done with regex
        # For now, just make sure it has an '@'
        raise ArgumentError.new("Email should be in the form 'fred@company.com'") unless /.+@.+/.match(params["share_to"])
      end

      response = create_and_send_share(share_parms.merge({ share_via: params['share_via'],
                                                           share_to:  params['share_to'],
                                                         }),
                                       params['tz'],
                                       response)
    end
    response
  end

  def Protocol.process_request_redeem (params)
    # a share URL has been clicked
    # using the cred, create a redeem for the share

    # get the share for this cred
    share = Share.find_by(share_cred: params[:cred])
    $LOG.debug share
    redirect_url = 'https://eng.geopeers.com'

    if (share)
      if (! share.num_uses_max ||	# null num_uses_max -> unlimited uses
           (share.num_uses < share.num_uses_max))
        # it's a good share

        # does params['device_id'] (seer) already have access to a share for share.device_id (seen)
        sql = "SELECT shares.expire_time, redeems.id AS redeem_id FROM shares, redeems
               WHERE shares.device_id  = '#{share.device_id}' AND
                     redeems.device_id = '#{params['device_id']}' AND
                     redeems.share_id  = shares.id AND
                     (shares.expire_time IS NULL OR NOW() < shares.expire_time)
              "
        $LOG.debug sql
        current_share = Share.find_by_sql(sql).first
        $LOG.debug current_share
        if (current_share)
          if ( ! current_share.expire_time)
            # we already have an unlimited share
            $LOG.debug "unlimited share"
            return {:redirect_url => redirect_url}
          end
          
          if (! share.expire_time)
            # the new share doesn't expire, use it
            $LOG.debug "using new infinite share"
            redeem = Redeem.find (current_share.redeem_id)
            redeem.share_id = share.id
          elsif (current_share.expire_time >= share.expire_time)
            # this current_share expires after the new share, ignore the new share
            $LOG.debug "using existing share"
            return {:redirect_url => redirect_url}
          else
            # the new share expires after the current share, update the redeem with the new share
            $LOG.debug "updating redeem with new share"
            redeem = Redeem.find (current_share.redeem_id)
            redeem.share_id = share.id
          end
        else
          $LOG.debug "no existing share"
          redeem = Redeem.new(share_id:  share.id,
                              device_id: params["device_id"])
        end
        redeem.save
        $LOG.debug redeem
        share.num_uses = share.num_uses ? share.num_uses+1 : 1
        share.save
      else
        # This share has been used up
        msg = "That credential is not valid.  You can't view the location.  You can still use the other features of GeoPeers"
        redirect_url = create_alert_url(redirect_url, msg)
      end
    else
      msg = "That credential is not valid.  You can't view the location.  You can still use the other features of GeoPeers"
      redirect_url = create_alert_url(redirect_url, msg)
    end
    {:redirect_url => redirect_url}
  end

  def Protocol.process_request_verify (params)
    # an auth was created to update a value in an account
    # In this request, we get a cred
    # If it corresponds to an auth,
    # then update the account with the info in the auth
    #
    # Several twists:
    #   - the cred may not be the most recent.
    #     There can only be one verification 'in the air' at a time.
    #     So if you request 2 value changes, the first verification should fail
    #   - make sure params['device_id'] is correct for the cred
    #

    # get the auth associated with the credential in the request params
    auth_cred = Auth.find_by(cred: params["cred"])
    $LOG.debug auth_cred

    # get the latest auth
    auth_latest = Protocol.get_latest_auth(auth_cred.account_id, auth_cred.auth_type)
    $LOG.debug auth_latest

    # As a cross-check, we include the device_id
    device = Device.find_by(device_id: params['device_id'])
    $LOG.debug device

    redirect_url = 'https://geopeers.com'

    # Things that can go wrong:
    #   1) there is no auth associated with cred
    #   2) there is no device associated with device_id
    #   3) the cred is old (not latest auth)
    #      test auth.auth_keys, not auth.ids
    #      in case user did this: key_1 -> key_2 -> key_1
    if  ! auth_cred ||
        ! device ||
        auth_cred.account_id != device.account_id
      (auth_latest &&
       auth_cred.auth_key != auth_latest.auth_key)
      log_dos (params)
      msg = "That credential is not valid.  You can't view the location.  You can still use the other features of GeoPeers"
      message_type = 'message_warning'
    else
      # auth_cred and device are good
      # But it is possible that there are two different accounts
      #   1) This device_id has an account
      #   2) There is an account associated with the value 
      account_for_device = Account.find(device.account_id)
      $LOG.debug account_for_device
      account_from_val = Account.where("#{auth_cred.auth_type}=? AND active = 1",auth_cred.auth_key).first
      $LOG.debug account_from_val
      if  account_from_val &&
          account_from_val.id != device.account_id
        # this value is used in another account, merge 
        msg = "#{auth_cred.auth_key} is used by #{account_from_val.name}.  Your device has been added to this account."
        message_type = 'message_info'
        errs = Protocol.merge_accounts(account_from_val, account_for_device)
        msg += errs.join('<br>') unless (errs.empty?)
        device.account_id = account_from_val.id
        device.save
        account = account_from_val
      else
        msg = account_for_device.name+" has been registered"
        message_type = 'message_success'
        account = account_for_device
      end
      auth_cred.auth_time = Time.now
      auth_cred.save
      account[auth_cred.auth_type] = auth_cred.auth_key
      account.save
      $LOG.debug account
    end
    redirect_url = create_alert_url(redirect_url, msg, message_type)
    redirect_url += "&device_id=#{device.device_id}"
    return {:redirect_url => redirect_url}
  end

  def Protocol.merge_accounts(account_1, account_2)
    # merge account_2 into account_1

    $LOG.debug account_1
    $LOG.debug account_2

    err_msgs = []
    ['name', 'mobile', 'email'].each do | type |
      if account_2[type]
        # merge the attributes of the account record
        if account_1[type]
          if account_1[type] != account_2[type]
            # This is bad
            msg = "The #{type} #{account_2[type]} will no longer be used. You can continue to use #{account_1[type]}."
            err_msgs.push (msg)
          end
        else
          # account_1[type] is nil, copy value from account_2
          account_1[type] = account_2[type]
        end
        if type != 'name'
          # We have to null out the entry in account_2
          # so that the email/mobile values can be unique in the DB
          account_2[type] = nil
        end
      end
    end
    # Have to save account_2 before account_1
    # To make sure the values account_1 is using are available
    account_2.save
    account_1.save

    # move any devices using account_2
    Device.where("account_id = ?", account_2.id)
      .update_all(account_id: account_1.id)

    # move any un-verified auths
    Auth.where("auth_time IS NULL AND account_id = ?", account_2.id)
      .update_all(account_id: account_1.id)

    # don't delete account_2, just mark it inactive
    account_2.active = nil
    account_2.save
    err_msgs
  end
  
  def Protocol.process_request_get_shares (params)
    # get a list of device_ids that are registered with the same device.email as params['device_id']
    # and create a comma-separate list, suitable for putting in the SQL IN clause
    device = Device.find_by(device_id: params['device_id'])
    if ! device
      log_dos ("No device for #{params['device_id']}")
      return {error: "No device"}
    end
    # get all the shares with those device_ids
    # and a list of the device_id that redeemed the shares
    sql = "SELECT   shares.id AS share_id, shares.share_to, shares.share_via,
                    shares.expire_time, shares.active,
                    shares.updated_at, shares.created_at,
                    redeems.id AS redeem_id,
                    redeems.created_at AS redeem_time
          "
    if device.account_id
      sql += ", accounts.name AS redeem_name"
      sql += " FROM accounts, devices, shares"
      sql += " LEFT JOIN redeems ON shares.id = redeems.share_id"
      sql += " WHERE devices.account_id = #{device.account_id} AND
                     accounts.id = devices.account_id AND
                     redeems.device_id = devices.device_id"
    else
      device_id_parm = Mysql2::Client.escape(params['device_id'])
      sql += " FROM accounts, devices, shares"
      sql += " LEFT JOIN redeems ON shares.id = redeems.share_id"
      sql += " WHERE redeems.device_id = #{device_id_parm}"
    end
    $LOG.debug sql.gsub("\n"," ")
    # Find the names associated with the redeemed device_ids
    elems = []
    Share.find_by_sql(sql).each { |row|
      elems.push (row)
    }
    {'shares' => elems }
  end

  def Protocol.process_request_send_download_link (params)
    # params:
    #   device_id
    #   email
    #   mobile
    
    response_msg = ""
    response_err = ""
    if params['email']
      email_err = Protocol.send_html_email('views/download_email_body.erb', 'views/download_email_msg.erb',
                                           "Download your Geopeers app", params['email'],
                                           { url: Protocol.create_download_url(params)}
                                           )
      if email_err
        response_err += "There was a problem sending email to #{params['email']}<br>"
        log_error (err)
      else
        response_msg += "A download link was sent to #{params['email']}<br>"
      end
    end

    if params['mobile']
      msg = "Press this #{url} to download the Geopeers native app"
      sms_obj = Sms.new
      sms_err = sms_obj.send(params['mobile'], msg)
      if sms_err
        response_err += "There was a problem sending a text to #{params['mobile']}<br>"
        log_error (sms_err)
      else
        response_msg += "A download link was sent to #{params['mobile']}<br>"
      end
    end
    if response_err
      {message: response_err+response_msg, message_class: 'message_error'}
    else
      {message: response_msg, message_class: 'message_ok'}
    end
  end
  
  def Protocol.process_request_download_app (params)
    # params:
    #   device_id - of device that sent the link
    #
    # This doesn't really download the app
    # It redirects to the webapp with instructions to download the native app
    {redirect_url: "https://eng.geopeers.com/?download_app=1"}
  end
  
  def Protocol.process_request_share_active_toggle (params)
    ##
    #
    # share_active_toggle
    #
    # params
    #   device_id
    #   share_id
    #
    error_response = {message: 'There was a problem with your request.  Support has been contacted', message_class: 'message_error'}
    if (! params['device_id'])
      log_error ("no device_id")
      return (error_response)
    end
    if (! params['share_id'])
      log_error ("no share_id")
      return (error_response)
    end
    share = Share.find(params['share_id'])
    if (! share)
      log_error ("Share for #{params['share_id']}")
      return (error_response)
    end
    if (share.device_id != params['device_id'])
      log_error ("Device ID for share #{params['share_id']} is #{share.device_id}, does not match #{params['device_id']}")
      return (error_response)
    end
    share.active = share.active == 1 ? 0 : 1
    share.save
    shares = Protocol.process_request_get_shares (params)
    $LOG.debug shares
    shares
  end

  def Protocol.process_request_unsolicited (params)
    # params
    #   cred
    #   device_id
    msg = "\n\n"
    msg += "cred: #{params['cred']}\n"
    msg += "device_id: #{params['device_id']}\n\n"
    if params['cred']
      auth = Auth.find_by(cred: params['cred'])
      if auth
        msg += "auth_type: #{auth.auth_type}\n"
        msg += "auth_key: #{auth.auth_key}\n\n"
        account_auth = Account.find(auth.account_id)
        msg += "account id: #{account_auth.id}\n"
        msg += "account name: #{account_auth.name}\n"
        msg += "account email: #{account_auth.email}\n"
        msg += "account mobile: #{account_auth.mobile}\n"
      else
        msg += "No share for cred\n"
      end
    end
    if params['device_id']
      account = Protocol.get_account_from_device_id (params['device_id'])
      if account
        if account.id == account_auth.id
          msg += "Matches auth account"
        else
          msg += "Different than auth account"
          msg += "account id: #{account.id}\n"
          msg += "account name: #{account.name}\n"
          msg += "account email: #{account.email}\n"
          msg += "account mobile: #{account.mobile}\n"
        end
      else
        msg += "No account for device_id\n"
      end
    end

    Protocol.send_email(msg, 'support@geopeers.com', 'Geopeers Support', 'support@geopeers.com',
                        'Geopeers Unsolicited Verification Report')
    html = "<html><body>Not much in the way of formatting, but thanks.</body></html>"
    {html: html}
  end

  def Protocol.process_request_send_support (params)
    msg = ""
    account = Protocol.get_account_from_device_id (params['device_id'])
    msg = '<div style="font-size:20px; font-weight:bold">User Info</div>'
    msg += '<div style="font-size:18px; font-weight:normal; margin-left:10px; margin-bottom:10px">'
    msg += "From "
    msg += account.name ? account.name : "Anonymous User" + ' '
    msg += "(" + params['device_id'] + ")" + '<br>'
    msg += "Email:" + account.email + '<br>' if account.email
    msg += "Mobile:" + account.mobile + '<br>' if account.mobile
    msg += '</div>'
    ['problem', 'reproduction', 'feature', 'cool_use'].each do | field |
      field_name = 'support_form_'+field
      val = params[field_name]
      next unless val
      field_display = field.capitalize.gsub("_", " ")
      msg += '<div style="font-size:20px; font-weight:bold">'+field_display+'</div>'
      msg += '<div style="font-size:18px; font-weight:normal; margin-left:10px">'+val+'</div>'
    end
    Protocol.send_email(msg, 'support@geopeers.com',
                        'Geopeers Support', 'support@geopeers.com',
                        'Geopeers Customer Request', 1)
    {message:"Message sent, thanks!"}
  end

  def Protocol.make_popup(popup_id, popup_title, nested_erb, params)
    share_location_my_contacts_tag = nil
    if params && params[:is_phonegap]
      share_location_my_contacts_tag = '<option value="contacts">Select from My Contacts</option>'
    end
    nested_html = ERB.new(File.read(nested_erb)).result(binding)
    ERB.new(File.read('views/popup.erb')).result(binding)
  end

  public

  def Protocol.create_index(params=nil)
    version = "0.7"
    phonegap_html = nil
    share_location_my_contacts_tag = nil
    if params && params[:is_phonegap]
      build_id = bump_build_id()
      phonegap_html = '<script type="text/javascript" charset="utf-8" src="cordova.js"></script>'
    else
      build_id = get_build_id()
    end
    registration_popup =
      make_popup("registration_popup",
                 "Setup your Account",
                 "views/registration_form.erb",
                 params)
    download_link_popup =
      make_popup("download_link_popup",
                 "Send Download Link",
                 "views/download_link_form.erb",
                 params)
    download_type_popup =
      make_popup("download_type_popup",
                 "Download Native App",
                 "views/download_type_form.erb",
                 params)
    share_location_popup =
      make_popup("share_location_popup",
                 "Share your Location",
                 "views/share_location_form.erb",
                 params)
    support_popup =
      make_popup("support_popup",
                 "Make Us Better",
                 "views/support_form.erb",
                 params)
    share_management_popup =
      make_popup("share_management_popup",
                 "Manage your Shared Locations",
                 "views/share_management_form.erb",
                 params)
    ERB.new(File.read('views/index.erb')).result(binding)
  end

  def Protocol.create_if_not_exists_device (params)
    $LOG.debug params
    device = Device.find_by(device_id: params[:device_id])
    if device
      $LOG.debug device
      device
    else
      # This is a device_id we haven't see yet
      Protocol.create_device(params[:device_id], params[:user_agent])
    end
  end

  def Protocol.get_account_from_device (device)
    return unless device
    if (device.account_id)
      Account.find(device.account_id)
    else
      nil
    end
  end

  def Protocol.get_account_from_device_id (device_id)
    device = Device.find_by(device_id: device_id)
    Protocol.get_account_from_device (device)
  end

  def Protocol.process_request (params)
    begin
      $LOG.info (params)

      if (!params.has_key?('method'))
        log_dos "No method"
        return (error_response "No method")
      end
      procname = 'process_request_' + params['method']
      if (defined? procname)
        resp = (method procname).call(params)
        $LOG.info resp
        resp
      else
        log_dos "Bad method " + procname
        error_response "There was a problem with your request.  Support has been contacted"
      end
    rescue Exception => e
      log_error e
      $LOG.debug e.backtrace
      error_response "There was a problem with your request.  Support has been contacted"
    end
  end
end

class ProtocolEngine < Sinatra::Base

  set :static, true

  def before_proc (params)
    # If the client sent a JSON object in the body of the request,
    # (typically used to send a >1 layer parms in a request)
    # merge that object with any parms that were passed in the request
    $params = params
    if (request.content_type == 'application/json')
      request.body.rewind
      params.merge!(JSON.parse(request.body.read))
      $LOG.debug params
    end

    # empty form variables are empty strings, not nil
    params.each do |key, val|
      params[key] = nil if (val.to_s.length == 0)
    end

    # Don't create a device if there are no parameters (e.g. robot, other probe)
    if ! params.empty?
      params['user_agent'] = request.user_agent unless params['user_agent']
      device = manage_device_id(params)
      params['device_id'] = device.device_id
    end
  end

  def manage_device_id (params)
    #
    # Params:
    #   device_id - can be nil or device_id that doesn't have a device row in DB
    # Returns:
    #   device

    device_id = params['device_id']
    if device_id
      $LOG.debug device_id
      Protocol.create_if_not_exists_device({ device_id: device_id,
                                             user_agent: request.user_agent})
    else
      $LOG.debug "No device_id"
      $LOG.debug params
      # there is no device_id
      # since the native apps create their own device_id from the uuid,
      # this must be a webapp

      # The device_id is stored in the client's cookie
      if (request.cookies['device_id'])
        # a device_id has been set in the cookie
        Protocol.create_if_not_exists_device({ device_id: request.cookies['device_id'],
                                               user_agent: request.user_agent})
      else
        # Brand new web app
        device = Protocol.create_device_id (request.user_agent)
        response.set_cookie('device_id',
                            { :value   => device_id,
                              :domain  => 'geopeers.com',
                              :expires => Time.new(2038,1,17),
                            })
        device
      end
    end
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

  before do
    before_proc (params)
  end

  get '/api' do
    resp = Protocol.process_request params
    if (! resp || resp[:error])
      html = create_error_html (resp)
      halt 500, {'Content-Type' => 'text/html'}, html
    elsif (resp[:redirect_url])
      # If this is a GET and the API wants to redirect,
      # we do it here and the rest of the response is ignored
      redirect resp[:redirect_url]
    elsif (resp[:html])
      content_type :html
      resp[:html]
    else
      content_type :json
      resp.to_json
    end
  end

  post '/api' do
    resp = Protocol.process_request params
    if (resp && resp.class == 'Hash' && resp[:error])
      # Don't send JSON to 500 ajax response
      # resp[:error_html] = create_error_html (resp)
      # content_type :json
      # resp.to_json
      log_error (resp[:error])
      status 500
    else
      response.headers['Access-Control-Allow-Origin'] = '*'
      content_type :json
      resp.to_json
    end
  end

  ['/', '/geo/?'].each do |path|
    get path do
      if request.secure?
        # erb :index
        index_html = Protocol.create_index params
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

