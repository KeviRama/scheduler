class AddStartDay < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :firstday, :integer, :default => 0
  end
end
