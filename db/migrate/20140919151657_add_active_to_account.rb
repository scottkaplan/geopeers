class AddActiveToAccount < ActiveRecord::Migration
  def change
    add_column :accounts, :active, :int
  end
end
