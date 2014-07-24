class AddThis2ToBeacons < ActiveRecord::Migration
  def change
    add_column :beacons, :share_type, "ENUM('sms','email','twitter','facebook')"
  end
end
