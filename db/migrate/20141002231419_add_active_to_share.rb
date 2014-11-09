class AddActiveToShare < ActiveRecord::Migration
  def change
    add_column :shares, :active, :int
  end
end
