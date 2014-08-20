class CreateRedeems < ActiveRecord::Migration
  def change
    create_table :redeems do |t|
      t.integer :share_id
      t.string :device_id

      t.timestamps
    end
  end
end
