class CreateBeacons < ActiveRecord::Migration
  def change
    create_table :beacons do |t|
      t.string :beacon
      t.datetime :expire_time
      t.string :seen_device_id
      t.string :seer_device_id

      t.timestamps
    end
  end
end
