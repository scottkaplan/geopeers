#!/usr/bin/ruby
require './geo.rb'
require 'net/http'
require 'json'
require 'pry'

COORDS = {
  new_orleans:   {latitude: 29.9667, longitude:  -90.0500},
  san_francisco: {latitude: 37.7833, longitude: -122.4167},
  new_york:      {latitude: 40.7127, longitude:  -74.0059},
  us_center:     {latitude: 39.8282, longitude:  -98.5795},
}

TEST_VALUES = {
  name_1:        'Scott Kaplan',
  email_good_1:  'test@geopeers.com',
  email_good_2:  'scott@kaplans.com',
  email_bad_1:   'noone@magtogo.com',
  email_bad_2:   'NotAnAddress',
  mobile_good_1: '4156521706',
  mobile_bad_1:  '123',
  user_agent:    "tire rim browser",
}

ERROR_MESSAGES = {
  email_or_mobile: 'Please supply your email or mobile number',
  email_bad: "Email should be in the form 'fred@company.com'",
  mobile_bad: "The mobile number must be 10 digits",
}

def call_api(method, device_id, extra_parms)
  procname = "process_request_#{method}"
  params = {
    'method'     => method,
    'device_id'  => device_id,
  }
  params.merge!(extra_parms)
  puts params.inspect
  response = Protocol.send(procname, params)
  puts response.inspect
  response
end

def get_auth_by_device_id(device_id, key, type)
  sql = "SELECT auths.* FROM auths, devices
         WHERE devices.device_id = '#{device_id}' AND
               devices.account_id = auths.account_id AND
               auths.auth_key = '#{key}' AND
               auths.auth_type = '#{type}' AND
               auths.created_at < TIMESTAMPADD(SECOND, 5, NOW())
        "
  Auth.find_by_sql(sql).first
end

RSpec.describe Protocol, production: true do
  method = "config"
  device_id = "TEST_DEV_42"

  user_agent = TEST_VALUES[:user_agent]
  current_version = 1

  context "when does not exist before" do
    it "creates device_id record" do
      device_before = Device.find_by(device_id: device_id)
      device_before.destroy() if device_before

      response = call_api(method, device_id,
                          { 'user_agent' => user_agent,
                            'version'    => current_version+1})

      device_after = Device.find_by(device_id: device_id)
      expect(device_after).not_to be_nil
    end
  end

  context "when does exist before"
  it "device_id record is unchanged" do
    device_before = Device.find_by(device_id: device_id)
    device_before ||= Device.new(device_id:  device_id,
                                 user_agent: TEST_VALUES[:user_agent])
    expect(device_before).not_to be_nil

    response = call_api(method, device_id,
                        { 'user_agent' => user_agent,
                          'version'    => current_version+1})

    device_after = Device.find_by(device_id: device_id)
    expect(device_after).not_to be_nil
    expect(device_before.id).to eq(device_after.id)
  end

  context "when sent old version"
  it "gets JS" do
    response = call_api(method, device_id,
                        { 'user_agent' => user_agent,
                          'version'    => current_version,
                        })

    expect(response[:js]).not_to be_nil
  end

end

RSpec.describe Protocol, production: true do
  method = "send_position"
  device_id = "TEST_DEV_42"

  def look_for_sighting (device_id, gps_longitude, gps_latitude)
    sql = "SELECT * FROM sightings WHERE device_id = '#{device_id}' AND gps_longitude = #{gps_longitude} AND gps_latitude = #{gps_latitude} AND created_at < TIMESTAMPADD(SECOND, 5, NOW())"
    puts sql
    Sighting.find_by_sql(sql).first
  end

  context "with syntax 1"
  it "creates sighting record" do
    gps_longitude = COORDS[:new_orleans][:longitude]
    gps_latitude  = COORDS[:new_orleans][:latitude]

    response = call_api(method, device_id,
                        { 'gps_longitude' => gps_longitude,
                          'gps_latitude'  => gps_latitude,
                        })

    expect(response[:status]).to eql("OK")

    sighting = look_for_sighting(device_id, gps_longitude, gps_latitude)
    expect(sighting).not_to be nil
  end

  context "with syntax 2"
  it "creates sighting record" do
    gps_longitude = COORDS[:new_york][:longitude]
    gps_latitude  = COORDS[:new_york][:latitude]
    response = call_api(method, device_id,
                        { 'location'      => {
                            'longitude' => gps_longitude,
                            'latitude'  => gps_latitude,
                            }
                        })

    expect(response[:status]).to eql("OK")

    sighting = look_for_sighting(device_id, gps_longitude, gps_latitude)
    expect(sighting).not_to be nil
  end
end

RSpec.shared_examples "a bad set of parameters" do | method, device_id, new_account, name, email, mobile, error_message |
  it "get error" do
    response = call_api(method, device_id,
                        { 'new_account' => new_account,
                          'name'        => name,
                          'email'       => email,
                          'mobile'      => mobile,
                        })
    expect(response[:message]).to match(/#{error_message}/i)
  end
end

RSpec.shared_examples "start the verification process" do | method, device_id, new_account, name, email, mobile |
  it "creates account, auth and device.account_id" do
    response = call_api(method, device_id,
                        { 'new_account' => new_account,
                          'name'        => name,
                          'email'       => email,
                          'mobile'      => mobile,
                        })
    ['mobile','email'].each do | type |
      val = type == 'email' ? email : mobile
      if val
        auth = get_auth_by_device_id(device_id, val, type)
        expect(auth).not_to be_nil
        expect(auth.auth_type).to eq(type)
        expect(auth.auth_key).to eq(val)

        device = Device.find_by(device_id: device_id)
        expect(device.account_id).not_to be_nil

        account = Protocol.get_account_from_device(device)
        # we haven't verified, so the field in the account must not be the new value
        # This test will fail if we send a verification even if the user does not change the cred
        expect(account[type]).not_to eq(val)
      end
    end
  end
end

RSpec.shared_examples "the 2nd step of the verification process" do | device_id, type, test_value |
  it "puts #{type}: #{test_value} in account" do
    auth = get_auth_by_device_id(device_id, test_value, type)
    expect(auth).not_to be_nil
    verify_url = "https://eng.geopeers.com/api"
    uri = URI(verify_url)
    response = Net::HTTP.post_form(uri, 'method' => 'verify', 'cred' => auth.cred, 'device_id' => device_id)

    # The response contains a redirect_url with query_params
    # If the verification succeeded, then message_type => 'message_success'
    expect(response).not_to be_nil
    response_obj = JSON.parse(response.body)
    redirect_url = response_obj['redirect_url']
    expect(redirect_url).not_to be_nil
    query_params = parse_params(URI.parse(redirect_url).query)
    expect(query_params).not_to be_nil
    expect(query_params['message_type']).to eq('message_success')

    # was auth marked as used?
    auth_after = get_auth_by_device_id(device_id, test_value, type)
    expect(auth_after.auth_time).not_to be_nil
    
    account = Protocol.get_account_from_device_id(device_id)
    expect(account[type]).to eq(test_value)
  end
end

RSpec.describe Protocol, development: true do
  
  method = "register_device"
  device_id = "TEST_DEV_42"

  # clear the decks
  device_before = Device.find_by(device_id: device_id)
  clear_device (device_before) if device_before
  device_before = Device.new(device_id:  device_id,
                             user_agent: TEST_VALUES[:user_agent])
  device_before.save

  params = {}
  context "when new_account == 'yes'" do

    context "when no name/email/mobile" do
      it_should_behave_like "a bad set of parameters", 'register_device', device_id,
                            'yes', nil, nil, nil,
                            ERROR_MESSAGES[:email_or_mobile]
    end
    context "when name" do

      context "when bad email format" do
        it_should_behave_like "a bad set of parameters", 'register_device', device_id,
                              'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_bad_2], nil,
                              ERROR_MESSAGES[:email_bad]
      end

      context "when bad SMS format" do
        it_should_behave_like "a bad set of parameters", 'register_device', device_id,
                              'yes', TEST_VALUES[:name_1], nil, TEST_VALUES[:mobile_bad_1],
                              ERROR_MESSAGES[:mobile_bad]
      end

      context "when email" do
        it_should_behave_like "start the verification process", 'register_device', device_id,
                              'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_good_1], nil
      end

      context "when verify email" do
        it_should_behave_like "the 2nd step of the verification process", device_id, 'email', TEST_VALUES[:email_good_1]
      end

      # Tests:
      #   change cred without verifying previous cred
      #   change cred to same value (should not send verification)
      #   new_account = 'yes', both email and mobile



      context "when mobile" do
        it_should_behave_like "start the verification process", 'register_device', device_id,
                              'yes', TEST_VALUES[:name_1], nil, TEST_VALUES[:mobile_good_1]
      end

      context "when both mobile and email" do
        it_should_behave_like "start the verification process", 'register_device', device_id,
        'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_good_2], TEST_VALUES[:mobile_good_1]
        # email_good_1 has already been verified
        # make sure email_good_2 verification is sent
        auth = get_auth_by_device_id(device_id, TEST_VALUES[:email_good2], 'email')

      end

    end
  end

  # More Tests
  #   new_account = 'no', both email and mobile, different accounts
  #   new_account = 'no', both email and mobile, same accounts
  context "when new_account == 'no'" do
    context "when mobile && email" do
      context "when mobile id != email id" do
        xit "Error" do
          params['new_account'] = 'no'
          params['mobile'] = TEST_VALUES[:mobile_good_1]
          params['email'] = TEST_VALUES[:email_good_1]
          response = call_api(method, device_id, params)
        end
      end
      context "when mobile id == email id" do
        xit "verification is sent for both mobile and email" do
          params['new_account'] = 'no'
          params['mobile'] = TEST_VALUES[:mobile_good_1]
          params['email'] = TEST_VALUES[:email_good_1]
          response = call_api(method, device_id, params)
        end
      end
    end
    context "when mobile && ! email" do
      xit "verification is sent for mobile" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
      end
    end
    context "when ! mobile && email" do
      xit "verification is sent for email" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
      end
    end
    context "when ! mobile && ! email" do
      xit "error" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
      end
    end
  end
  context "with no account ID" do
    xit "has error" do
      params['new_account'] = 'no'
      params['mobile'] = TEST_VALUES[:mobile_good_1]
      params['email'] = TEST_VALUES[:email_good_1]
      response = call_api(method, device_id, params)
      expect(response[:message]).to match(/no account/i)
      # check for error
    end
  end
  context "with account ID" do
    # make sure the account exists
    account = Protocol.get_account_from_device (device_before)
    context "with no email or mobile" do
      xit "reports an error" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id,
                            {name: TEST_VALUES[:name_1]})
        expect(response[:message]).to match(/please supply/i)
      end
    end
    context "when name changes" do
      xit "changes the name in the account record" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        params['name'] = "Fred Friendly"
        response = call_api(method, device_id, params)
        # check message
        # check new name in account record
      end
    end
    context "when email changes" do
      xit "sends verification" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        to_email = TEST_VALUES[:email_bad_1]
        params['email'] = to_email
        response = call_api(method, device_id, params)
        expect(response[:message]).to match(/sent to #{to_email}/i)
        auth = get_auth_by_device_id(device_id, to_email, 'email')
        expect(auth.auth_time).to be nil
      end
    end
    context "when mobile changes" do
      xit "sends verification" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
        # check message
        # check verification cred
      end
    end
    context "when email changes again" do
      xit "sends verification, invalidates old verification" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
        # check message
        # check new verification cred
        # check old verification cred
      end
    end
    context "when first email change is verified" do
      xit "fails" do
        auth = get_auth_by_device_id(device_id, TEST_VALUES[:email_bad_1], 'email')
        expect(auth).not_to be nil
        expect(auth.auth_time).to be nil
        verify_url = "https://eng.geopeers.com/api?method=cred&cred="+auth.cred
        response = Net::HTTP.get(URI.parse(verify_url))
        # check failure
      end
    end
    context "when second email change is verified" do
      xit "updates email in account" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
      end
    end
    context "when mobile change is verified" do
      xit "updates mobile in account" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
        # check mobile in account
      end
    end
  end
  context "new_account = 'no'" do
    params['new_account'] = 'no'
    context "when name changes" do
      xit "name changes in account" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        params['name'] = 'new name'
        response = call_api(method, device_id, params)
      end
    end
    context "when email changes" do
      xit "verification is sent for email" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        params['name'] = 'new name'
        response = call_api(method, device_id, params)
        # check mobile in account
      end
    end
  end
  context "when good name/email, download_app == 1" do
    context "desktop" do
      xit "get verification, no download_app" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
      end
    end
    context "ios browser" do
      xit "get verification, redirect to iOS" do
        response = call_api(method, device_id, params)
      end
    end
    context "android browser" do
      xit "get verification, redirect to android" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api(method, device_id, params)
      end
    end
  end
end

RSpec.describe Protocol do
  method = "share_location"
  device_id = "TEST_DEV_42"

  context "with share location"
  xit "creates share" do
    response = call_api(method, device_id, params)
    # get cred
    # verify that share was created
  end
  context "when seer verifies share"
  xit "redeem is created" do
    # verify redeem is created
  end
end

RSpec.describe Protocol do
  method = "get_positions"
  device_id = "TEST_DEV_42"
  params = {}
  context "when get positions shared to device_id"
  xit "returns GPS coords shared to device_id" do
    response = call_api(method, device_id, params)
    # check coords for new_orleans and new_york
  end
  context ""
  xit "" do

  end
end

RSpec.describe Protocol do
  method = "get_registration"
  device_id = "TEST_DEV_42"
  context ""
  xit "" do
    response = call_api(method, device_id, params)
  end
end

RSpec.describe Protocol do
  context "start registration"
  xit "sends email" do
  end
end

RSpec.describe Protocol do
  context "verify registration"
  xit "creates account" do
  end
end
