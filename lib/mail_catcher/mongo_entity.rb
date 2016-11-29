require 'mail_catcher/utils'
require 'bson'

module MailCatcher
  class MongoEntity
    # @param [String|Symbol] name
    # @param [Object] default_value
    # @param [Object] processor
    def self.define_field(name, default_value = nil, processor = nil)
      name = name.to_sym
      attr_accessor(name)
      @fields ||= {}
      @fields[name] = {
          :default => default_value,
          :processor => processor,
      }
    end

    # @return [Hash]
    def self.fields
      @fields
    end

    # @param [Hash] hash
    # @return [MailCatcher::MongoEntity]
    def self.from_mongo(hash)
      hash = MailCatcher::Utils.symbolize_hash_keys(hash)
      id = hash.delete(:_id)
      hash[:id] = id.to_s unless id.nil?

      fields.each do |k,v|
        if v[:processor].respond_to?(:from_mongo)
          hash[k] = v[:processor].from_mongo(hash[k])
        end
      end

      from_h(hash)
    end

    # @param [Hash] hash
    # @return [MailCatcher::MongoEntity]
    def self.from_h(hash)
      hash = MailCatcher::Utils.symbolize_hash_keys(hash)
      inst = new

      self.fields.each do |k,v|
        inst.send(:"#{k}=", hash.has_key?(k) ? hash[k] : v[:default])
      end

      inst
    end

    def initialize
      self.class.fields.each do |k,v|
        send(:"#{k}=", v[:default])
      end
    end

    # @return [Hash]
    def to_mongo
      hash = to_h
      hash.delete(:id)

      self.class.fields.each do |k,v|
        if v[:processor].respond_to?(:to_mongo)
          hash[k] = v[:processor].to_mongo(hash[k])
        end
      end

      hash
    end

    # @return [Hash]
    def to_h
      hash = {}
      self.class.fields.each do |k,_|
        hash[k] = send(k)
      end
      hash
    end
  end
end
