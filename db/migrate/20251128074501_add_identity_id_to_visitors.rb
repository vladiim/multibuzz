class AddIdentityIdToVisitors < ActiveRecord::Migration[8.0]
  def change
    add_reference :visitors, :identity, null: true, foreign_key: true, index: true
  end
end
