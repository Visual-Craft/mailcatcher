require 'eventmachine'
require 'mongo'
require 'mail_catcher/message'

module MailCatcher::Mail extend self
  def add_message(data)
    message = MailCatcher::Message.from_raw(data)
    result = collection.insert_one(message.to_mongo)
    message.id = result.inserted_id.to_s

    EventMachine.next_tick do
      MailCatcher::Events::MessageAdded.push(message)
    end
  end

  def messages
    collection.find.map { |doc| MailCatcher::Message.from_mongo(doc) }
  end

  def message(id)
    doc = collection.find({ :_id => to_bson_object_id(id) }).limit(1).first

    if doc.nil?
      nil
    else
      MailCatcher::Message.from_mongo(doc)
    end
  end

  def delete!
    collection.find.delete_many.n > 0
  end

  def delete_by_owner!(owner)
    owner = nil if owner.blank?
    collection.find({ :owner => owner }).delete_many.n > 0
  end

  def delete_message!(id)
    collection.find({ :_id => to_bson_object_id(id) }).delete_one.n > 0
  end

  def mark_readed(id)
    collection.find({ :_id => to_bson_object_id(id) }).update_one({ :$set => { :new => 0 } }).n > 0
  end

  private

  def db
    @db ||= begin
      options = MailCatcher.config[:db].clone
      host = options.delete(:host)
      port = options.delete(:port)

      Mongo::Logger.logger.level = if MailCatcher.env === 'development'
        ::Logger::DEBUG
      else
        ::Logger::FATAL
      end

      Mongo::Client.new(["#{host}:#{port}"], options)
    end
  end

  def collection
    db[:messages]
  end

  def to_bson_object_id(val)
    begin
      BSON::ObjectId(val)
    rescue BSON::ObjectId::Invalid
      nil
    end
  end
end
