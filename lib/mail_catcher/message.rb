require 'mail'
require 'mail_catcher/mongo_entity'
require 'mail_catcher/utils'

module MailCatcher
  class Message < MailCatcher::MongoEntity
    class SourceProcessor
      def self.to_mongo(value)
        if value.is_a?(String)
          BSON::Binary.new(value)
        else
          value
        end
      end

      def self.from_mongo(value)
        if value.is_a?(BSON::Binary)
          value.data
        else
          value
        end
      end
    end

    class AttachmentsProcessor
      def self.to_mongo(value)
        if value.is_a?(Hash)
          value.each do |_,v|
            if v[:body].is_a?(String)
              v[:body] = BSON::Binary.new(v[:body])
            end
          end
        else
          value
        end
      end

      def self.from_mongo(value)
        if value.is_a?(BSON::Binary)
          value.data
        else
          value
        end

        if value.is_a?(Hash)
          value.each do |_,v|
            if v[:body].is_a?(BSON::Binary)
              v[:body] = v[:body].data
            end
          end
        else
          value
        end
      end
    end

    define_field :id
    define_field :folder
    define_field :sender
    define_field :recipients
    define_field :subject
    define_field :source, nil, SourceProcessor
    define_field :size
    define_field :new
    define_field :created_at
    define_field :attachments, [], AttachmentsProcessor
    define_field :parts, []

    class << self
      def from_raw(data)
        mail = ::Mail.new(data[:source])
        processed_data = {
          folder: data[:folder],
          sender: data[:sender],
          recipients: data[:recipients],
          subject: mail.subject,
          source: data[:source],
          size: data[:source].length,
          new: 1,
          created_at: Time.now,
          parts: {},
          attachments: {},
        }

        parts = mail.all_parts
        parts = [mail] if parts.empty?
        part_ids = {
            :attachments => 0,
            :parts => 0,
        }
        parts.each do |part|
          body = part.body.to_s
          type = part.mime_type || 'text/plain'
          part_key = part.attachment? ? :attachments : :parts
          part_id = part_ids[part_key].to_s.to_sym
          processed_data[part_key][part_id] = {
            id: part_id,
            cid: part.respond_to?(:cid) ? part.cid : nil,
            type: type,
            filename: part.filename,
            charset: part.charset,
            body: body,
            size: body.length,
          }
          part_ids[part_key] += 1
        end

        from_h(processed_data)
      end
    end

    def to_short_hash
      hash = to_h
      hash[:source] = nil
      hash[:parts].each { |_,v| v[:body] = nil }
      hash[:attachments].each { |_,v| v[:body] = nil }
      hash
    end
  end
end
