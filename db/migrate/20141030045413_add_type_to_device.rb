class AddTypeToDevice < ActiveRecord::Migration
  def change
    add_column :devices, :app_type, :string
  end
end
