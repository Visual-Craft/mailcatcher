require 'mail'
require 'mail_catcher/mongo_entity'
require 'mail_catcher/utils'

module MailCatcher
  class Message < MailCatcher::MongoEntity
    define_field :id, nil
    define_field :owner, nil
    define_field :sender, nil
    define_field :recipients, nil
    define_field :subject, nil
    define_field :source, nil
    define_field :size, nil
    define_field :new, nil
    define_field :created_at, nil
    define_field :attachments, []
    define_field :parts, []

    class << self
      def from_raw(data)
        mail = ::Mail.new(data[:source])
        processed_data = {
          owner: data[:owner],
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

    def html_part
      parts.detect { |p| %w(text/html application/xhtml+xml).include?(p[:type]) }
    end

    def has_html?
      !!html_part
    end

    def plain_part
      parts.detect { |p| 'text/plain' == p[:type] }
    end

    def has_plain?
      !!plain_part
    end

    def cid_part(cid)
      parts.detect { |p| p[:cid] === cid } || attachments.detect { |p| p[:cid] === cid }
    end
  end
end
