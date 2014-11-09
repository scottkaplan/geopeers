class AddAuthKeyToAuth < ActiveRecord::Migration
  def change
    add_column :auths, :auth_key, :string
  end
end
