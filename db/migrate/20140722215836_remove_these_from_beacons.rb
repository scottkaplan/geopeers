class RemoveTheseFromBeacons < ActiveRecord::Migration
  def change
    remove_column :beacons, :type, :string
    remove_column :beacons, :to, :string
  end
end
