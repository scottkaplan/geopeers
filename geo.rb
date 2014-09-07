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
require 'securerandom'

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
class Account < ActiveRecord::Base
end
class Auth < ActiveRecord::Base
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

def log_error(err)
  if (err.respond_to?(:backtrace))
    msg = err.message + "\n" + err.backtrace.join("\n")
  else
    backtrace = parse_backtrace caller
    backtrace_str = backtrace[0][:file_base] + ':' + backtrace[0][:line_num] + ' ' + backtrace[0][:routine]
    msg = err.inspect + "\n" + backtrace_str
  end
  $LOG.error msg
  Protocol.send_email(msg, 'support@geopeers.com', 'Geopeers Support', 'support@geopeers.com', 'Geopeers Server Error')
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

DOWNLOAD_URLS = {
  ios:     'https://www.geopeers.com/bin/ios/index.html',
  android: 'https://www.geopeers.com/bin/android/index.html',
#  web:     'https://www.geopeers.com/bin/android/index.html',
}

def get_client_type (user_agent)
  if (/android/.match(user_agent))
    :android
  elsif (/iphone/.match(user_agent) ||
         /ipad/.match(user_agent))
    :ios
  else
    :web
  end
  
end

class Protocol
  private

  def Protocol.get_account_from_device (device)
    if (device.account_id)
      Account.find(device.account_id)
    end
  end

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
    "https://eng.geopeers.com/api?method=cred&cred="+share.share_cred
  end

  def Protocol.create_verification_url (params)
    "https://eng.geopeers.com/api?method=verify&cred=#{params['cred']}&device_id=#{params['device_id']}"
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
    device = Device.find_by(device_id: params['device_id'])
    url = Protocol.create_share_url(share, params)
    expire_time = Protocol.format_expire_time(share, params)
    account = Protocol.get_account_from_device (device)
    name = account ? account.name : 'Geopeers'
    message = params['share_message']
    if (share.share_via == 'sms')
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

  def Protocol.send_msg (params, type)
    device = Device.find_by(device_id: params['device_id'])
    url = Protocol.create_verification_url(params)
    if (type == 'email')
      boundary_random = SecureRandom.base64(21)
      template_file = 'views/verify_email_body.erb'
      msg_erb = File.read(template_file)
      html_body = ERB.new(msg_erb).result(binding)
      require 'mail'
      quoted_html_body = Mail::Encodings::QuotedPrintable.encode(html_body)
      template_file = 'views/verify_email_msg.erb'
      msg_erb = File.read(template_file)
      msg = ERB.new(msg_erb).result(binding)
      Protocol.send_email(msg, 'sherpa@geopeers.com', 'Geopeers Helper', params[type], "Please verify your email with Geopeers")
    elsif (type == 'mobile')
      msg = "Press this #{url} to verify your Geopeers account"
      sms_obj = Sms.new
      sms_obj.send(params[type], msg)
    end
  end

  def Protocol.send_share_sms (share, params)
    sms_obj = Sms.new
    msg = Protocol.create_share_msg(share, params)
    err = sms_obj.send(share.share_to, msg)
    if (err)
      error_response err
    else
      {message: 'Location Shared', style: {color: 'blue'}}
    end
  end

  def Protocol.send_email (msg, from_email, from_name, to_email, subject)
    from = "#{from_name} <#{from_email}>"
    msg = "From: #{from}\nTo: #{to_email}\nSubject: #{subject}\n" + msg
    begin
      Net::SMTP.start('127.0.0.1') do |smtp|
        smtp.send_message msg, from_email, to_email
        $LOG.info "Sent email to #{to_email}"
      end
    rescue Exception => e  
      log_error e
      return true
    end
    nil
  end

  def Protocol.send_share_email (share, params)
    device = Device.find_by(device_id: params['device_id'])
    account = Protocol.get_account_from_device (device)
    if (! account)
      log_error ("No account")
      {message: 'There was a problem sending your email.  Support has been contacted', css_class: 'message_error'}
    else
      subject = "#{account.name} shared a location with you"
      msg = Protocol.create_share_msg(share, params)
      $LOG.debug account
      email = account.email ? account.email : 'email_unknown@geopeers.com'
      $LOG.debug email
      err = Protocol.send_email(msg, email, account.name, share.share_to, subject)
      if (err)
        log_error (err)
        {message: 'There was a problem sending your email.  Support has been contacted', css_class: 'message_error'}
      else
        {message: 'Email sent'}
      end
    end
  end

  def Protocol.send_share_facebook (share, params)
    {message: "Facebook shares are not implemented yet"}
  end

  def Protocol.send_share_twitter (share, params)
    {message: "Twitter shares are not implemented yet"}
  end

  def Protocol.send_share (share, params)
    procname = 'send_share_' + share['share_via']
    if (defined? procname)
      (method procname).call(share, params)
    else
      error_response "Bad method " + procname
    end
  end

  def Protocol.error_response (error_msg)
    # { error: error_msg, backtrace: caller }
    { message: error_msg, style: {color: 'red'}}
  end

  def Protocol.process_request_config (params)
    # params: device_id, version
    # returns: js

    if (params[:version].to_i < 1)
      {js: "alert('If we had an upgrade, this would be it')"}
    end
  end

  def Protocol.process_request_send_position (params)
    # parms: device_id, gps_*
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
    {}
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

    if device.account_id
      device_filter = "devices.account_id = #{device.account_id} AND redeems.device_id = devices.device_id"
    else
      device_filter = "redeems.device_id = '#{params['device_id']}'"
    end
    sql = "SELECT sightings.device_id, sightings.gps_longitude, sightings.gps_latitude,
                  MAX(sightings.updated_at) AS max_updated_at,
                  shares.expire_time,
                  accounts.name
           FROM   sightings, devices, shares, redeems, accounts
           WHERE  #{device_filter} AND
                  redeems.share_id = shares.id AND
                  (NOW() < shares.expire_time OR shares.expire_time IS NULL) AND
                  shares.device_id = sightings.device_id AND
                  sightings.device_id = devices.device_id AND
                  devices.account_id = accounts.id AND
                  (accounts.email IS NOT NULL OR accounts.mobile IS NOT NULL)
           GROUP BY sightings.device_id
          "
    $LOG.debug sql
    elems = []
    Sighting.find_by_sql(sql).each { |row|
      elems.push ({ 'name'          => row.name,
                    'device_id'     => row.device_id,
                    'gps_longitude' => row.gps_longitude,
                    'gps_latitude'  => row.gps_latitude,
                    'sighting_time' => row.max_updated_at,
                    'expire_time'   => row.expire_time,
                  })
    }
    $LOG.debug elems
    {'sightings' => elems }
  end

  def Protocol.process_request_get_registration (params)
    if params.has_key?('device_id')
      device = Device.find_by(device_id: params['device_id'])
      if device.nil?
        # This shouldn't happen.  If there is a device_id, it should be in the DB
        log_dos ("No record for "+params['device_id'])
        error_response "Unknown device ID"
      else
        if device.account_id
          Account.find(device.account_id)
        else
          {}
        end
      end
    else
      log_dos ("No device_id")
      return (error_response "No device ID")
    end
  end

  def Protocol.validate_register_params (params)
    return ("Please supply your name") if (params['new_account'] == 'yes' && (! params['name']))
    return ("No device ID") unless (params['device_id'])

    if (params['email'])
      if (! /.+@.+/.match(params["email"]))
        return ("Email should be in the form 'fred@company.com'")
      end
      has_email_or_mobile = true
    end

    if (params['mobile'])
      # We are not just validating, but actually normalizing (changing) the user input
      # We have to do this so that (415) 555-1212 matches 415-5551212
      params['mobile'] = Sms.clean_num(params['mobile'])
      if (! /^\d{10}$/.match(params['mobile']))
        return ("The mobile number must be 10 digits")
      end
      has_email_or_mobile = true
    end

    return ("Please supply your email or mobile number") unless (has_email_or_mobile)

    return
  end

  def Protocol.send_verification_by_type (params, type)
    account = Account.find(params['account_id'])
    $LOG.debug account
    if (params[type])
      # Don't send if already verified
      return if account[type]

      auth = Auth.find_by(account_id: account.id)
      $LOG.debug auth
      if auth
        # Didn't verify, resend existing cred
        params['cred'] = auth.cred
      else
        params['cred'] = SecureRandom.urlsafe_base64(10)
        auth = Auth.new(account_id: params['account_id'],
                        auth_type:  type,
                        auth_key:   params[type],
                        cred:       params['cred'],
                        issue_time: Time.now,
                        )
        auth.save
      end
      err = Protocol.send_msg(params, type)
      if (err)
        log_error (err)
        verification_type = (type == 'email') ? 'email' : 'text msg'
        return ("There was a problem sending your verification #{verification_type}.  Support has been contacted")
      else
        user_msg = params[type]+" has not been verified yet.  The verification has been re-sent"
        return nil, user_msg
      end
    end
  end

  def Protocol.send_verifications (params)
    errs = []
    user_msgs = []
    ['mobile','email'].each do | type |
      err, user_msg = send_verification_by_type(params, type)
      errs.push err if err
      user_msgs.push user_msg if user_msg
    end
    # errors are concatenated, user messages are returned as an array
    err = errs.empty? ? nil : errs.join('<br>')
    return err, user_msgs
  end

  def Protocol.get_existing_account (params, type)
    if (params[type])
      return Account.where(type+"=?", params[type]).first
    end
    return
  end

  def Protocol.get_verified_account (params, type)
    account = Protocol.get_existing_account(params, type)
    if account
      if account[type]
        return account
      else
        return [account, "NOT_VERIFIED"]
      end
    end
  end

  def Protocol.find_account (params, type)
    # look for the account associated with credential (email | mobile) supplied by user
    # returns <account, msg>
    #   nil, msg     => no account, user message
    #   account, nil => account is verified
    #   account, msg => account is not verified, user message (info only)
    return unless params[type]

    account = Protocol.get_existing_account(params, type)
    $LOG.debug account
    if account
      if ! account[type]
        # not verified, resend the verification as a reminder
        # ignore the error, if it failed, the system error was already logged
        params['account_id'] = account.id
        err_msg = Protocol.send_verification_by_type(params, type)
        if err_msg
          log_error (err_msg)
        else
          user_msg = params[type]+" has not been verified yet.  The verification has been re-sent"
        end
      end
    else
      log_dos ("No account for #{params[type]}")
      user_msg = params[type]+" is not an account"
    end
    return account, user_msg
  end

  def Protocol.process_new_account (params)
    user_msgs = []

    # Are these credentials already verified
    device = Device.find_by(device_id: params['device_id'])
    if (! device)
      log_dos ("No device")
      return (["There was a problem with your request."])
    end

    if ! device.account_id
      # create the account and bind device_id to it
      account = Account.new(name: params['name'])
      account.save
      device[:account_id] = account.id
      device.save
    end

    # make sure account (email and/or mobile) doesn't already exist
    account = Protocol.get_existing_account(params, 'mobile')
    user_msgs.push (params['mobile']+" is already registered") if account && account.id != device.account_id
    account = Protocol.get_existing_account(params, 'email')
    user_msgs.push (params['email']+" is already registered") if account && account.id != device.account_id
    return user_msgs unless (user_msgs.empty?)

    params['account_id'] = device.account_id
    err, user_msgs = Protocol.send_verifications (params)
    return err, user_msgs
  end

  def Protocol.process_existing_account (params)
    # associate device_id with an existing account
    # since we have email and/or mobile, this requires a few twists

    user_msgs = []
    account_mobile, user_msg = find_account(params, 'mobile')
    user_msgs.push (user_msg) if user_msg
    account_email, user_msg = find_account(params, 'email')
    user_msgs.push (user_msg) if user_msg
    # Don't use user_msgs as status
    # use accounts to determine if there is an existing account
    if (! account_mobile && ! account_email)
      return error_response user_msgs.join ('<br>')
    end
    if (account_mobile && account_email && (account_mobile.id != account_email.id))
      # This is a problem, the email points to one account and the mobile to another
      return error_response "The email and mobile are not associated with the same account"
    end
    # We can finally get to one account
    account = account_mobile ? account_mobile : account_email
    params['account_id'] = account.id
    device = Device.find_by(device_id: params['device_id'])
    device[:account_id] = account.id
    device.save

    return nil, user_msgs
  end

  def Protocol.process_registration (params)
    user_msgs = []
    if (params['new_account'] == 'yes')
      err, user_msgs = Protocol.process_new_account (params)
      return error_response err if (err)
    else
      err, user_msgs = Protocol.process_existing_account (params)
      return error_response err if (err)
    end

    # If we get to here there is an account which may or may not be verified
    # redirect to the native app download URL
    if (params['download_app'])
      client_type = get_client_type ()
      redirect_url = DOWNLOAD_URLS[client_type]
      if (redirect_url)
        if ! user_msgs.empty?
          msg = URI.escape (user_msgs.join('<br>'))
          redirect_url += "?alert=#{msg}"
        end
        {redirect_url: redirect_url}
      else
        user_msgs.push "There is no native app available for your device"
        {message: user_msgs.join('<br>'), style: {color:"red"}}
      end
    end
  end

  def Protocol.manage_registration (params)
    device = Device.find_by(device_id: params['device_id'])
    msgs = []
    if device.account_id
      account = Account.find(device.account_id)
      if account
        if (params['name'] != account.name)
          account.name = params['name']
          account.save
          msgs.push ("Account name changed to #{account.name}")
        end
        ['mobile','email'].each do | type |
          if (params[type] != account[type])
            params['account_id'] = account.id
            err = send_verification_by_type(params, type)
            if err
              msgs.push (err)
            else
              msgs.push ("A verification was sent to #{params[type]}")
            end
          end
        end
      else
        log_error "No account for #{device.account_id}"
        msgs.push "No account for #{device.account_id}"
      end
    else
      log_error "No account"
      msgs.push "No account"
    end
    if msgs.empty?
      {message: 'The changes have been made', style: {color:"green"}}
    else
      {message: msgs.join('<br>'), style: {color:"red"}}
    end
  end

  def Protocol.process_request_register_device (params)
    # register name/email/mobile with an account
    # send the verification
    #
    err = Protocol.validate_register_params (params)
    return (error_response err) if (err)

    if params['registration_edit']
      # changes to an existing account
      Protocol.manage_registration (params)
    else
      # standard login (new or existing)
      Protocol.process_registration (params)
    end
  end

  def Protocol.process_request_share_location (params)
    # create a share and send it
    raise ArgumentError.new("No share via") unless params['share_via']
    raise ArgumentError.new("No device ID")  unless params['device_id']
    
    raise ArgumentError.new("Please supply the address to send the share to") unless params['share_to']

    if params["share_via"] == 'sms'
      sms_num = Sms.clean_num(params["share_to"])
      raise ArgumentError.new("The phone number (share to) must be 10 digits") unless /^\d{10}$/.match(sms_num)
    end

    if params["share_via"] == 'email'
      # In general, RFC-822 email validation can't be done with regex
      # For now, just make sure it has an '@'
      raise ArgumentError.new("Email should be in the form 'fred@company.com'") unless /.+@.+/.match(params["share_to"])
    end
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
    share = Share.find_by(share_cred: params["cred"])
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

  def Protocol.process_request_verify (params)
    # an auth was created to update a value in an account
    # In this request, we get a cred
    # If it corresponds to an auth,
    # then update the account with the info in the auth
    auth = Auth.find_by(cred: params["cred"])
    $LOG.debug auth
    device = Device.find_by(device_id: params['device_id'])
    $LOG.debug device
    redirect_url = 'https://geopeers.com'
    if (! auth || ! device || auth.account_id != device.account_id)
      log_dos (params)
      msg = "That credential is not valid.  You can't view the location.  You can still use the other features of GeoPeers"
    else
      auth.auth_time = Time.now
      auth.save
      account = Account.find(auth.account_id)
      account[auth.auth_type] = auth.auth_key
      account.save
      $LOG.debug account
      msg = account.name+" has been registered"
      message_type = 'message_success'
    end
    msg = URI.escape (msg)
    redirect_url += "?alert=#{msg}"
    redirect_url += "&download_app=1&device_id=#{device.device_id}"
    redirect_url += "&message_type=#{message_type}" if message_type
    return {:redirect_url => redirect_url}
  end
  
  def Protocol.process_request_device_id_bind (params)
    # A native app redirected to:
    #   /api?method=device_id_bind&native_app_device_id=<native app device_id>"
    # The webview opens this URL, so the webapp device_id is in the cookie
    native_app_device = Device.find_by(device_id: params['native_app_device_id'])
    web_app_device = Device.find_by(device_id: params['device_id'])
    if native_app_device.account_id
      if web_app_device.account_id
        if native_app_device.account_id == web_app_device.account_id
          $LOG.debug "native/web app account_id match: "+native_app_device.account_id
          return
        else
          # This is not good, the webapp and native app got different accounts
          log_error ("Account conflict:"+native_app_device.inspect+","+web_app_device.inspect)
        end
      else
        # Native app was installed on a device where the web app was never run
        # Associate the web app with this native app
        # so the native app gets any shares that wind up in the web app
        $LOG.debug "setting web app to account_id "+native_app_device.account_id
        web_app_device.account_id = native_app_device.account_id
        web_app_device.save
      end
    else
      if web_app_device.account_id
        # This is the common case
        # An account was created in the web app, probably when the native app was downloaded
        # The native app was installed on the same device
        # When the native app started,
        # it redirected to the webview where the registration/download happened
        $LOG.debug "setting native app to account_id "+web_app_device.account_id
        native_app_device.account_id = web_app_device.account_id
        native_app_device.save
      else
        # This shouldn't happen, there should be an account somewhere
        # Create the account and assign to both web and native app
        # But this means there is no user-generated name
        # It's better to generate one than leave it empty
        name = "anon_"+SecureRandom.hex(6)
        account = Account.new(name: name)
        account.save
        $LOG.debug "created new account "+account.id+" with name "+account.name
        native_app_device.account_id = account.id
        native_app_device.save
        web_app_device.account_id = account.id
        web_app_device.save
      end
    end
    # redirect back to the native app with the device_ids
    native_app_deeplink = "geopeers://api?method=device_id_bind&native_app_device_id="
    native_app_deeplink += native_app_device.device_id
    native_app_deeplink += "&web_app_device_id="
    native_app_deeplink += web_app_device.device_id
    {redirect_url: native_app_deeplink}
  end
  
  def Protocol.process_request_get_shares (params)
    # get a list of device_ids that are registered with the same device.email as params['device_id']
    # and create a comma-separate list, suitable for putting in the SQL IN clause
    device = Device.find_by(device_id: params['device_id'])
    if device.account_id
      device_filter = "devices.account_id = #{device.account_id} AND redeems.device_id = devices.device_id"
      devices_table = ", devices"
    else
      device_filter = "redeems.device_id = #{params['device_id']}"
    end

    # get all the shares with those device_ids
    # and a list of the device_id that redeemed the shares
    sql = "SELECT shares.share_to, shares.share_via, shares.expire_time,
                    shares.updated_at, shares.created_at,
                    redeems.id AS redeem_id,
                    redeems.created_at AS redeem_time,
                    accounts.name AS redeem_name
             FROM accounts #{devices_table}, shares
             LEFT JOIN redeems ON shares.id = redeems.share_id
             WHERE  #{device_filter}
            "
    # Find the names associated with the redeemed device_ids
    elems = []
    Share.find_by_sql(sql).each { |row|
      elems.push (row)
    }
    {'shares' => elems }
  end

  public
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
    begin
      device_record = Device.new(device_id: device_id,
                                 user_agent: user_agent)
      device_record.save
    rescue => err
      log_error (err)
    end
    device_id
  end

  before do
    # empty form variables are empty strings, not nil
    params.each do |key, val|
      params[key] = nil if (val.length == 0)
    end
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
    # If the client sent a JSON object in the body of the request,
    # (typically used to send a >1 layer parms in a request)
    # merge that object with any parms that were passed in the request
    if (request.content_type == 'application/json')
        params.merge!(JSON.parse(request.body.read))
    end

    # parameters to add
    params['device_id'] = params['device_id'] ? params['device_id'] : get_device_id()
    params['user_agent'] = request.user_agent

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
