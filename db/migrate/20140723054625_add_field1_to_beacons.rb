class AddField1ToBeacons < ActiveRecord::Migration
  def change
    add_column :beacons, :share_cred, :string
  end
end
