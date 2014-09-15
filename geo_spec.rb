#!/usr/bin/ruby
require './geo.rb'
require 'net/http'
require 'pry'

COORDS = {
  new_orleans:   {latitude: 29.9667, longitude:  -90.0500},
  san_francisco: {latitude: 37.7833, longitude: -122.4167},
  new_york:      {latitude: 40.7127, longitude:  -74.0059},
  us_center:     {latitude: 39.8282, longitude:  -98.5795},
}

TEST_VALUES = {
  mobile_1: '4156521706',
  email_1:  'scott@kaplans.com',
  name_1:   'Scott Kaplan',
  email_2:  'noone@magtogo.com',
  email_3:  'NotAnAddress',
  mobile_2: '123',
  user_agent: "tire rim browser",
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

def get_auth_by_device_id(device_id, key)
  sql = "SELECT auths.* FROM auths, devices
         WHERE devices.device_id = '#{device_id}' AND
               devices.account_id = auths.account_id AND
               auths.auth_key = '#{key}' AND
               auths.created_at < TIMESTAMPADD(SECOND, 5, NOW())
        "
  Auth.find_by_sql(sql).first
end

RSpec.shared_examples "email" do
  xit "" do
    
  end
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
  puts device_before.inspect
  context "when registration_edit == 0" do
    params['registration_edit'] = 0

    context "when new_account == 'yes'" do
      params['new_account'] = 'yes'

      context "when no name/email/mobile" do
        it "Error" do
          params['name'] = nil;
          params['email'] = nil;
          params['mobile'] = nil;
          response = call_api(method, device_id, params)
          expect(response[:message]).to match(//i)
        end
      end
      context "when name" do

        context "when bad email format" do
          it "Error" do
            params['name'] = TEST_VALUES[:name_1]
            params['email'] = TEST_VALUES[:email_3]
            params['mobile'] = nil;
            response = call_api(method, device_id, params)
            expect(response[:message]).to match(/Email should be in the form 'fred@company.com/i)
          end
        end

        context "when bad SMS format" do
          it "Error" do
            params['name'] = TEST_VALUES[:name_1]
            params['email'] = nil
            params['mobile'] = TEST_VALUES[:mobile_2]
            response = call_api(method, device_id, params)
            expect(response[:message]).to match(/The mobile number must be 10 digits/i)
          end
        end

        context "when email" do
          it "creates account, auth and device.account_id" do
            params['name'] = TEST_VALUES[:name_1]
            params['email'] = TEST_VALUES[:email_1]
            params['mobile'] = nil
            response = call_api(method, device_id, params)
            auth = get_auth_by_device_id(device_id, params['email'])
            expect(auth).not_to be_nil
          end
        end

        context "when mobile" do
          it "creates account, auth and device.account_id" do
            params['name'] = TEST_VALUES[:name_1]
            params['email'] = nil
            params['mobile'] = TEST_VALUES[:mobile_1]
            response = call_api(method, device_id, params)
            auth = get_auth_by_device_id(device_id, params['mobile'])
            expect(auth).not_to be_nil
          end
        end
      end
    end
    context "when new_account == 'no'" do
      params['new_account'] = 'no'
      context "when mobile && email" do
        params['mobile'] = TEST_VALUES[:mobile_1]
        params['email'] = TEST_VALUES[:email_1]
        context "when mobile id != email id" do
          xit "Error" do
          end
        end
        context "when mobile id == email id" do
          xit "verification is sent for both mobile and email" do
          end
        end
      end
      context "when mobile && ! email" do
        xit "verification is sent for mobile" do
          params['mobile'] = TEST_VALUES[:mobile_1]
          response = call_api(method, device_id, params)
        end
      end
      context "when ! mobile && email" do
        xit "verification is sent for email" do
          params['email'] = TEST_VALUES[:email_1]
          response = call_api(method, device_id, params)
        end
      end
      context "when ! mobile && ! email" do
        xit "error" do
          response = call_api(method, device_id, params)
        end
      end
    end
  end
  context "when registration_edit == 1" do
    params['registration_edit'] = 1
    context "with no account ID" do
      xit "has error" do
        response = call_api(method, device_id, params)
        expect(response[:message]).to match(/no account/i)
        # check for error
      end
    end
    context "with account ID" do
      # make sure the account exists
      account = Protocol.get_account_for_device (device_before)
      context "with no email or mobile" do
        xit "reports an error" do
          response = call_api(method, device_id,
                              {name: TEST_VALUES[:name_1]})
          expect(response[:message]).to match(/please supply/i)
        end
      end
      context "when name changes" do
        xit "changes the name in the account record" do
          params['name'] = "Fred Friendly"
          response = call_api(method, device_id, params)
          # check message
          # check new name in account record
        end
      end
      context "when email changes" do
        xit "sends verification" do
          to_email = TEST_VALUES[:email_2]
          params['email'] = to_email
          response = call_api(method, device_id, params)
          expect(response[:message]).to match(/sent to #{to_email}/i)
          auth = get_auth_by_device_id(device_id, to_email)
          expect(auth.auth_time).to be nil
        end
      end
      context "when mobile changes" do
        xit "sends verification" do
          params['mobile'] = "4156521706"
          response = call_api(method, device_id, params)
          # check message
          # check verification cred
        end
      end
      context "when email changes again" do
        xit "sends verification, invalidates old verification" do
          params['email'] = "scott@magtogo.com"
          response = call_api(method, device_id, params)
          # check message
          # check new verification cred
          # check old verification cred
        end
      end
      context "when first email change is verified" do
        xit "fails" do
          auth = get_auth_by_device_id(device_id, TEST_VALUES[:email_2])
          expect(auth).not_to be nil
          expect(auth.auth_time).to be nil
          verify_url = "https://eng.geopeers.com/api?method=cred&cred="+auth.cred
          response = Net::HTTP.get(URI.parse(verify_url))
          # check failure
        end
      end
      context "when second email change is verified" do
        xit "updates email in account" do
          response = call_api(method, device_id, params)
        end
      end
      context "when mobile change is verified" do
        xit "updates mobile in account" do
          response = call_api(method, device_id, params)
          # check mobile in account
        end
      end
    end
  end
  context "when registration_edit == 0" do
    params['registration_edit'] = 0
    context "new_account = 'no'" do
      params['new_account'] = 'no'
      context "when name changes" do
        xit "name changes in account" do
          params['name'] = 'new name'
          response = call_api(method, device_id, params)
        end
      end
      context "when email changes" do
        xit "verification is sent for email" do
          params['name'] = 'new name'
          response = call_api(method, device_id, params)
          # check mobile in account
        end
      end
    end
  end
  context "when good name/email, download_app == 1" do
    context "desktop" do
      xit "get verification, no download_app" do
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



