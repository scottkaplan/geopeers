class AddGlobalKeyValToGlobal < ActiveRecord::Migration
  def change
    add_column :globals, :Global, :string
    add_column :globals, :key, :string
    add_column :globals, :value, :string
  end
end
