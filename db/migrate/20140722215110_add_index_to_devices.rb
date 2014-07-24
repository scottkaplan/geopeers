class AddIndexToDevices < ActiveRecord::Migration
  def change
    add_column :devices, :device_name, :string
    add_index :devices, :device_name, unique: true
  end
end
