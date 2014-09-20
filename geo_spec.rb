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
  name_1:         'Fred Friendly',
  name_2:         'Mary Smith',
  name_3:         'George Fortune',
  email_good_1:   'test@geopeers.com',
  email_good_2:   'scott@kaplans.com',
  email_good_3:   'scott@magtogo.com',
  email_bad_1:    'noone@magtogo.com',
  email_bad_2:    'NotAnAddress',
  mobile_good_1:  '4156521706',
  mobile_good_2:  '4155551212',
  mobile_valid_1: '1234567890',
  mobile_bad_1:   '123',
  user_agent:     'tire rim browser',
  device_id_1:    'TEST_DEV_42',
  device_id_2:    'TEST_DEV_43',
  device_id_3:    'TEST_DEV_44',
}

ERROR_MESSAGES = {
  no_email_or_mobile: 'Please supply your email or mobile number',
  no_name: 'Please supply your name',
  email_bad: "Email should be in the form 'fred@company.com'",
  mobile_bad: "The mobile number must be 10 digits",
  already_registered: " is already registered",
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
  # get the most recent, un-verified (auth_time IS NULL) auth
  # for a given account/type/key
  sql = "SELECT auths.* FROM auths, devices
         WHERE devices.device_id = '#{device_id}' AND
               devices.account_id = auths.account_id AND
               auths.auth_key = '#{key}' AND
               auths.auth_type = '#{type}' AND
               auths.auth_time IS NULL
         ORDER BY auths.issue_time DESC
         LIMIT 1
        "
  Auth.find_by_sql(sql).first
end

RSpec.describe Protocol, production: true do
  method = "config"
  device_id = TEST_VALUES[:device_id_1]

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
  device_id = TEST_VALUES[:device_id_1]

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

RSpec.shared_examples "bad parameters" do
  | method, device_id, new_account, name, email, mobile, error_message |
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

RSpec.shared_examples "start the verification process" do
  | method, device_id, new_account, name, email, mobile |
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
        # This test will fail if we send a verification even if the user does not change the value
        expect(account[type]).not_to eq(val)
      end
    end
  end
end

RSpec.shared_examples "the 2nd step of the verification process" do
  | device_id, type, test_value |
  it "puts #{type}: #{test_value} in account" do
    auth = get_auth_by_device_id(device_id, test_value, type)
    expect(auth).not_to be_nil
    verify_url = "https://eng.geopeers.com/api"
    uri = URI(verify_url)
    response = Net::HTTP.post_form(uri, 'method' => 'verify', 'cred' => auth.cred, 'device_id' => device_id)
    $LOG.debug response.body

    # The response contains a redirect_url with query_params
    # If the verification succeeded, then message_type => 'message_success'
    expect(response).not_to be_nil
    response_obj = JSON.parse(response.body)
    redirect_url = response_obj['redirect_url']
    expect(redirect_url).not_to be_nil
    query_params = parse_params(URI.parse(redirect_url).query)
    expect(query_params).not_to be_nil
    expect(query_params['message_type']).to eq('message_success')

    auth_after = Auth.find(auth.id)
    $LOG.debug auth_after
    expect(auth_after).not_to be_nil
    expect(auth_after.auth_time).not_to be_nil
    
    account = Protocol.get_account_from_device_id(device_id)
    expect(account).not_to be_nil
    expect(account[type]).to eq(test_value)
  end
end

RSpec.describe Protocol, development: true do

  # clear the decks
  clear_device_id (TEST_VALUES[:device_id_1])
  clear_device_id (TEST_VALUES[:device_id_2])
  clear_device_id (TEST_VALUES[:device_id_3])

  context "when creating a new account (new_account == 'yes')" do

    context "when no name/email/mobile" do
      it_should_behave_like "bad parameters",
      'register_device', TEST_VALUES[:device_id_1],
      'yes', nil, nil, nil,
      ERROR_MESSAGES[:no_name]
    end

    context "when bad email format" do
      it_should_behave_like "bad parameters",
      'register_device', TEST_VALUES[:device_id_1],
      'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_bad_2], nil,
      ERROR_MESSAGES[:email_bad]
    end

    context "when bad SMS format" do
      it_should_behave_like "bad parameters",
      'register_device', TEST_VALUES[:device_id_1],
      'yes', TEST_VALUES[:name_1], nil, TEST_VALUES[:mobile_bad_1],
      ERROR_MESSAGES[:mobile_bad]
    end

    context "when email" do
      it_should_behave_like "start the verification process",
      'register_device', TEST_VALUES[:device_id_1],
      'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_good_1], nil
    end

    context "when verify email" do
      it_should_behave_like "the 2nd step of the verification process",
      TEST_VALUES[:device_id_1], 'email', TEST_VALUES[:email_good_1]
    end

    context "when mobile, new device_id" do
      # This is from a different device_id
      it_should_behave_like "start the verification process",
      'register_device', TEST_VALUES[:device_id_2],
      'yes', TEST_VALUES[:name_2], nil, TEST_VALUES[:mobile_good_1], nil
    end

    context "when verify mobile for new device_id" do
      it_should_behave_like "the 2nd step of the verification process",
      TEST_VALUES[:device_id_2], 'mobile', TEST_VALUES[:mobile_good_1]
    end

    # When this context ends there are two accounts
    #   [ name: name_1, email:  email_good_1 ]  bound to device_id_1
    #   [ name: name_2, mobile: mobile_good_1 ] bound to device_id_2
  end

  context "when editing an account (new_account == 'no') associated with a single device" do
    context "when no name/email/mobile" do
      it_should_behave_like "bad parameters",
      'register_device', TEST_VALUES[:device_id_2],
      'no', nil, nil, nil,
      ERROR_MESSAGES[:email_or_mobile]
    end

    context "when bad email format" do
      it_should_behave_like "bad parameters",
      'register_device', TEST_VALUES[:device_id_2],
      'no', TEST_VALUES[:name_1], TEST_VALUES[:email_bad_2], nil,
      ERROR_MESSAGES[:email_bad]
    end

    context "when bad SMS format" do
      it_should_behave_like "bad parameters",
      'register_device', TEST_VALUES[:device_id_2],
      'no', TEST_VALUES[:name_1], nil, TEST_VALUES[:mobile_bad_1],
      ERROR_MESSAGES[:mobile_bad]
    end

    context "when change name" do
      it "changes name in account" do
        response = call_api('register_device', TEST_VALUES[:device_id_2],
                            { 'new_account' => 'no',
                              'name'        => TEST_VALUES[:name_3],
                            })
        account = Protocol.get_account_from_device_id(TEST_VALUES[:device_id_2])
        expect(account).not_to be_nil
        expect(account.name).to eq (TEST_VALUES[:name_3])
      end
    end

    context "when adding mobile" do
      it_should_behave_like "start the verification process",
      'register_device', TEST_VALUES[:device_id_1],
      'no', nil, nil, TEST_VALUES[:mobile_good_2], nil
    end

    context "when verifing new mobile value" do
      it_should_behave_like "the 2nd step of the verification process",
      TEST_VALUES[:device_id_1], 'mobile', TEST_VALUES[:mobile_good_2]
    end

    context "when parameter doesn't change" do
      it "doesn't do anything" do
        response = call_api('register_device', TEST_VALUES[:device_id_1],
                            { 'new_account' => 'no',
                              'mobile'      => TEST_VALUES[:mobile_good_2],
                            })
        auth = get_auth_by_device_id(TEST_VALUES[:device_id_1], TEST_VALUES[:mobile_good_2], 'mobile')
        expect(auth).to be_nil
      end
    end
    
    context "when email changes" do
      it_should_behave_like "start the verification process",
      'register_device', TEST_VALUES[:device_id_2],
      'no', nil, TEST_VALUES[:email_good_2], nil
    end

    context "when change email again before last change was verified" do
      it_should_behave_like "start the verification process",
      'register_device', TEST_VALUES[:device_id_2],
      'no', nil, TEST_VALUES[:email_good_3], nil do
      end
    end

    context "when trying to verify old value, fail" do
      it_should_behave_like "the 2nd step of the verification process",
      TEST_VALUES[:device_id_2], 'email', TEST_VALUES[:email_good_2]
      # TODO      # try to verify email_good_2 auth - should fail
    end

    context "when verify email_good_3" do
      it_should_behave_like "the 2nd step of the verification process",
      TEST_VALUES[:device_id_2], 'email', TEST_VALUES[:email_good_3]
    end

    # When this context ends there are two accounts
    #   device_id_1 => [ name: name_1,
    #                    email: email_good_2,
    #                    mobile: mobile_good_2 ]
    #   device_id_2 => [ name: name_3,
    #                    email: email_good_3,
    #                    mobile: mobile_good_1 ]
  end
end

RSpec.describe Protocol do
  # clear the decks
  clear_device_id (TEST_VALUES[:device_id_1])
  clear_device_id (TEST_VALUES[:device_id_2])
  clear_device_id (TEST_VALUES[:device_id_3])

  context "when devices in multiple accounts" do
    context "when add verified email to a new device" do
      it_should_behave_like "start the verification process",
      'register_device',  TEST_VALUES[:device_id_3],
      'no', nil, TEST_VALUES[:email_good_2], nil
    end

    context "when verify email for new device_id" do
      let(:account_before) { Protocol.get_account_from_device_id(TEST_VALUES[:device_id_3]) }
      it_should_behave_like "the 2nd step of the verification process",
      TEST_VALUES[:device_id_3], 'email', TEST_VALUES[:email_good_2] do
      end
      it "should merge the accounts" do
        account_deleted = Account.find(account_before.id)
        expect(account_deleted).to be_nil

        account_after = Protocol.get_account_from_device_id(TEST_VALUES[:device_id_3])
        expect(account_before.id).not_to be eq(account_after.id)
      end
    end
  end

  params = {}
  context "when download_app == 1" do
    context "desktop" do
      xit "get verification, no download_app" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api('register_device', TEST_VALUES[:device_id_1], params)
      end
    end
    context "ios browser" do
      xit "get verification, redirect to iOS" do
        response = call_api('register_device', TEST_VALUES[:device_id_1], params)
      end
    end
    context "android browser" do
      xit "get verification, redirect to android" do
        params['new_account'] = 'no'
        params['mobile'] = TEST_VALUES[:mobile_good_1]
        params['email'] = TEST_VALUES[:email_good_1]
        response = call_api('register_device', TEST_VALUES[:device_id_1], params)
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
  method = "cred"
  device_id = "TEST_DEV_42"
  context "when cred is redeemed"
  xit "creates a share" do
    response = call_api(method, device_id, params)
  end
end

RSpec.describe Protocol do
  method = "get_shares"
  device_id = "TEST_DEV_42"
  context "when cred is redeemed"
  xit "creates a share" do
    response = call_api(method, device_id, params)
  end
end

RSpec.describe Protocol do
  method = "device_id_bind"
  device_id = "TEST_DEV_42"
  context "when cred is redeemed"
  xit "creates a share" do
    response = call_api(method, device_id, params)
  end
end

