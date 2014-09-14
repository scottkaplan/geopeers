#!/usr/bin/ruby
require './geo.rb'

COORDS = {
  new_orleans:   {latitude: 29.9667, longitude:  -90.0500},
  san_francisco: {latitude: 37.7833, longitude: -122.4167},
  new_york:      {latitude: 40.7127, longitude:  -74.0059},
  us_center:     {latitude: 39.8282, longitude:  -98.5795},
};

def call_api(method, device_id, extra_parms)
  procname = "process_request_#{method}"
  params = {
    'method'     => method,
    'device_id'  => device_id,
  }
  params.merge!(extra_parms)
  Protocol.send(procname, params)
end

RSpec.shared_examples "email" do
  xit "" do
    
  end
end

RSpec.describe Protocol, production: true do
  method = "config"
  device_id = "TEST_DEV_42"

  user_agent = "tire rim browser"
  current_version = 1

  context "when does not exist before" do
    it "creates device_id record" do
      device_pre = Device.find_by(device_id: device_id)
      device_pre.destroy() if device_pre

      response = call_api(method, device_id,
                          { 'user_agent' => user_agent,
                            'version'    => current_version+1})

      device_post = Device.find_by(device_id: device_id)
      expect(device_post).not_to be_nil
    end
  end

  context "when does exist before"
  it "device_id record is unchanged" do
    device_pre = Device.find_by(device_id: device_id)
    device_pre ||= Device.new(device_id:  device_id,
                              user_agent: user_agent)
    expect(device_pre).not_to be_nil

    response = call_api(method, device_id,
                        { 'user_agent' => user_agent,
                          'version'    => current_version+1})

    device_post = Device.find_by(device_id: device_id)
    expect(device_post).not_to be_nil
    expect(device_pre.id).to eq(device_post.id)
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

RSpec.describe Protocol do
  method = "register_device"
  procname = "process_request_#{method}"
  device_id = "TEST_DEV_42"
  params = {}
  context "when registration_edit == 1" do
    params['registration_edit'] = 1
    context "with no account ID" do
      it "has error" do
        response = call_api(method, device_id, params)
        # check for error
      end
    end
    context "with account ID" do
      context "when name changes" do
        it "changes the name in the account record" do
          response = call_api(method, device_id, params)
          # check message
          # check new name in account record
        end
      end
      context "when email changes" do
        it "sends verification" do
          response = call_api(method, device_id, params)
          # check message
          # check verification cred
        end
      end
      context "when mobile changes" do
        it "sends verification" do
          response = call_api(method, device_id, params)
          # check message
          # check verification cred
        end
      end
      context "when email changes again" do
        it "sends verification, invalidates old verification" do
          response = call_api(method, device_id, params)
          # check message
          # check new verification cred
          # check old verification cred
        end
      end
      context "when first email change is verified" do
        it "fails"
        response = call_api(method, device_id, params)
        # check failure
      end
      context "when second email change is verified" do
        it "updates email in account"
        response = call_api(method, device_id, params)
        # 
      end
      context "when mobile change is verified" do
        it "updates mobile in account"
        response = call_api(method, device_id, params)
        # check mobile in account
      end
    end
  end
  context "when registration_edit == 0" do
    params['registration_edit'] = 0
    context "new_account = 'no'" do
      params['new_account'] = 'no'
      context "when name changes" do
        params['name'] = 'new name'
        response = call_api(method, device_id, params)
        # check mobile in account
      end
      context "when email changes" do
        params['name'] = 'new name'
        response = call_api(method, device_id, params)
        # check mobile in account
      end
    end
  end
  context "when registration_edit == 1, new_account == 0, name.nil?"
  xit "" do
  response = call_api(method, device_id, params)
  end
  context "when registration_edit == 1, new_account == 0, ! name.nil?"
  xit "" do
    response = call_api(method, device_id, params)
  end
  context "when registration_edit == 1, new_account == 1"
  xit "" do
    response = call_api(method, device_id, params)
  end
  context "when no name"
  xit "Get error message, no verification sent" do
    response = call_api(method, device_id, params)
  end
  context "when bad email format"
  xit "Get error message, no verification sent" do
    response = call_api(method, device_id, params)
  end
  context "when bad SMS format"
  xit "Get error message, no verification sent" do
    response = call_api(method, device_id, params)
  end
  context "when good name/email, download_app == 0"
  xit "" do
    response = call_api(method, device_id, params)
  end
  context "when good name/email, download_app == 1, desktop"
  xit "get verification, no download_app" do
    response = call_api(method, device_id, params)
  end
  context "when good name/email, download_app == 1, ios browser"
  xit "get verification, redirect to iOS" do
    response = call_api(method, device_id, params)
  end
  context "when good name/email, download_app == 1, android browser"
  xit "get verification, redirect to android" do
    response = call_api(method, device_id, params)
  end
  context ""
  xit "" do
    response = call_api(method, device_id, params)
  end
  context ""
  xit "" do
    response = call_api(method, device_id, params)
  end
  context ""
  xit "" do
    response = call_api(method, device_id, params)
  end
  context ""
  xit "" do
    response = call_api(method, device_id, params)
  end
  context ""
  xit "" do
    response = call_api(method, device_id, params)
  end
end

RSpec.describe Protocol do
  method = "share_location"
  procname = "process_request_#{method}"
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
  procname = "process_request_#{method}"
  device_id = "TEST_DEV_42"
  params = {}
  context "when get positions shared to device_id"
  it "returns GPS coords shared to device_id" do
    response = call_api(method, device_id, params)
    # check coords for new_orleans and new_york
  end
  context ""
  it "" do

  end
end

RSpec.describe Protocol do
  method = "get_registration"
  procname = "process_request_#{method}"
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



