require 'mail_catcher/utils'
require 'bson'

module MailCatcher
  class MongoEntity
    # @param [String|Symbol] name
    # @param [Object] default_value
    def self.define_field(name, default_value)
      name = name.to_sym
      attr_accessor(name)
      @fields ||= {}
      @fields[name] = default_value
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
      hash = MailCatcher::Utils.recursive_walk(hash) do |v|
        if v.is_a? BSON::Binary
          v.data
        else
          v
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
        inst.send(:"#{k}=", hash.has_key?(k) ? hash[k] : v)
      end

      inst
    end

    def initialize
      self.class.fields.each do |k,v|
        send(:"#{k}=", v)
      end
    end

    # @return [Hash]
    def to_mongo
      hash = to_h
      hash.delete(:id)

      MailCatcher::Utils.recursive_walk(hash) do |v|
        if v.is_a? MailCatcher::BinaryString
          BSON::Binary.new(v.data)
        else
          v
        end
      end
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

  class BinaryString
    def initialize(data)
      @data = data
    end

    def data
      @data
    end
  end
end
