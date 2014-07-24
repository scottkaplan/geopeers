class AddTheseToBeacons < ActiveRecord::Migration
  def change
    add_column :beacons, :share_type, :string
    add_column :beacons, :share_to, :string
  end
end
