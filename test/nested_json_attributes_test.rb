require 'test_helper'

class NestedStoreAttributesTest < ActiveSupport::TestCase
  
  def setup
    @books = {1 => {isbn: 1234, name: 'war, what is it good for' }, 2 => {isbn: 5678, name: 'the borg'}}
    @books_array = @books.values.map(&:stringify_keys)
    @person = Person.create(books_attributes: @books)
  end

  # called after every single test
  def teardown
    # as we are re-initializing @post before every test
    # setting it to nil here is not essential but I hope
    # you understand how you can use the teardown method
    @post = nil
  end
  
  test "adds accepts_store_attributes to ActiveRecord" do
    assert Class.new(ActiveRecord::Base).respond_to?(:accepts_store_attributes_for)
  end
  
  test "generates books_attributes= method for person" do
    assert Person.new.respond_to?(:books_attributes=)
  end
  test "generates cars_attributes= method for person" do
    assert Person.new.respond_to?(:cars_attributes=)
  end
    
  test "adds new books as hash" do
    assert_equal @books_array, @person.books
  end
  
  test "adds new books as array" do
    person = Person.create(books_attributes: @books_array)
    assert_equal @books_array, person.books
  end
  
  test "updates existing books" do
    @person.books_attributes = [{isbn: 1234, name: 'war and peace'}]
    expected_array = [{isbn: 1234, name: 'war and peace' }, {isbn: 5678, name: 'the borg'}].map(&:stringify_keys)
    assert_equal expected_array, @person.books
  end
  
  test "removes existing books" do
    @person.books_attributes = [{isbn: 1234, _destroy: true}]
    expected_array = [{isbn: 5678, name: 'the borg'}].map(&:stringify_keys)
    assert_equal expected_array, @person.books    
  end
  
  test "adds, updates, and removes all at once" do
    @person.books_attributes = [{isbn: 1234, name: 'war and peace'}, {isbn: 5678, _destroy: 1}, {isbn: 9100, title: 'moon landing'}]
    expected_array = [{isbn: 1234, name: 'war and peace' }, {isbn: 9100, title: 'moon landing'}].map(&:stringify_keys)
    assert_equal expected_array, @person.books
  end
  
  test "raises error if argument is not a hash or array" do
    assert_raise ArgumentError do
      Person.create(books_attributes: 'invalid value')
    end
  end
  
  test "wont delete unless allow_destroy is set" do
    person = Person.create(cars_attributes: [{id: 1, name: 'test'}])
    person.cars_attributes = [{id: 1, _destroy: true}]
    assert person.cars = [{id: 1, name: 'test'}]
  end
  
  
end
