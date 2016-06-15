require 'active_support/json'
require 'eventmachine'
require 'mongo'
require 'mail_catcher/message'

module MailCatcher::Mail extend self
  include Mongo

  def add_message(data)
    message = MailCatcher::Message.from_raw(data)
    result = collection.insert_one(message.to_h)
    message = MailCatcher::Message.from_mongo(collection.find(:_id => result.inserted_id).to_a.first)

    EventMachine.next_tick do
      message = MailCatcher::Mail.message message.id
      MailCatcher::Events::MessageAdded.push message.to_h
    end
  end

  def messages
    collection.find.to_a.map { |doc| MailCatcher::Message.from_mongo(doc).to_h }
  end

  def message(id)
    doc = collection.find({ "_id" => object_id(id) }).to_a.first
    MailCatcher::Message.from_mongo(doc) if doc
  end

  def delete!
    collection.find.delete_many
  end

  def delete_by_owner!(owner)
    if owner.blank?
      collection.find.delete_many
    else
      collection.find("owner" => owner).delete_many
    end
  end

  def delete_message!(id)
    collection.find({ "_id" => object_id(id) }).delete_one
  end

  def mark_readed(id)
    collection.find_one_and_update({ "_id" => object_id(id) }, { '$set' => { :new => 0 }})
  end

  private

  def config
    @config ||= MailCatcher.config[:db]
  end

  def db
    #TODO: https://docs.mongodb.com/ecosystem/tutorial/ruby-driver-tutorial/
    #TODO: MongoDB URI must be in the following format: mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
    #TODO: mongod --port 27017 --dbpath :PATH
    @db ||= Mongo::Client.new(["#{config[:host]}:#{config[:port]}"], :database => config[:name])
  end

  def collection
    db['messages']
  end

  def object_id val
    begin
      BSON::ObjectId.from_string(val)
    rescue BSON::ObjectId::Invalid
      nil
    end
  end
end
