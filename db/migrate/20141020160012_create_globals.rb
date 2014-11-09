class CreateGlobals < ActiveRecord::Migration
  def change
    create_table :globals do |t|
      t.integer :build_id

      t.timestamps
    end
  end
end
