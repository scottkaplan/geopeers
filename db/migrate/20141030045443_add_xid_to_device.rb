class AddXidToDevice < ActiveRecord::Migration
  def change
    add_column :devices, :xdevice_id, :string
  end
end
