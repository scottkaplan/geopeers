class RemoveThis3FromBeacons < ActiveRecord::Migration
  def change
    remove_column :beacons, :share_type, :string
  end
end
