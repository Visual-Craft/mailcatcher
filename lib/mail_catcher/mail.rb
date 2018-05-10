require 'eventmachine'
require 'mongo'
require 'mail_catcher/message'
require 'mail_catcher/folder_list'

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

  def messages(folder, user)
    filter = []
    uf = filter_for_user(user)

    unless uf.nil?
      filter.push(uf)
    end

    unless folder.nil?
      filter.push({ :folder => folder })
    end

    if filter.empty?
      filter = nil
    else
      filter = {
        :$and => filter,
      }
    end

    collection.find(filter).sort(:created_at => -1)
      .map { |doc| MailCatcher::Message.from_mongo(doc) }
  end

  def message(id, user)
    raise NotFoundException if (id = to_bson_object_id(id)).nil?

    doc = collection.find({ :_id => id }).limit(1).first

    raise NotFoundException if doc.nil?

    message = MailCatcher::Message.from_mongo(doc)

    unless user.nil?
      raise AccessDeniedException unless MailCatcher.users.allowed_folder?(user, message.folder)
    end

    message
  end

  def delete!(user=nil)
    collection.find(filter_for_user(user)).delete_many.n > 0
  end

  def delete_by_folder!(folder, user)
    raise AccessDeniedException unless MailCatcher.users.allowed_folder?(user, folder)

    collection.find({ :folder => folder }).delete_many.n > 0
  end

  def delete_message!(id, user)
    message(id, user)
    collection.find({ :_id => to_bson_object_id(id) }).delete_one.n > 0
  end

  def mark_readed(id, user=nil)
    message(id, user)
    collection.find({ :_id => to_bson_object_id(id) }).update_one({ :$set => { :new => 0 } }).n > 0
  end

  def folders(user=nil)
    project = []
    filter = filter_for_user(user)

    if filter
      project.push({
        :$match => filter,
      })
    end

    project.push({
      :$group => {
        :_id => '$folder',
        :count => { :$sum => 1 },
        :newCount => {
          :$sum => {
            :$switch => {
              :default => 0,
              :branches => [
                {
                  :case => {
                    :$eq => [ '$new', 1 ],
                  },
                  then: 1,
                },
              ],
            },
          },
        },
      },
    })
    project.push({
      :$sort => { :_id => 1 },
    })

    folder_list = MailCatcher::FolderList.new('! All')
    collection.aggregate(project).each do |doc|
      folder_list.add(doc['_id'], doc['count'], doc['newCount'])
    end

    folder_list.to_a
  end

  private

  # @param [MailCatcher::User] user
  def filter_for_user(user)
    if user.nil? || user.all_folders
      return nil
    end

    filter = { :folder => { :$in => user.folders } }

    if user.unassigned_folders
      filter = { :$or => [filter, { :folder => { :$nin => MailCatcher.users.assigned_folders } }] }
    end

    filter
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

      client = Mongo::Client.new(["#{host}:#{port}"], options)
      client[:messages].indexes.create_one({ created_at: -1 })
      client
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
