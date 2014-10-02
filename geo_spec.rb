#!/usr/bin/ruby

# This must be the first require
# require 'simplecov'
# SimpleCov.start

require './geo.rb'
require 'net/http'
require 'json'
require 'pry'
require 'mysql2'

COORDS = {
  new_orleans:   {latitude: 29.9667, longitude:  -90.0500},
  san_francisco: {latitude: 37.7833, longitude: -122.4167},
  new_york:      {latitude: 40.7127, longitude:  -74.0059},
  us_center:     {latitude: 39.8282, longitude:  -98.5795},
}

TEST_VALUES = {
  name_1:          'Device ID1',
  name_2:          'Device ID2',
  name_3:          'Device ID3',
  email_good_1:    'test@geopeers.com',
  email_good_2:    'scott@kaplans.com',
  email_good_3:    'scott@magtogo.com',
  email_bad_1:     'noone@magtogo.com',
  email_bad_2:     'NotAnAddress',
  mobile_good_1:   '4156521706',
  mobile_good_2:   '4155551212',
  mobile_valid_1:  '1234567890',
  mobile_bad_1:    '123',
  user_agent_1:    'tire rim browser',
  user_agent_2:    'Safari iPhone browser',
  user_agent_3:    'Android browser',
  device_id_1:     'TEST_DEV_42',
  device_id_2:     'TEST_DEV_43',
  device_id_3:     'TEST_DEV_44',
  device_id_bad_4: 'TEST_DEV_45',
}

UA_MAP = {}
UA_MAP[TEST_VALUES[:device_id_1]] = TEST_VALUES[:user_agent_1]
UA_MAP[TEST_VALUES[:device_id_2]] = TEST_VALUES[:user_agent_2]
UA_MAP[TEST_VALUES[:device_id_3]] = TEST_VALUES[:user_agent_3]

ERROR_MESSAGES = {
  no_email_or_mobile: "Please supply your email or mobile number",
  no_name:            "Please supply your name",
  email_bad:          "Email should be in the form 'fred@company.com'",
  mobile_bad:         "The mobile number must be 10 digits",
  already_registered: " is already registered",
  no_native_app:      "There is no native app available for your device",
}

#
# Utilities
#

def call_api(method, device_id, extra_parms=nil)
  procname = "process_request_#{method}"
  device = Device.find_by(device_id: device_id)

  # Giant Hack
  #   We can't call ProtocolEngine.before_proc()
  #   just call create_device to preconfigure what before_proc() should do with an HTTP call
  Protocol.create_device(device_id, UA_MAP[device_id]) unless device

  params = {
    'method'     => method,
    'device_id'  => device_id,
  }
  params.merge!(extra_parms) if extra_parms
  $LOG.debug params
  response = Protocol.send(procname, params)
  $LOG.debug response
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

def get_email_shares(device_id, email)
  Share.where("device_id=? AND share_to=? AND share_via='email'",
              device_id, email)
    .order(created_at: :desc)
end

def get_email_share(device_id, email)
  # returns latest share for device_id/email
  share = get_email_shares(device_id, email).first
  $LOG.debug share
  share
end

def clear_test_shares()
  [:device_id_1, :device_id_2, :device_id_3].each do
    | seen_device_id |
    get_email_shares(TEST_VALUES[seen_device_id], TEST_VALUES[:email_good_2]).each do
      | share |
      share.destroy
    end
  end
end

def clear_devices
  clear_device_id (TEST_VALUES[:device_id_1])
  clear_device_id (TEST_VALUES[:device_id_2])
  clear_device_id (TEST_VALUES[:device_id_3])
  Account.destroy_all(:name => TEST_VALUES[:name_1])
  Account.destroy_all(:name => TEST_VALUES[:name_2])
  Account.destroy_all(:name => TEST_VALUES[:name_3])
end

def setup_device(device_id, name, user_agent)
  call_api('register_device', device_id,
           { 'new_account' => 'yes',
             'name'        => name,
             'user_agent'  => user_agent,
           })
end

def setup_devices()
  setup_device(TEST_VALUES[:device_id_1], TEST_VALUES[:name_1], TEST_VALUES[:user_agent_1])
  setup_device(TEST_VALUES[:device_id_2], TEST_VALUES[:name_2], TEST_VALUES[:user_agent_2])
  setup_device(TEST_VALUES[:device_id_3], TEST_VALUES[:name_3], TEST_VALUES[:user_agent_3])
end

def reset_devices()
  clear_devices()
  setup_devices()
end

RSpec.shared_examples "verification process - phase 1" do
  | device_id, new_account, name, email, mobile |
  it "creates account, auth and device.account_id" do
    response = call_api('register_device', device_id,
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

RSpec.shared_examples "verification process - phase 2" do
  | device_id, type, test_value |
  it "put #{type}: #{test_value} in account" do
    auth = get_auth_by_device_id(device_id, test_value, type)
    expect(auth).not_to be_nil
    verify_url = "https://eng.geopeers.com/api"
    uri = URI(verify_url)
    response = Net::HTTP.post_form(uri, 'method' => 'verify', 'cred' => auth.cred, 'device_id' => device_id)
    if response.body.match /^<!DOCTYPE html>/
      log_error (response.body)
    else
      $LOG.debug response.body
    end

    # The response contains a redirect_url with query_params
    # If the verification succeeded, then message_type => 'message_success'
    expect(response).not_to be_nil
    response_obj = JSON.parse(response.body)
    redirect_url = response_obj['redirect_url']
    expect(redirect_url).not_to be_nil
    query_params = parse_params(URI.parse(redirect_url).query)
    expect(query_params).not_to be_nil
    expect(query_params['message_type']).not_to eq('message_error')

    auth_after = Auth.find(auth.id)
    expect(auth_after).not_to be_nil
    expect(auth_after.auth_time).not_to be_nil
    
    account = Protocol.get_account_from_device_id(device_id)
    expect(account).not_to be_nil
    expect(account[type]).to eq(test_value)
  end
end

#
# CONFIG API
#

RSpec.describe Protocol, production: true do
  describe "config" do
    before(:each) do
      reset_devices()
    end
    context "when no email/mobile" do
      it "merges account for device_id_2 into account for device_id_1" do
        device_1_before = Device.find_by(device_id: TEST_VALUES[:device_id_1])
        account_1_before = Protocol.get_account_from_device (device_1_before)
        device_2_before = Device.find_by(device_id: TEST_VALUES[:device_id_2])
        account_2_before = Protocol.get_account_from_device (device_2_before)

        # config test parms
        # end

        response = call_api("config", TEST_VALUES[:device_id_2],
                            { 'user_agent'       => TEST_VALUES[:user_agent_1],
                              'native_device_id' => TEST_VALUES[:device_id_1],
                            })
        $LOG.debug response
        expect(response[:redirect_url]).not_to be_nil

        device_1_after = Device.find_by(device_id: TEST_VALUES[:device_id_1])
        account_1_after = Protocol.get_account_from_device (device_1_after)
        device_2_after = Device.find_by(device_id: TEST_VALUES[:device_id_2])
        # This should be the same account id as before,
        # not the account that device_id_2 now points to
        account_2_after = Account.find(account_2_before.id)

        # config expects
        expect(account_1_after.name).to eq TEST_VALUES[:name_1]
        expect(account_1_after.email).to be_nil
        expect(account_1_after.mobile).to be_nil
        # end

        expect(account_1_after.id).to eq account_1_before.id
        expect(device_2_after.account_id.to_i).to eq account_1_after.id
        expect(device_1_after.account_id.to_i).to eq account_1_after.id

        account_2_auth_count = Auth.where("auth_time IS NULL AND account_id = ?", account_2_after.id)
          .count
        expect(account_2_auth_count).to eq 0

        expect(account_1_after[:active]).to eq 1
        $LOG.debug account_2_after
        expect(account_2_after[:active]).to be_nil
      end
    end
    context "when name_1/email in one account and name_2/mobile in other account" do
      it "merges account for device_id_2 into account for device_id_1" do
        device_1_before = Device.find_by(device_id: TEST_VALUES[:device_id_1])
        account_1_before = Protocol.get_account_from_device (device_1_before)
        device_2_before = Device.find_by(device_id: TEST_VALUES[:device_id_2])
        account_2_before = Protocol.get_account_from_device (device_2_before)

        # config test parms
        account_1_before.email = TEST_VALUES[:email_good_1]
        account_1_before.save
        account_2_before.mobile = TEST_VALUES[:mobile_good_1]
        account_2_before.save
        # end
        
        response = call_api("config", TEST_VALUES[:device_id_2],
                            { 'user_agent'       => TEST_VALUES[:user_agent_1],
                              'native_device_id' => TEST_VALUES[:device_id_1],
                            })
        $LOG.debug response
        expect(response[:redirect_url]).not_to be_nil

        device_1_after = Device.find_by(device_id: TEST_VALUES[:device_id_1])
        account_1_after = Protocol.get_account_from_device (device_1_after)
        device_2_after = Device.find_by(device_id: TEST_VALUES[:device_id_2])
        # This should be the same account id as before,
        # not the account that device_id_2 now points to
        account_2_after = Account.find(account_2_before.id)

        # config expects
        expect(account_1_after.name).to eq TEST_VALUES[:name_1]
        expect(account_1_after.email).to eq TEST_VALUES[:email_good_1]
        expect(account_1_after.mobile).to eq TEST_VALUES[:mobile_good_1]
        # end

        expect(account_1_after.id).to eq account_1_before.id
        expect(device_2_after.account_id.to_i).to eq account_1_after.id
        expect(device_1_after.account_id.to_i).to eq account_1_after.id

        account_2_auth_count = Auth.where("auth_time IS NULL AND account_id = ?", account_2_after.id)
          .count
        expect(account_2_auth_count).to eq 0

        expect(account_1_after[:active]).to eq 1
        $LOG.debug account_2_after
        expect(account_2_after[:active]).to be_nil
      end
    end
    context "when name_1/email_1/mobile_1 in one account and name_2/email_2/mobile_2 in other account" do
      it "merges account for device_id_2 into account for device_id_1" do
        device_1_before = Device.find_by(device_id: TEST_VALUES[:device_id_1])
        account_1_before = Protocol.get_account_from_device (device_1_before)
        device_2_before = Device.find_by(device_id: TEST_VALUES[:device_id_2])
        account_2_before = Protocol.get_account_from_device (device_2_before)

        # config test parms
        account_1_before.email = TEST_VALUES[:email_good_1]
        account_1_before.mobile = TEST_VALUES[:mobile_good_1]
        account_1_before.save
        account_2_before.email = TEST_VALUES[:email_good_2]
        account_2_before.mobile = TEST_VALUES[:mobile_good_2]
        account_2_before.save
        # end
        
        response = call_api("config", TEST_VALUES[:device_id_2],
                            { 'user_agent'       => TEST_VALUES[:user_agent_1],
                              'native_device_id' => TEST_VALUES[:device_id_1],
                            })
        $LOG.debug response
        expect(response[:redirect_url]).not_to be_nil

        device_1_after = Device.find_by(device_id: TEST_VALUES[:device_id_1])
        account_1_after = Protocol.get_account_from_device (device_1_after)
        device_2_after = Device.find_by(device_id: TEST_VALUES[:device_id_2])
        # This should be the same account id as before,
        # not the account that device_id_2 now points to
        account_2_after = Account.find(account_2_before.id)

        # config expects
        expect(account_1_after.name).to eq TEST_VALUES[:name_1]
        expect(account_1_after.email).to eq TEST_VALUES[:email_good_1]
        expect(account_1_after.mobile).to eq TEST_VALUES[:mobile_good_1]
        # end

        expect(account_1_after.id).to eq account_1_before.id
        expect(device_2_after.account_id.to_i).to eq account_1_after.id
        expect(device_1_after.account_id.to_i).to eq account_1_after.id

        account_2_auth_count = Auth.where("auth_time IS NULL AND account_id = ?", account_2_after.id)
          .count
        expect(account_2_auth_count).to eq 0

        expect(account_1_after[:active]).to eq 1
        $LOG.debug account_2_after
        expect(account_2_after[:active]).to be_nil
      end
    end
    context "when sent old version" do
      it "gets JS" do
        response = call_api("config", TEST_VALUES[:device_id_1],
                            { 'user_agent' => TEST_VALUES[:user_agent_1],
                              'version'    => 0.9,
                            })

        expect(response[:js]).not_to be_nil
      end
    end
  end
end

#
# REGISTER_DEVICE API
#

RSpec.shared_examples "bad register parameters" do
  | device_id, new_account, name, email, mobile, error_message |
  it "get error" do
    response = call_api('register_device', device_id,
                        { 'new_account' => new_account,
                          'name'        => name,
                          'email'       => email,
                          'mobile'      => mobile,
                        })
    expect(response[:message]).to match(/#{error_message}/i)
  end
end

RSpec.describe Protocol, production: true do
  describe "register_device" do
    before(:all) do
      # clear the decks
      clear_device_id (TEST_VALUES[:device_id_1])
      clear_device_id (TEST_VALUES[:device_id_2])
      clear_device_id (TEST_VALUES[:device_id_3])
    end

    context "when creating a new account (new_account == 'yes')" do

      context "when no name/email/mobile" do
        it_should_behave_like "bad register parameters",
        TEST_VALUES[:device_id_1],
        'yes', nil, nil, nil,
        ERROR_MESSAGES[:no_name]
      end

      context "when bad email format" do
        it_should_behave_like "bad register parameters",
        TEST_VALUES[:device_id_1],
        'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_bad_2], nil,
        ERROR_MESSAGES[:email_bad]
      end

      context "when bad SMS format" do
        it_should_behave_like "bad register parameters",
        TEST_VALUES[:device_id_1],
        'yes', TEST_VALUES[:name_1], nil, TEST_VALUES[:mobile_bad_1],
        ERROR_MESSAGES[:mobile_bad]
      end

      context "when email" do
        it_should_behave_like "verification process - phase 1",
        TEST_VALUES[:device_id_1],
        'yes', TEST_VALUES[:name_1], TEST_VALUES[:email_good_1], nil
      end

      context "when verify email" do
        it_should_behave_like "verification process - phase 2",
        TEST_VALUES[:device_id_1], 'email', TEST_VALUES[:email_good_1]
      end

      context "when mobile, new device_id" do
        # This is from a different device_id
        it_should_behave_like "verification process - phase 1",
        TEST_VALUES[:device_id_2],
        'yes', TEST_VALUES[:name_2], nil, TEST_VALUES[:mobile_good_1], nil
      end

      context "when verify mobile for new device_id" do
        it_should_behave_like "verification process - phase 2",
        TEST_VALUES[:device_id_2], 'mobile', TEST_VALUES[:mobile_good_1]
      end

      # When this context ends there are two accounts
      #   [ name: name_1, email:  email_good_1 ]  bound to device_id_1
      #   [ name: name_2, mobile: mobile_good_1 ] bound to device_id_2
    end

    context "when editing an account (new_account == 'no') associated with a single device" do
      context "when no name/email/mobile" do
        it_should_behave_like "bad register parameters",
        TEST_VALUES[:device_id_2],
        'no', nil, nil, nil,
        ERROR_MESSAGES[:email_or_mobile]
      end

      context "when bad email format" do
        it_should_behave_like "bad register parameters",
        TEST_VALUES[:device_id_2],
        'no', TEST_VALUES[:name_1], TEST_VALUES[:email_bad_2], nil,
        ERROR_MESSAGES[:email_bad]
      end

      context "when bad SMS format" do
        it_should_behave_like "bad register parameters",
        TEST_VALUES[:device_id_2],
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
        it_should_behave_like "verification process - phase 1",
        TEST_VALUES[:device_id_1],
        'no', nil, nil, TEST_VALUES[:mobile_good_2], nil
      end

      context "when verifing new mobile value" do
        it_should_behave_like "verification process - phase 2",
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
        it_should_behave_like "verification process - phase 1",
        TEST_VALUES[:device_id_2],
        'no', nil, TEST_VALUES[:email_good_2], nil
      end

      context "when change email again before last change was verified" do
        it_should_behave_like "verification process - phase 1",
        TEST_VALUES[:device_id_2],
        'no', nil, TEST_VALUES[:email_good_3], nil do
        end
      end

      context "when trying to verify old value, fail" do
        it_should_behave_like "verification process - phase 2",
        TEST_VALUES[:device_id_2], 'email', TEST_VALUES[:email_good_2]
        # TODO      # try to verify email_good_2 auth - should fail
      end

      context "when verify email_good_3" do
        it_should_behave_like "verification process - phase 2",
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
end

RSpec.describe Protocol, production: true do
  describe "register_device - multiple accounts" do
    before(:all) do
      # clear the decks
      setup_devices()
    end

    context "when multiple devices use the same verification value" do
      # put verification in the air for device_id_1
      it_should_behave_like "verification process - phase 1",
      TEST_VALUES[:device_id_1],
      'no', TEST_VALUES[:name_1], TEST_VALUES[:email_good_2], nil do
      end
      let!(:account_device_id_1_before) { Protocol.get_account_from_device_id(TEST_VALUES[:device_id_1]) }

      # put verification in the air for device_id_2
      it_should_behave_like "verification process - phase 1",
      TEST_VALUES[:device_id_2],
      'no', TEST_VALUES[:name_2], TEST_VALUES[:email_good_2], nil do
      end
      let!(:account_device_id_2_before) { Protocol.get_account_from_device_id(TEST_VALUES[:device_id_2]) }

      # verify device_id_1
      it_should_behave_like "verification process - phase 2",
      TEST_VALUES[:device_id_1], 'email', TEST_VALUES[:email_good_2] do
      end
      it "should leave the account unchanged" do
        account_device_id_1_after = Protocol.get_account_from_device_id(TEST_VALUES[:device_id_1])
        expect(account_device_id_1_before.id).to eq account_device_id_1_after.id
      end
      
      # verify device_id_2
      it_should_behave_like "verification process - phase 2",
      TEST_VALUES[:device_id_2], 'email', TEST_VALUES[:email_good_2] do
      end
      it "should merge the accounts" do
        account_device_id_2_after = Protocol.get_account_from_device_id(TEST_VALUES[:device_id_2])
        expect(account_device_id_2_before.id).not_to be eq account_device_id_2_after.id
      end
    end
  end
end

RSpec.describe Protocol, production: true do
  describe "register_device - download_app" do
    before(:all) do
      clear_device_id (TEST_VALUES[:device_id_1])
      clear_device_id (TEST_VALUES[:device_id_2])
      clear_device_id (TEST_VALUES[:device_id_3])
      setup_devices()
    end
    context "desktop" do
      it "get verification, no download_app" do
        response = call_api('register_device', TEST_VALUES[:device_id_1],
                            { 'new_account'  => 'no',
                              'mobile'       => TEST_VALUES[:mobile_good_1],
                              'email'        => TEST_VALUES[:email_good_1],
                              'download_app' => 1,
                            })
        expect(response[:message]).to match(/#{TEST_VALUES[:no_native_app]}/i)
      end
    end
    context "ios browser" do
      it "get verification, redirect to iOS" do
        response = call_api('register_device', TEST_VALUES[:device_id_2],
                            { 'new_account' => 'no',
                              'mobile'      => TEST_VALUES[:mobile_good_1],
                              'email'       => TEST_VALUES[:email_good_1],
                              'download_app' => 1,
                            })
        expect(response['redirect_url']).to match(/#{DOWNLOAD_URLS[:ios]}/i)
      end
    end
    context "android browser" do
      it "get verification, redirect to android" do
        response = call_api('register_device', TEST_VALUES[:device_id_3],
                            { 'new_account' => 'no',
                              'mobile'      => TEST_VALUES[:mobile_good_1],
                              'email'       => TEST_VALUES[:email_good_1],
                              'download_app' => 1,
                            })
        expect(response['redirect_url']).to match(/#{DOWNLOAD_URLS[:android]}/i)
      end
    end
  end
end

#
# SEND_POSITION API
#

def create_position(device_id, coords)
  call_api("send_position", device_id,
           { 'gps_longitude' => coords[:longitude],
             'gps_latitude'  => coords[:latitude],
           })
end

RSpec.describe Protocol, production: true do
  describe "send_position" do
    def look_for_sighting (device_id, coords)
      sql = "SELECT * FROM sightings
             WHERE device_id = '#{device_id}' AND
                   gps_longitude = #{coords[:longitude]} AND
                   gps_latitude = #{coords[:latitude]} AND
                   created_at < TIMESTAMPADD(SECOND, 5, NOW())
            "
      Sighting.find_by_sql(sql).first
    end

    context "with syntax 1"
    it "creates sighting record" do
      response = create_position(TEST_VALUES[:device_id_1], COORDS[:new_orleans]) 
      expect(response[:status]).to eql("OK")

      sighting = look_for_sighting(TEST_VALUES[:device_id_1], COORDS[:new_orleans]) 
      expect(sighting).not_to be nil
    end

    context "with syntax 2"
    it "creates sighting record" do
      response = call_api("send_position", TEST_VALUES[:device_id_1],
                          { 'location'      => {
                              'longitude' => COORDS[:new_york][:longitude],
                              'latitude'  => COORDS[:new_york][:latitude],
                            }
                          })

      expect(response[:status]).to eql("OK")

      sighting = look_for_sighting(TEST_VALUES[:device_id_1], COORDS[:new_york])
      expect(sighting).not_to be nil
    end
  end
end

#
# SHARE_LOCATION API
#

RSpec.describe Protocol, production: true do
  describe "share_location" do
    before(:all) do
      clear_shares(TEST_VALUES[:device_id_1])
    end

    context "with share location" do
      it "creates share" do
        params = {
          'share_via' => 'email',
          'share_to' => TEST_VALUES[:email_good_2],
          'share_duration_unit' => 'manual',
          'num_uses' => 1
        }
        response = call_api('share_location', TEST_VALUES[:device_id_1], params)
        # We would really like the cred that was created
        # and look up the share with the unique cred
        # But it would defeat the entire process to send the cred in the response
        # instead get the most recent share for this device_id/share_to that was created in the last 5 sec
        share = get_email_share(TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2])
        expect(share).not_to be_nil
        expect(Time.now.to_i - 5).to be < share.created_at.to_i
      end
    end
  end
end

#
# REDEEM API
#

def call_redeem(seer_device_id, cred)
  response = call_api('redeem', seer_device_id, {cred: cred})
  redeem = get_redeem(seer_device_id, cred)
  redeem
end

def call_redeem_by_values(seer_device_id, seen_device_id, email)
  share = get_email_share(seen_device_id, email)
  call_redeem(seer_device_id, share.share_cred)
end

def create_and_redeem_share(seer_device_id, seen_device_id, share_duration_unit, share_duration_number=nil)
  email = TEST_VALUES[:email_good_2]
  response = create_share(seen_device_id,
                          { 'share_via'             => 'email',
                            'share_to'              => email,
                            'share_duration_unit'   => share_duration_unit,
                            'share_duration_number' => share_duration_number,
                            'num_uses'              => 1,
                          })
  call_redeem_by_values(seer_device_id, seen_device_id, email)
end

def get_redeem_by_seen(seer_device_id, seen_device_id)
  quoted_seer_device_id = Mysql2::Client.escape(seer_device_id)
  quoted_seen_device_id = Mysql2::Client.escape(seen_device_id)
  sql = "SELECT redeems.* FROM redeems, shares
         WHERE shares.device_id = '#{quoted_seen_device_id}' AND
               shares.id = redeems.share_id AND
               redeems.device_id = '#{quoted_seer_device_id}'"
  redeem = Redeem.find_by_sql(sql).first
  redeem
end

def get_redeem_by_share(share_id, device_id)
  Redeem.where("share_id=? AND device_id=?",share_id, device_id).first
end

def get_redeem(device_id, cred)
  quoted_device_id = Mysql2::Client.escape(device_id)
  quoted_cred = Mysql2::Client.escape(cred)
  sql = "SELECT redeems.* FROM redeems, shares
         WHERE shares.share_cred = '#{quoted_cred}' AND
               shares.id = redeems.share_id AND
               redeems.device_id = '#{quoted_device_id}'"
  redeem = Redeem.find_by_sql(sql).first
  redeem
end

RSpec.shared_examples "no redeem" do
  | seer_device_id, seen_device_id, email |
  it "checks for no redeem" do
    share = get_email_share(seen_device_id, email)
    expect(share).not_to be_nil
    redeem = get_redeem_by_share(share.id, seer_device_id)
    expect(redeem).to be_nil
  end
end

RSpec.describe Protocol, production: true do
  describe "redeem" do
    before(:all) do
      [:device_id_1, :device_id_2, :device_id_3].each do
        | seen_device_id |
        get_email_shares(TEST_VALUES[seen_device_id], TEST_VALUES[:email_good_2]).each do
          | share |
          share.destroy
        end
      end

      # create a share to setup the testing
      params = {
        'share_via' => 'email',
        'share_to' => TEST_VALUES[:email_good_2],
        'share_duration_unit' => 'manual',
        'num_uses' => 1
      }
      response = call_api('share_location', TEST_VALUES[:device_id_1], params)
    end

    context "when redeem bad share" do
      it "get error" do
        response = call_api('redeem', TEST_VALUES[:device_id_2], {cred: 'NOT_A_CRED'})
        expect(response).not_to be_nil
        redirect_url = response[:redirect_url]
        expect(redirect_url).not_to be_nil
        query_params = parse_params(URI.parse(redirect_url).query)
        expect(query_params).not_to be_nil
        expect(query_params['alert']).not_to be_nil
      end
    end
    context "when redeem does not exist for seer device_id initially" do
      it_should_behave_like "no redeem",
      TEST_VALUES[:device_id_2], TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2] do
      end
    end
    context "when creating redeem" do
      it "creates redeem and seer (device_id_2) can now see device_id_1" do
        redeem = call_redeem_by_values(TEST_VALUES[:device_id_2], TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2])
        expect(redeem).not_to be_nil
        expect(Time.now.to_i - 5).to be < redeem.created_at.to_i
        share = Share.find(redeem.share_id)
        expect(share.device_id).to eq TEST_VALUES[:device_id_1]
      end
    end
    context "when redeem does not exist for seer device_id initially" do
      it_should_behave_like "no redeem",
      TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2] do
      end
    end
    context "when num_uses is exceeded" do
      it "get error" do
        redeem = call_redeem_by_values(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2])
        expect(redeem).to be_nil
      end
    end
    
    context "when the seer already has an infinite share" do
      it "makes the redeem time infinite" do
        share = get_email_share(TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2])
        redeem = get_redeem_by_share(share.id, TEST_VALUES[:device_id_2])
        response = create_share(TEST_VALUES[:device_id_1],
                                { 'share_via'             => 'email',
                                  'share_to'              => TEST_VALUES[:email_good_2],
                                  'share_duration_unit'   => 'hour',
                                  'share_duration_number' => '1',
                                  'num_uses'              => 1,
                                })
        call_redeem_by_values(TEST_VALUES[:device_id_2], TEST_VALUES[:device_id_1], TEST_VALUES[:email_good_2])
        redeem_after = get_redeem_by_seen(TEST_VALUES[:device_id_2], TEST_VALUES[:device_id_1])
        expect(redeem_after).not_to be_nil
        expect(redeem_after.id).to eq redeem.id
      end
    end

    context "when the first seer redeems a share that is shorter duration than the first share" do
      it "doesn't change the redeem" do
        # setup initial share
        # don't do this in before clause or earlier tests get upset
        create_and_redeem_share(TEST_VALUES[:device_id_3],
                                TEST_VALUES[:device_id_1],
                                'hour', '5')

        redeem_before = get_redeem_by_seen(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1])
        create_and_redeem_share(TEST_VALUES[:device_id_3],
                                TEST_VALUES[:device_id_1],
                                'hour', '2')
        redeem_after = get_redeem_by_seen(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1])
        expect(redeem_after).not_to be_nil
        expect(redeem_after.share_id).to eq redeem_before.share_id
      end
    end

    context "when the seer redeems a share that is longer duration than the first share" do
      it "uses redeem with longer expiration" do
        redeem_before = get_redeem_by_seen(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1])
        create_and_redeem_share(TEST_VALUES[:device_id_3],
                                TEST_VALUES[:device_id_1],
                                'hour', '10')
        redeem_after = get_redeem_by_seen(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1])
        expect(redeem_after).not_to be_nil
        expect(redeem_after.share_id).not_to eq redeem_before.share_id
      end
    end
    context "when the first seer redeems a share that is infinite" do
      it "makes the redeem time infinite" do
        redeem_before = get_redeem_by_seen(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1])
        create_and_redeem_share(TEST_VALUES[:device_id_3],
                                TEST_VALUES[:device_id_1],
                                'manual')
        redeem_after = get_redeem_by_seen(TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1])
        expect(redeem_after).not_to be_nil
        expect(redeem_after.share_id).not_to eq redeem_before.share_id
        share_after = Share.find(redeem_after.share_id)
        expect(share_after.expire_time).to be_nil
      end
    end
  end
end

RSpec.describe Protocol, production: true do
  describe "get_shares" do
    before(:all) do
      clear_test_shares()
      setup_devices()
    end
    context "when the user doesn't have any shares"
    it "return the empty list" do
      response = call_api("get_shares", TEST_VALUES[:device_id_1])
      expect(response).not_to be_nil
      expect(response['shares']).to be_empty
    end
    context "when the user does have any shares"
    it "returns shares" do
      create_and_redeem_share(TEST_VALUES[:device_id_2],
                              TEST_VALUES[:device_id_1],
                              'manual')
      response = call_api("get_shares", TEST_VALUES[:device_id_2])
      expect(response).not_to be_nil
      expect(response['shares']).not_to be_empty
    end
  end
end

RSpec.describe Protocol, production: true do
  describe "get_registration" do
    before(:all) do
      setup_devices()
    end
    context "when good device_id is sent"
    it "returns account" do
      response = call_api("get_registration", TEST_VALUES[:device_id_1])
      expect(response).not_to be_nil
    end
  end
end

#
# GET_POSITIONS API
#

def get_sighting(sightings, seen_device_id, coords)
  sightings.each do
    |sighting|
    if  sighting['gps_longitude'] == coords[:longitude] &&
        sighting['gps_latitude'] == coords[:latitude] &&
        sighting['device_id'] == seen_device_id
      return sighting
    end
  end
  return
end

RSpec.shared_examples "no sighting" do
  | seer_device_id, seen_device_id, coords |
  it "does not get a sighting for coords" do
    response = call_api("get_positions", seer_device_id)
    expect(response).not_to be_nil
    expect(response["sightings"]).not_to be_nil
    sighting = get_sighting(response["sightings"], seen_device_id, coords)
    expect(sighting).to be_nil
  end
end

RSpec.shared_examples "good sighting" do
  | seer_device_id, seen_device_id, coords |
  it "gets a sighting for coords" do
    response = call_api("get_positions", seer_device_id)
    expect(response).not_to be_nil
    expect(response["sightings"]).not_to be_nil
    sighting = get_sighting(response["sightings"], seen_device_id, coords)
    expect(sighting).not_to be_nil
  end
end

RSpec.describe Protocol, production: true do
  describe "get_positions" do

    before(:all) do
      setup_devices()
      clear_test_shares()

      # create sightings to test
      create_position(TEST_VALUES[:device_id_1], COORDS[:new_orleans])

      # create share/redeem to test
      # device_id_3 (seer) to see device_id_1 (seen)
      create_and_redeem_share(TEST_VALUES[:device_id_3],
                              TEST_VALUES[:device_id_1],
                              'manual',
                              )
    end
    context "when single sighting" do
      it_should_behave_like "good sighting",
      TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1], COORDS[:new_orleans] do
      end
    end
    context "when multiple sightings for a seen" do
      it "waits to make sure next sighting is later (different) timestamp" do
        sleep(1)
        create_position(TEST_VALUES[:device_id_1], COORDS[:us_center]) 
      end
      it_should_behave_like "good sighting",
      TEST_VALUES[:device_id_3], TEST_VALUES[:device_id_1], COORDS[:us_center] do
      end
    end
    context "when share expires" do
      before(:all) do
        create_position(TEST_VALUES[:device_id_3], COORDS[:new_york])
        
        # seer device_id_2, seen device_id_3
        create_and_redeem_share(TEST_VALUES[:device_id_2],
                                TEST_VALUES[:device_id_3],
                                'second',
                                '3',
                                )
      end

      context "before share expires" do
        it_should_behave_like "good sighting",
        TEST_VALUES[:device_id_2], TEST_VALUES[:device_id_3], COORDS[:new_york] do
        end
      end

      context "let share expires" do
        it "waits for share to expire" do
          sleep(4)
        end
      end

      context "after share expires" do
        it_should_behave_like "no sighting",
        TEST_VALUES[:device_id_2], TEST_VALUES[:device_id_3], COORDS[:new_york] do
        end
      end
    end
  end
end

