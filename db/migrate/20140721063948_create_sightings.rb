class CreateSightings < ActiveRecord::Migration
  def change
    create_table :sightings do |t|
      t.string :device_id
      t.float :gps_longitude
      t.float :gps_latitude

      t.timestamps
    end
  end
end
