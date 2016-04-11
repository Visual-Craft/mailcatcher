require 'active_support/json'
require 'eventmachine'
require 'mail'
require 'sqlite3'

module MailCatcher::Mail extend self
  def database_path=(val)
    @database_path = val
  end

  def add_message(message)
    mail = Mail.new(message[:source])
    @add_message_query ||= db.prepare("INSERT INTO message (owner, sender, recipients, subject, source, type, size, new, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))")
    @add_message_part_query ||= db.prepare "INSERT INTO message_part (message_id, cid, type, is_attachment, filename, charset, body, size, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))"

    db.query('BEGIN IMMEDIATE TRANSACTION')

    begin
      @add_message_query.execute(
          message[:owner],
          message[:sender],
          message[:recipients].to_json,
          mail.subject,
          message[:source],
          mail.mime_type || 'text/plain',
          message[:source].length,
          1
      )
      message_id = db.last_insert_row_id
      parts = mail.all_parts
      parts = [mail] if parts.empty?
      parts.each do |part|
        body = part.body.to_s
        @add_message_part_query.execute(
            message_id,
            # Only parts have CIDs, not mail
            part.respond_to?(:cid) ? part.cid : nil,
            part.mime_type || 'text/plain',
            part.attachment? ? 1 : 0,
            part.filename,
            part.charset,
            body,
            body.length
        )
      end
    rescue
      db.query('ROLLBACK TRANSACTION')
    else
      db.query('COMMIT TRANSACTION')
    end

    EventMachine.next_tick do
      message = MailCatcher::Mail.message message_id
      MailCatcher::Events::MessageAdded.push message
    end
  end

  def latest_created_at
    query = prepare_query('SELECT created_at FROM message ORDER BY created_at DESC LIMIT 1')
    query.execute.next
  end

  def messages
    query = prepare_query('SELECT id, owner, sender, recipients, subject, size, new, created_at FROM message ORDER BY created_at, id ASC')
    query.execute.map do |row|
      Hash[row.fields.zip(row)].tap do |message|
        message['recipients'] &&= ActiveSupport::JSON.decode message['recipients']
      end
    end
  end

  def message(id)
    query = prepare_query('SELECT * FROM message WHERE id = ? LIMIT 1')
    row = query.execute(id).next
    row && Hash[row.fields.zip(row)].tap do |message|
      message['recipients'] &&= ActiveSupport::JSON.decode message['recipients']
    end
  end

  def message_has_html?(id)
    query = prepare_query("SELECT 1 FROM message_part WHERE message_id = ? AND is_attachment = 0 AND type IN ('application/xhtml+xml', 'text/html') LIMIT 1")
    (!!query.execute(id).next) || %w(text/html application/xhtml+xml).include?(message(id)['type'])
  end

  def message_has_plain?(id)
    query = prepare_query("SELECT 1 FROM message_part WHERE message_id = ? AND is_attachment = 0 AND type = 'text/plain' LIMIT 1")
    (!!query.execute(id).next) || message(id)['type'] == 'text/plain'
  end

  def message_parts(id)
    query = prepare_query('SELECT cid, type, filename, size FROM message_part WHERE message_id = ? ORDER BY filename ASC')
    query.execute(id).map do |row|
      Hash[row.fields.zip(row)]
    end
  end

  def message_attachments(id)
    query = prepare_query('SELECT cid, type, filename, size FROM message_part WHERE message_id = ? AND is_attachment = 1 ORDER BY filename ASC')
    query.execute(id).map do |row|
      Hash[row.fields.zip(row)]
    end
  end

  def message_part(message_id, part_id)
    query = prepare_query('SELECT * FROM message_part WHERE message_id = ? AND id = ? LIMIT 1')
    row = query.execute(message_id, part_id).next
    row && Hash[row.fields.zip(row)]
  end

  def message_part_type(message_id, part_type)
    query = prepare_query('SELECT * FROM message_part WHERE message_id = ? AND type = ? AND is_attachment = 0 LIMIT 1')
    row = query.execute(message_id, part_type).next
    row && Hash[row.fields.zip(row)]
  end

  def message_part_html(message_id)
    part = message_part_type(message_id, 'text/html')
    part ||= message_part_type(message_id, 'application/xhtml+xml')
    part ||= begin
      message = message(message_id)
      message if message.present? and %w(text/html application/xhtml+xml).include? message['type']
    end
  end

  def message_part_plain(message_id)
    message_part_type message_id, 'text/plain'
  end

  def message_part_cid(message_id, cid)
    query = prepare_query('SELECT * FROM message_part WHERE message_id = ?')
    query.execute(message_id).map do |row|
      Hash[row.fields.zip(row)]
    end.find do |part|
      part['cid'] == cid
    end
  end

  def delete!
    prepare_query('DELETE FROM message').execute and
    prepare_query('DELETE FROM message_part').execute
  end

  def delete_by_owner!(owner)
    if owner.blank?
      prepare_query('DELETE FROM message WHERE owner IS NULL').execute
    else
      prepare_query('DELETE FROM message WHERE CAST(owner AS TEXT) = ?').execute(owner)
    end
  end

  def delete_message!(message_id)
    prepare_query('DELETE FROM message WHERE id = ?').execute(message_id) and
    prepare_query('DELETE FROM message_part WHERE message_id = ?').execute(message_id)
  end

  def mark_readed(id)
    prepare_query('UPDATE message SET new = 0 WHERE id = ?').execute(id)
  end

  private

  def db
    @__db ||= begin
      SQLite3::Database.new(@database_path || ':memory:', :type_translation => true).tap do |db|
        db.execute(<<-SQL)
          CREATE TABLE IF NOT EXISTS message (
            id INTEGER PRIMARY KEY ASC,
            owner TEXT DEFAULT NULL,
            sender TEXT,
            recipients TEXT,
            subject TEXT,
            source BLOB,
            size TEXT,
            type TEXT,
            new INTEGER,
            created_at DATETIME DEFAULT CURRENT_DATETIME
          )
        SQL
        db.execute(<<-SQL)
          CREATE TABLE IF NOT EXISTS message_part (
            id INTEGER PRIMARY KEY ASC,
            message_id INTEGER NOT NULL,
            cid TEXT,
            type TEXT,
            is_attachment INTEGER,
            filename TEXT,
            charset TEXT,
            body BLOB,
            size INTEGER,
            created_at DATETIME DEFAULT CURRENT_DATETIME
          )
        SQL
      end
    end
  end

  def prepare_query(sql)
    @query_cache ||= {}
    @query_cache[sql] ||= db.prepare(sql)
  end
end
