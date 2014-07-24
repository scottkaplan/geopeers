class AddThis3ToBeacons < ActiveRecord::Migration
  def change
    add_column :beacons, :share_via, "ENUM('sms','email','twitter','facebook')"
  end
end
