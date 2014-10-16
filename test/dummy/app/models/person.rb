class Person < ActiveRecord::Base
  
  serialize :books, JSON
  serialize :cars, JSON
  
  accepts_store_attributes_for :books, primary_key: :isbn, allow_destroy: true
  
  accepts_store_attributes_for :cars
end
