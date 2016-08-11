require 'eventmachine'
require 'mongo'
require 'mail_catcher/message'

module MailCatcher::Mail extend self
  class NotFoundException < StandardError; end
  class AccessDeniedException < StandardError; end

  def add_message(data)
    message = MailCatcher::Message.from_raw(data)
    result = collection.insert_one(message.to_mongo)
    message.id = result.inserted_id.to_s

    EventMachine.next_tick do
      MailCatcher::Events::MessageAdded.push(message)
    end
  end

  def messages(user=nil)
    collection.find(filter_for_user(user)).sort(:created_at => -1)
      .map { |doc| MailCatcher::Message.from_mongo(doc) }
  end

  def message(id, user=nil)
    raise NotFoundException if (id = to_bson_object_id(id)).nil?

    doc = collection.find({ :_id => id }).limit(1).first

    raise NotFoundException if doc.nil?

    message = MailCatcher::Message.from_mongo(doc)

    return message unless user

    raise AccessDeniedException unless MailCatcher.users.allowed_owner?(user, message.to_h[:owner])

    message
  end

  def delete!(user=nil)
    collection.find(filter_for_user(user)).delete_many.n > 0
  end

  def delete_by_owner!(owner, user=nil)
    raise AccessDeniedException if user && !MailCatcher.users.allowed_owner?(user, owner)

    collection.find({ :owner => owner }).delete_many.n > 0
  end

  def delete_message!(id, user=nil)
    message(id, user)
    collection.find({ :_id => to_bson_object_id(id) }).delete_one.n > 0
  end

  def mark_readed(id, user=nil)
    message(id, user)
    collection.find({ :_id => to_bson_object_id(id) }).update_one({ :$set => { :new => 0 } }).n > 0
  end

  private

  # @param [MailCatcher::User] user
  def filter_for_user(user)
    if user.all_owners
      return nil
    end

    if user.unassigned_owners
      { :$or => [{ "owner" => { :$in => user.owners } }, { "owner" => { :$nin => MailCatcher.users.assigned_owners } }] }
    else
      { "owner" => { :$in => user.owners } }
    end
  end

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
    rescue
      nil
    end
  end
end
