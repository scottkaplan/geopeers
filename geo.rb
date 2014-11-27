#!/usr/bin/ruby

# The backend server for Geopeers
#
# Author:: Scott Kaplan (mailto:scott@kaplans.com)
# Copyright:: Copyright (c) 2014 Scott Kaplan

require 'bundler'
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
class Milestone < ActiveRecord::Base
end

class Logging
  def self.milestone (msg)
    params_json = $params.to_json
    $LOG.debug params_json
    Milestone.create(method: $params['method'],
                     message: msg,
                     params: params_json)
  end
end

def init_log
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
end

def log_dos(msg)
  $LOG.error msg
  return
end

def log_info(msg)
  $LOG.info msg
  Protocol.send_email(msg, 'support@geopeers.com', 'Geopeers Support', 'support@geopeers.com', 'Geopeers Server Info')
  msg
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

def format_account_name (account)
  account.name ? "#{account.name}(#{account.id})" : account.id
end

def format_device_name (device)
  account = Protocol.get_account_from_device(device)
  if account.name
    account.name + '(' + device.device_id + ')'
  else
    device.device_id
  end
end

def format_device_id_name (device_id)
  device = Device.find_by(device_id: device_id)
  format_device_name (device)
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

def parse_backtrace (backtrace) 
  ar = []
  backtrace.each { |x|
    /(?<path>.*?):(?<line_num>\d+):in `(?<routine>.*)'/ =~ x
    file_base = File.basename(path)
    ar.push({file_base: file_base, line_num: line_num, routine: routine})
  }
  ar
end

def host
  Socket.gethostname
end

def url_base
  'https://geopeers.com'
end

def log_error(err)
  msg = "On " + host() + "\n\n"
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
  # strip optional leading '?'
  params_str = /\??(.*)/.match(params_str).to_s

  params = {}
  params_str.split('&').each { |param_str|
    key, val = param_str.split('=')
    params[key] = val
  }
  params
end

def create_alert_url(alert_method, params=nil)
  url = "#{url_base()}/?alert_method=#{alert_method}"
  if params
    params.each do | key, val |
      url += "&#{key}=#{val}"
    end
  end
  url
end

def create_and_send_share(share_params, params, response)
  $LOG.debug share_params
  share_params['share_cred'] = SecureRandom.urlsafe_base64(10)
  share = Share.create(share_params)

  # Can't have tz in Share.new (share_params)
  # Need it in send_share, so add it now
  share_params.merge! (params)
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
  Dir.chdir (File.dirname(__FILE__))
  init_log
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
  # $LOG.debug ARGV
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
  ios:     url_base() + '/bin/ios/index.html',
  android: url_base() + '/bin/android/index.html',
#  web:     url_base() + '/bin/android/index.html',
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
  set_global('build_id', 1)
  value = get_global('build_id')
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

def create_index(params=nil)
  version = "0.7"
  is_phonegap = nil
  is_production = nil
  url_prefix = nil
  block_gps_spinner = nil
  share_location_my_contacts_tag = nil
  is_production = params && params[:is_production]
  block_gps_spinner = params && params[:block_gps_spinner]
  initial_js = params && params[:initial_js]

  if params && params[:is_phonegap]
    build_id = bump_build_id()
    params['url_prefix'] = ""
    is_phonegap = true
  else
    build_id = get_build_id()
    params['url_prefix'] = "https://prod.geopeers.com/"
    is_phonegap = false
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
  download_app_popup =
    make_popup("download_app_popup",
               "Download Native App",
               "views/download_app_form.erb",
               params)
  native_app_switch_popup =
    make_popup("native_app_switch_popup",
               "Switch to Native App",
               "views/native_app_switch_form.erb",
               params)
  update_app_popup =
    make_popup("update_app_popup",
               "Update Native App",
               "views/update_app_form.erb",
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
               "Manage Shared Locations",
               "views/share_management_form.erb",
               params)
  ERB.new(File.read('views/index.erb')).result(binding)
end

def make_popup(popup_id, popup_title, nested_erb, params)
  share_location_my_contacts_tag = nil
  if params && params[:is_phonegap]
    share_location_my_contacts_tag = '<option value="contacts">Select from My Contacts</option>'
  end
  url_prefix = params['url_prefix']
  nested_html = ERB.new(File.read(nested_erb)).result(binding)
  ERB.new(File.read('views/popup.erb')).result(binding)
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
    url_base() + "/api?method=redeem&cred="+share.share_cred
  end

  def Protocol.create_verification_url (params)
    url_base() + "/api?method=verify&cred=#{params['cred']}&device_id=#{params['device_id']}"
  end

  def Protocol.create_download_url (params)
    url_base() + "/api?method=download_app&device_id=#{params['device_id']}"
  end

  def Protocol.create_unsolicited_url (params)
    url_base() + "/api?method=unsolicited&cred=#{params['cred']}&device_id=#{params['device_id']}"
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

  def Protocol.send_share_sms (share, params)
    # Temporary hack
    # This used to be called 'sms'
    # All references should be gone, but we're being careful
    log_error("Warning: saw 'sms', not 'mobile'")
    Protocol.send_share_mobile(share, params)
  end
  
  def Protocol.send_share_mobile (share, params)
    sms_obj = Sms.new
    msg = Protocol.create_share_msg(share, params)
    err = sms_obj.send(share.share_to, msg)
    if (err)
      return error_response err
    end
    if params['share_message']
      account = Protocol.get_account_from_device_id (params['device_id'])
      msg = ""
      if account && account.name
        msg = "From #{account.name}: "
      end
      msg += params['share_message']
      err = sms_obj.send(share.share_to, msg)
    end
    if (err)
      return error_response err
    end
    {message: "Sent location share to #{share.share_to}"}
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
    { message: error_msg, css_class: 'message_error'}
  end

  def Protocol.send_share (share, params)
    procname = 'send_share_' + share['share_via']
    if (defined? procname)
      (method procname).call(share, params)
    else
      error_response "Bad method " + procname
    end
  end

  def Protocol.create_device(device_id, user_agent, app_type)
    device = Device.new(device_id:   device_id,
                        user_agent:  user_agent,
                        app_version: get_build_id(),
                        app_type:    app_type,
                        )
    account = Account.create()
    device[:account_id] = account.id
    device.save

    Logging.milestone ("created device #{device_id}, account=#{account.id}")
    device
  end

  def Protocol.create_device_id (user_agent)
    require 'securerandom'
    device_id = SecureRandom.uuid
    # if we create the device_id, it's a webapp
    Protocol.create_device(device_id, user_agent, 'webapp')
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

    native_app_device = Device.find_by(device_id: params['native_device_id'])
    $LOG.debug native_app_device
    if ! native_app_device
      log_error ("No native app device")
      url = create_alert_url("SUPPORT_CONTACTED")
      return {redirect_url: url}
    end

    # manage_device_id should have been called already, so if there isn't a device_id set,
    # something has gone very wrong
    if ! params['device_id']
      log_error ("No web app device id")
      url = create_alert_url("SUPPORT_CONTACTED")
    end

    web_app_device = Device.find_by(device_id: params['device_id'])
    $LOG.debug web_app_device

    if web_app_device.xdevice_id &&
        web_app_device.xdevice_id != native_app_device.device_id
      log_error ("changing web_app_device.xdevice_id from #{web_app_device.xdevice_id} to #{native_app_device.device_id}\nProbably from deleting and re-installing the native app")
    end
    web_app_device.xdevice_id = native_app_device.device_id
    web_app_device.save

    if native_app_device.xdevice_id &&
        native_app_device.xdevice_id != web_app_device.device_id
      log_error ("changing native_app_device.xdevice_id from #{native_app_device.xdevice_id} to #{web_app_device.device_id}")
    end
    native_app_device.xdevice_id = web_app_device.device_id
    native_app_device.save

    # The deeplink includes these parameters for completeness.
    # Since we will merge the accounts here,
    # the native app doesn't need to do anything with these params

    if native_app_device.account_id == web_app_device.account_id
      # This was already done
      html = create_index({is_production: true,
                           block_gps_spinner: true,
                           initial_js: "device_id_bind_webapp('SHARES_XFERED')"})
    else
      native_app_account = Protocol.get_account_from_device(native_app_device)
      web_app_account = Protocol.get_account_from_device(web_app_device)
      errs = Protocol.merge_accounts(native_app_account, web_app_account);
      if errs.empty?
        html = create_index({is_production: true,
                             block_gps_spinner: true,
                             initial_js: "device_id_bind_webapp('SHARES_XFERED_COUNTDOWN')"})
      else
        message = errs.join('<br>')
        html = create_index({is_production: true,
                             block_gps_spinner: true,
                             initial_js: "device_id_bind_webapp('SHARES_XFERED_MSG', '#{message}')"})
      end
      event_msg = "bound web app "
      event_msg += format_device_name web_app_device
      event_msg += " to native app "
      event_msg += format_device_name native_app_device
      Logging.milestone (event_msg)
    end
    $LOG.debug html
    {html: html}
  end

  def Protocol.process_request_config (params)
    ##
    # config
    #
    # client sends config request at startup
    #
    # params
    #   device_id
    #   version - current client version
    #
    # returns
    #   js - client will execute this js
    #     

    response = {}
    # handle upgrade
    current_build_id = get_global ('build_id')
    device = Device.find_by(device_id: params['device_id'])
    if (params['version'] &&
        params['version'].to_i < current_build_id.to_i &&
        device['app_type'] == 'native')
      response.merge! ({update: true})
    end

    if device.account_id
      account = Protocol.get_account_from_device(device)
      if account.name
        response.merge! ({account_name: true})
      else
        response.merge! ({account_name: false})
      end
    else
      response.merge! ({account_name: false})
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

    sighting = Sighting.create(device_id:     params['device_id'],
                               gps_longitude: longitude,
                               gps_latitude:  latitude,
                              )
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

    sql = "SELECT DISTINCT sightings.device_id,
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
    # $LOG.debug sql.gsub("\n"," ")
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
          account = Protocol.get_account_from_device(device)
          {account: account, device: device}
        else
          {device: device}
        end
      else
        # This shouldn't happen.  If there is a device_id, it should be in the DB
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
        user_msg = "We were waiting for a verification for #{auth.auth_key}"
        user_msg += "That verification will now verify #{new_val}.  And a new verification was sent to #{new_val}"
        auth.auth_key = new_val
        Logging.milestone (user_msg)
        auth.save
      end
    else
      params['cred'] = SecureRandom.urlsafe_base64(10)
      auth = Auth.create(account_id: account.id,
                         auth_type:  type,
                         auth_key:   new_val,
                         cred:       params['cred'],
                         issue_time: Time.now,
                        )
      user_msg = "A verification was sent to #{new_val}"
      Logging.milestone (user_msg)
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
      user_msg = "Account name changed to #{account.name}"
      Logging.milestone (user_msg)
      msgs.push (user_msg)
      account.save
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

    msgs.push ("No changes") if (errs.empty? && msgs.empty?)
    $LOG.debug errs
    $LOG.debug msgs
    return errs, msgs
  end

  def Protocol.process_request_register_device (params)
    # params:
    #   method = 'register_device'
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

    account = Protocol.get_account_from_device (device)
    if account
      # This device is already associated with an account
      # params are changes to that account
      errs, user_msgs = Protocol.manage_account(params, account)
    else
      errs.push ("No account for device")
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

  def Protocol.process_request_share_location (params)
    # The form is in views/share_location_form.erb

    raise ArgumentError.new("No device ID")  unless params['device_id']

    response = {}

    # First, if the device user has supplied a name, apply it.
    if params['account_name']
      account = Protocol.get_account_from_device_id (params['device_id'])
      if account
        account.name = params['account_name']
        account.save
        user_msg = "Name set to #{account.name}"
        response['message'] = user_msg
        Logging.milestone (user_msg)
      end
    end

    # there are multipe ways to specify a share from the share_location form
    #   1) seer_device_id:
    #      boomerang share - A shares with B, now B wants to share with A
    #   2) my_contacts_mobile and/or my_contacts_email
    #      A single value came back from the device Contacts picker
    #   3) my_contacts_mobile_dropdown and/or my_contacts_email_dropdown
    #      Multiple values came back from the device Contacts picker and the user picked one
    #   4) share_via/share_to
    #      Explicitly type into text box

    # create the share
    expire_time = compute_expire_time params
    expire_time = Time.now + expire_time if expire_time
    share_parms = {
      expire_time:  expire_time,
      num_uses:     0,
      num_uses_max: params["num_uses"],
      active:       1,
    }
    share_parms['device_id'] = params["device_id"]

    if params['seer_device_id']
      # share location of requesting device
      # with account associated with a share
      # (i.e. share my location with pin)
      #
      account = Protocol.get_account_from_device_id (params['seer_device_id'])
      ['mobile','email'].each do | type |
        if account[type]
          response = create_and_send_share(share_parms.merge({ share_via: type,
                                                               share_to:  account[type],
                                                             }),
                                           params,
                                           response)
          Logging.milestone ("Share by seer_device_id to #{account[type]} via #{type}")
        end
      end
      # TODO: This only returns the last response
      #       if both mobile and email are set in account, the first response is ignored

      if response.empty?
        response[popup_message] = 'No email or phone number found'
      end
    end

    ['mobile','email', 'mobile_dropdown', 'email_dropdown'].each do | field_type |
      my_contacts_field = "my_contacts_#{field_type}"
      if params[my_contacts_field]
        $LOG.debug params[my_contacts_field]
        type = field_type.sub(/_dropdown/, '')
        share_to = params[my_contacts_field]
        response = create_and_send_share(share_parms.merge({ share_via: type,
                                                             share_to:  share_to,
                                                           }),
                                         params,
                                         response)
        Logging.milestone ("Share by #{my_contacts_field} to #{share_to} via #{type}")
      end
    end
      
    if params['share_to']
      if ! params['share_via']
        # see if we can figure it out
        if /.+@.+/.match(params["share_to"])
          params["share_via"] = 'email'
        else
          sms_num = Sms.clean_num(params["share_to"])
          if /^\d{10}$/.match(sms_num)
            params["share_via"] = 'mobile'
          else
            response['popup_message'] = "#{params['share_to']} doesn't look like an email or phone number"
            # This can fall thru since share_via is not set
          end
        end
      end
      
      if params["share_via"] == 'mobile'
        sms_num = Sms.clean_num(params["share_to"])
        if /^\d{10}$/.match(sms_num)
          response = create_and_send_share(share_parms.merge({ share_via: params['share_via'],
                                                               share_to:  params['share_to'],
                                                             }),
                                           params,
                                           response)
          Logging.milestone ("Share by typing to #{params['share_to']} via #{params['share_via']}")
        else 
          response['popup_message'] = "The phone number (share to) must be 10 digits"
        end
      end

      if params["share_via"] == 'email'
        # In general, RFC-822 email validation can't be done with regex
        # For now, just make sure it has an '@'
        if /.+@.+/.match(params["share_to"])
          response = create_and_send_share(share_parms.merge({ share_via: params['share_via'],
                                                               share_to:  params['share_to'],
                                                             }),
                                           params,
                                           response)
          Logging.milestone ("Share by typing to #{params['share_to']} via #{params['share_via']}")
        else
          response['popup_message'] = "Email should be in the form 'fred@company.com'"
        end
      end
    end

    $LOG.debug response
    response
  end

  def Protocol.process_request_redeem (params)
    # a share URL has been clicked
    # using the cred, create a redeem for the share

    # get the share for this cred
    share = Share.find_by(share_cred: params[:cred])
    redirect_url = url_base()

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
        current_share = Share.find_by_sql(sql).first
        if (current_share)
          if ( ! current_share.expire_time)
            # we already have an unlimited share
            return {:redirect_url => redirect_url}
          end

          event_msg = ''
          if (! share.expire_time)
            # the new share doesn't expire, use it
            event_msg = "using new infinite share"
            redeem = Redeem.find (current_share.redeem_id)
            redeem.share_id = share.id
          elsif (current_share.expire_time >= share.expire_time)
            # this current_share expires after the new share, ignore the new share
            event_msg = "using existing share"
            return {:redirect_url => redirect_url}
          else
            # the new share expires after the current share, update the redeem with the new share
            event_msg = "updating redeem with new share"
            redeem = Redeem.find (current_share.redeem_id)
            redeem.share_id = share.id
          end
        else
          event_msg = "no existing share"
          redeem = Redeem.new(share_id:  share.id,
                              device_id: params["device_id"])
        end
        redeem.save
        $LOG.debug redeem
        share.num_uses = share.num_uses ? share.num_uses+1 : 1
        share.save

        seer_name = format_device_id_name redeem.device_id
        seen_name = format_device_id_name share.device_id
        Logging.milestone "#{seer_name} can now see #{seen_name} - #{event_msg}"

        device = Device.find_by(device_id: params['device_id'])
        if device &&
            device.app_type == 'webapp' &&
            device.xdevice_id
          # This share was redeemed by a webapp with a native app on the device
          # deeplink to the native app
          redirect_url = "geopeers://"
        end
      else
        # This share has been used up
        redirect_url = create_alert_url("CRED_INVALID")
      end
    else
      redirect_url = create_alert_url("CRED_INVALID")
    end
    $LOG.debug redirect_url
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
      redirect_url = create_alert_url("CRED_INVALID")
    else
      # auth_cred and device are good
      # But it is possible that there are two different accounts
      #   1) This device_id has an account
      #   2) There is an account associated with the value 
      account_for_device = Protocol.get_account_from_device device

      $LOG.debug account_for_device
      account_from_val = Account.where("#{auth_cred.auth_type}=? AND active = 1",auth_cred.auth_key).first
      $LOG.debug account_from_val
      event_msg = ''
      if  account_from_val &&
          account_from_val.id != device.account_id
        # this value is used in another account, merge
        redirect_url = create_alert_url("DEVICE_ADDED",
                                        { auth_key: auth_cred.auth_key,
                                          account_name: account_from_val.name,
                                        })
        warns = Protocol.merge_accounts(account_from_val, account_for_device)
        if ! warns.empty?
          log_error warns.join("\n")
        end
        device.account_id = account_from_val.id
        device.save
        account = account_from_val
        event_msg = ", merged account " + format_account_name(account_for_device)
      else
        redirect_url = create_alert_url("DEVICE_REGISTERED",
                                        { account_name: account_for_device.name })
        account = account_for_device
      end
      auth_cred.auth_time = Time.now
      auth_cred.save
      account[auth_cred.auth_type] = auth_cred.auth_key
      account.save
      Logging.milestone "Assigned #{auth_cred.auth_key} to account " + format_account_name(account) + event_msg
    end
    redirect_url += "&device_id=#{device.device_id}"
    return {:redirect_url => redirect_url}
  end

  def Protocol.merge_accounts(account_1, account_2)
    # merge account_2 into account_1

    $LOG.debug account_1
    $LOG.debug account_2

    warn_msgs = []
    ['name', 'mobile', 'email'].each do | type |
      if account_2[type]
        # merge the attributes of the account record
        if account_1[type]
          if account_1[type] != account_2[type]
            # This is bad
            msg = "The #{type} #{account_2[type]} will no longer be used. You can continue to use #{account_1[type]}."
            warn_msgs.push (msg)
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
    warn_msgs
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
                    redeems.created_at AS redeem_time,
                    redeems.device_id AS redeem_device_id
          FROM accounts, devices, shares
          LEFT JOIN redeems ON shares.id = redeems.share_id
          WHERE devices.account_id = #{device.account_id} AND
                accounts.id = devices.account_id AND
                shares.device_id = devices.device_id"
    $LOG.debug sql
    # Find the names associated with the redeemed device_ids
    elems = []
    Share.find_by_sql(sql).each { |row|
      elem = {}
      row.attributes.each { |key, val|
        elem[key] = val
      }
      account = Protocol.get_account_from_device_id (row.redeem_device_id)
      if account
        elem['redeem_name'] = account['name'] ? account['name'] : "Anonymous"
      end
      elems.push (elem)
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
    url = Protocol.create_download_url(params)
    if params['email']
      email_err = Protocol.send_html_email('views/download_email_body.erb', 'views/download_email_msg.erb',
                                           "Download your Geopeers app", params['email'],
                                           {url: url}
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
    {redirect_url: url_base() + "/?download_app=1"}
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
    account_share = Protocol.get_account_from_device_id (share.device_id)
    account_device_id = Protocol.get_account_from_device_id (params['device_id'])
    if (account_share.id != account_device_id.id)
      log_error ("Account for share #{params['share_id']} is #{account_share.id}, device_id #{share.device_id}, does not match ${account_device_id.id}, device_id #{params['device_id']}")
      return (error_response)
    end
    share.active = share.active == 1 ? 0 : 1
    share.save
    Logging.milestone "Set share to #{share.share_to} active=#{share.active}"
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

  def Protocol.support_section (title, content)
    msg = "<div style='font-size:20px; font-weight:bold'>#{title}</div>"
    msg += "<div style='font-size:18px; font-weight:normal; margin-left:10px'>#{content}</div>"
    
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
    msg += Protocol.support_section('Version', params['support_version'])
    ['problem', 'reproduction', 'feature', 'cool_use'].each do | field |
      field_name = 'support_form_'+field
      val = params[field_name]
      next unless val
      field_display = field.capitalize.gsub("_", " ")
      msg += Protocol.support_section(field_display, val)
    end
    Protocol.send_email(msg, 'support@geopeers.com',
                        'Geopeers Support', 'support@geopeers.com',
                        'Geopeers Customer Request', 1)
    {message:"Message sent, thanks!"}
  end

  public

  def Protocol.create_if_not_exists_device (params)
    device = Device.find_by(device_id: params[:device_id])
    if device
      device
    else
      # This is a device_id we haven't seen yet
      # Unless the caller told us, assume it is a native app
      # because if we created the device_id,
      # we would have created the device record at the same time
      app_type = params[:app_type] ? params[:app_type] : 'native'
      Protocol.create_device(params[:device_id], params[:user_agent], app_type)
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
                                             user_agent: request.user_agent })
    else
      $LOG.debug "No device_id"
      $LOG.debug params
      $LOG.debug request.cookies
      # there is no device_id
      # since the native apps create their own device_id from the uuid,
      # this must be a webapp

      # The device_id is stored in the client's cookie
      if (request.cookies['device_id'])
        # we shouldn't get here
        # This means there is a device_id cookie, but it wasn't in params
        # Since params['device_id'] gets set from the cookie in the Sinatra DSL
        # this shouldn't happen
        Protocol.create_if_not_exists_device({ device_id:  request.cookies['device_id'],
                                               user_agent: request.user_agent,
                                               app_type:   'webapp',
                                             })
      else
        # Brand new web app
        device = Protocol.create_device_id (request.user_agent)
        response.set_cookie('device_id',
                            { :value   => device.device_id,
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

  get '/' do
    if request.secure?
      manage_device_id ({})

      # Three ways to send the index file:
      #
      # single ERB (nothing is ever that simple in production :-)
      # erb :index

      # RT processing
      # ~ 300ms
      params['is_production'] = false
      create_index params

      # pre-processed
      # ~ 200ms
      # index_html = File::read("/home/geopeers/sinatra/geopeers/public/main_page.html")
    else
      redirect request.url.gsub(/^http/, "https")
    end
  end

  after do
    # if we don't do this,
    # bad things when we run under passenger
    ActiveRecord::Base.clear_active_connections!
  end

end

init()

