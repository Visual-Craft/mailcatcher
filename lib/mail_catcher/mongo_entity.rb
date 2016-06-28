require 'mail_catcher/utils'

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
