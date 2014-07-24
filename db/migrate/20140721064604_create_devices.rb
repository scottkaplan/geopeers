class CreateDevices < ActiveRecord::Migration
  def change
    create_table :devices do |t|
      t.string :device_id
      t.string :user_agent
      t.string :name
      t.string :email

      t.timestamps
    end
  end
end
