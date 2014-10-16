require 'active_support/core_ext/hash/except'
require 'active_support/core_ext/object/try'
require 'active_support/core_ext/hash/indifferent_access'

module NestedStoreAttributes
  module AcceptsStoreAttributes #:nodoc:
    class TooManyRecords < ActiveRecord::ActiveRecordError
    end

    extend ActiveSupport::Concern

    included do
      class_attribute :store_attributes_options, instance_writer: false
      self.store_attributes_options = {}
    end

    module ClassMethods
      REJECT_ALL_BLANK_PROC = proc { |attributes| attributes.all? { |key, value| key == '_destroy' || value.blank? } }

      # Defines an attributes writer for the specified serialized attribute(s).
      #
      # Supported options:
      # [:allow_destroy]
      #   If true, destroys any members from the attributes hash with a
      #   <tt>_destroy</tt> key and a value that evaluates to +true+
      #   (eg. 1, '1', true, or 'true'). This option is off by default.
      # [:reject_if]
      #   Allows you to specify a Proc or a Symbol pointing to a method
      #   that checks whether a record should be built for a certain attribute
      #   hash. The hash is passed to the supplied Proc or the method
      #   and it should return either +true+ or +false+. When no :reject_if
      #   is specified, a record will be built for all attribute hashes that
      #   do not have a <tt>_destroy</tt> value that evaluates to true.
      #   Passing <tt>:all_blank</tt> instead of a Proc will create a proc
      #   that will reject a record where all the attributes are blank excluding
      #   any value for _destroy.
      # [:limit]
      #   Allows you to specify the maximum number of the nested records that
      #   can be processed with the nested attributes. Limit also can be specified as a
      #   Proc or a Symbol pointing to a method that should return number. If the size of the
      #   nested attributes array exceeds the specified limit, NestedAttributes::TooManyRecords
      #   exception is raised. If omitted, any number nested records can be processed.
      # [:primary_key]
      #   Allows you to specify the primary key to use when checking for existing objects. This
      #   defaults to :id.
      #
      # Examples:
      #   # creates subscribers_attributes=
      #   accepts_store_attributes_for :subscribers, primary_key: :email
      #   # creates books_attributes=
      #   accepts_store_attributes_for :books, reject_if: proc { |attributes| attributes['name'].blank? }
      #   # creates books_attributes=
      #   accepts_store_attributes_for :books, reject_if: :all_blank
      #   # creates books_attributes= and posts_attributes=
      #   accepts_store_attributes_for :books, :posts, allow_destroy: true
      def accepts_store_attributes_for(*attr_names)
        options = { :allow_destroy => false, :update_only => false, :primary_key => :id }
        options.update(attr_names.extract_options!)
        options.assert_valid_keys(:allow_destroy, :reject_if, :limit, :update_only, :primary_key)
        options[:reject_if] = REJECT_ALL_BLANK_PROC if options[:reject_if] == :all_blank

        attr_names.each do |attribute_name|
          if self.attribute_names.include?(attribute_name.to_s)

            store_attributes_options = self.store_attributes_options.dup
            store_attributes_options[attribute_name] = options
            self.store_attributes_options = store_attributes_options

            store_generate_collection_writer(attribute_name)
          else
            raise ArgumentError, "No column found for name `#{attribute_name}'. Has it been added yet?"
          end
        end
      end

      private

      # Generates a writer method for this attribute. Serves as a point for
      # accessing the hashes in the attribute. For example, this method
      # could generate the following:
      #
      #   def pirate_attributes=(attributes)
      #     store_assign_nested_attributes_for_collection_association(:pirate, attributes)
      #   end
      #
      # This redirects the attempts to write objects in an association through
      # the helper methods defined below. Makes it seem like the nested
      # associations are just regular associations.
      def store_generate_collection_writer(attribute_name)
        generated_association_methods.module_eval <<-eoruby, __FILE__, __LINE__ + 1
          if method_defined?(:#{attribute_name}_attributes=)
            remove_method(:#{attribute_name}_attributes=)
          end
          def #{attribute_name}_attributes=(attributes)
            store_assign_nested_attributes_for_collection(:#{attribute_name}, attributes)
          end
        eoruby
      end
    end

    def _destroy
      nil?
    end

    private

    # Attribute hash keys that should not be assigned as normal attributes.
    # These hash keys are nested attributes implementation details.
    UNASSIGNABLE_KEYS = %w( id _destroy )


    # Assigns the given attributes to the collection attribute.
    #
    # Hashes with an primary_key (by default <tt>:id</tt>) value matching an existing nested record
    # will update that record. Hashes without an primary_key value will build
    # a new record for the association. Hashes with a matching primary_key
    # value and a <tt>:_destroy</tt> key set to a truthy value will mark the
    # matched record for destruction.
    #
    # For example:
    #
    #   store_assign_nested_attributes_for_collection_association(:people, {
    #     '1' => { id: '1', name: 'Peter' },
    #     '2' => { name: 'John' },
    #     '3' => { id: '2', _destroy: true }
    #   })
    #
    # Will update the name of the Person with ID 1, add a new record for
    # person with the name 'John', and remove the Person with ID 2.
    #
    # Also accepts an Array of attribute hashes:
    #
    #   store_assign_nested_attributes_for_collection_association(:people, [
    #     { id: '1', name: 'Peter' },
    #     { name: 'John' },
    #     { id: '2', _destroy: true }
    #   ])
    def store_assign_nested_attributes_for_collection(attribute_name, attributes_collection)
      options = self.store_attributes_options[attribute_name]

      unless attributes_collection.is_a?(Hash) || attributes_collection.is_a?(Array)
        raise ArgumentError, "Hash or Array expected, got #{attributes_collection.class.name} (#{attributes_collection.inspect})"
      end

      store_check_record_limit!(options[:limit], attributes_collection)
      primary_key = options[:primary_key].to_s
      new_collection = []

      if attributes_collection.is_a? Hash
        keys = attributes_collection.keys
        attributes_collection = if keys.include?(primary_key) || keys.include?(primary_key.to_sym)
          [attributes_collection]
        else
          attributes_collection.values
        end
      end

      existing_records = self.send(attribute_name) || []
      existing_records.map!(&:with_indifferent_access)

      attributes_collection.each do |attributes|
        attributes = attributes.with_indifferent_access
  
        if attributes[primary_key].present? && existing_record = existing_records.delete_at(existing_records.index { |record| record[primary_key].to_s == attributes[primary_key].to_s } || existing_records.length)
          unless store_call_reject_if(attribute_name, attributes)
            new_collection << store_add_or_destroy(existing_record, attributes, options[:allow_destroy])
          end
        else
          unless store_reject_new_record?(attribute_name, attributes)
            new_collection << attributes.except(*UNASSIGNABLE_KEYS)
          end
        end
      end
      
      new_collection += existing_records
      new_collection.reject!(&:nil?)
      self.assign_attributes(attribute_name => new_collection)
    end

    # Takes in a limit and checks if the attributes_collection has too many
    # records. It accepts limit in the form of symbol, proc, or
    # number-like object (anything that can be compared with an integer).
    #
    # Raises TooManyRecords error if the attributes_collection is
    # larger than the limit.
    def store_check_record_limit!(limit, attributes_collection)
      if limit
        limit = case limit
        when Symbol
          send(limit)
        when Proc
          limit.call
        else
          limit
        end

        if limit && attributes_collection.size > limit
          raise TooManyRecords, "Maximum #{limit} records are allowed. Got #{attributes_collection.size} records instead."
        end
      end
    end

    # Updates a record with the +attributes+ or returns nil if
    # +allow_destroy+ is +true+ and has_destroy_flag? returns +true+.
    def store_add_or_destroy(hash, attributes, allow_destroy)
      hash.merge!(attributes.except(*UNASSIGNABLE_KEYS))
      unless store_has_destroy_flag?(attributes) && allow_destroy
        return hash
      else
        return nil
      end
    end

    # Determines if a hash contains a truthy _destroy key.
    def store_has_destroy_flag?(hash)
      hash.stringify_keys!
      ActiveRecord::ConnectionAdapters::Column.value_to_boolean(hash['_destroy'])
    end

    # Determines if a new record should be rejected by checking
    # has_destroy_flag? or if a <tt>:reject_if</tt> proc exists for this
    # attribute and evaluates to +true+.
    def store_reject_new_record?(attribute_name, attributes)
      store_has_destroy_flag?(attributes) || store_call_reject_if(attribute_name, attributes)
    end

    # Determines if a record with the particular +attributes+ should be
    # rejected by calling the reject_if Symbol or Proc (if defined).
    # The reject_if option is defined by +accepts_nested_attributes_for+.
    #
    # Returns false if there is a +destroy_flag+ on the attributes.
    def store_call_reject_if(attribute_name, attributes)
      return false if store_has_destroy_flag?(attributes)
      case callback = self.store_attributes_options[attribute_name][:reject_if]
      when Symbol
        method(callback).arity == 0 ? send(callback) : send(callback, attributes)
      when Proc
        callback.call(attributes)
      end
    end

    def store_raise_nested_attributes_record_not_found!(attribute_name, record_id)
      raise RecordNotFound, "Couldn't find #{attribute_name} with ID=#{record_id} for #{self.class.name} with ID=#{id}"
    end
  end
end

ActiveRecord::Base.send :include, NestedStoreAttributes::AcceptsStoreAttributes
