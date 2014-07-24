class RemoveThisFromBeacons < ActiveRecord::Migration
  def change
    remove_column :beacons, :beacon, :string
  end
end
