class CreateShares < ActiveRecord::Migration
  def change
    create_table :shares do |t|
      t.datetime :expire_time
      t.string :device_id
      t.string :share_via
      t.string :share_to
      t.string :share_cred
      t.string :share_to
      t.integer :num_uses
      t.integer :num_uses_max

      t.timestamps
    end
    add_index :shares, :share_cred, unique: true
  end
end
