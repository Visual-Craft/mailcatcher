require 'mail'
module MailCatcher
  class Message
    class << self
      def fields
        @fields ||= {
            _id: nil,
            owner: nil,
            sender: nil,
            recipients: nil,
            subject: nil,
            source: nil,
            size: nil,
            new: nil,
            created_at: nil,
            attachments: [],
            parts: [],
        }
      end

      def from_raw(params = {})
        mail = ::Mail.new(params[:source])
        parts = mail.all_parts
        parts = [mail] if parts.empty?

        data = {
          owner: params[:owner],
          sender: params[:sender],
          recipients: params[:recipients],
          subject: mail.subject,
          source: params[:source],
          size: params[:source].length,
          new: 1,
          created_at: Time.now,
        }

        parts.each do |part|
          body = part.body.to_s
          (data[part.attachment? ? :attachments : :parts] ||= []) << {
              cid: part.respond_to?(:cid) ? part.cid : nil,
              type: part.mime_type || 'text/plain',
              filename: part.filename,
              charset: part.charset,
              body: body,
              size: body.length,
          }
        end

        new(data)
      end

      def from_mongo(params = {})
        new(params)
      end

      def keys_to_sym(hash)
        hash.inject({}) { |a,(k,v)| a[k.to_sym] = v; a }
      end
    end

    def initialize(params={})
      h = self.class.keys_to_sym(params)
      h[:parts] = h[:parts].map { |array| self.class.keys_to_sym(array) } if h[:parts]
      h[:attachments] = h[:attachments].map { |array| self.class.keys_to_sym(array) } if h[:attachments]
      @data = self.class.fields.merge(h)
    end

    def attachments
      @attachments ||= @data[:attachments]
    end

    def parts
      @parts ||= @data[:parts]
    end

    def html_part
      @html_part ||= parts.detect { |p| %w(text/html application/xhtml+xml).include?(p[:type]) }
    end

    def has_html?
      !!html_part
    end

    def plain_part
      @plain_part ||= parts.detect { |p| 'text/plain' == p[:type] }
    end

    def has_plain?
      !!plain_part
    end

    def cid_part(cid)
      cid_part ||= parts.detect { |p| cid == p[:cid] }
      cid_part ||= attachments.detect { |p| cid == p[:cid] }
      cid_part
    end

    def id
      @id ||= @data[:_id].to_s
    end

    def to_h
      @data.merge(id: id)
    end

    def to_json
      @data.merge(id: id).to_json
    end

    def method_missing(m, *args, &block)
      if @data.include?(m.to_sym)
        @data[m.to_sym]
      else
        raise ArgumentError.new("Method `#{m}` doesn't exist.")
      end
    end

    def respond_to?(method_name, include_private = false)
      @data.include?(method_name.to_sym) || super
    end
  end
end
