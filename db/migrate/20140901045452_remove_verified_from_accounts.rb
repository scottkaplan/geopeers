class RemoveVerifiedFromAccounts < ActiveRecord::Migration
  def change
    remove_column :accounts, :email_verified, :integer
    remove_column :accounts, :mobile_verified, :integer
  end
end
