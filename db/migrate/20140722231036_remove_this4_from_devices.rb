class RemoveThis4FromDevices < ActiveRecord::Migration
  def change
    remove_column :devices, :device_name, :string
  end
end
