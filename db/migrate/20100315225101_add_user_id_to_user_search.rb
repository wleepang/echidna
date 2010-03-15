class AddUserIdToUserSearch < ActiveRecord::Migration
  def self.up
    add_column :user_searches, :user_id, :integer
  end

  def self.down
    remove_column :user_searches, :user_id
  end
end
