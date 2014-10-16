class CreatePeople < ActiveRecord::Migration
  def change
    create_table :people do |t|
      t.string :name
      t.text :books
      t.text :cars

      t.timestamps
    end
  end
end
