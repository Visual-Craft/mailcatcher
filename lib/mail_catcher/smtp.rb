require "eventmachine"

require "mail_catcher/mail"

class MailCatcher::Smtp < EventMachine::Protocols::SmtpServer
  # We override EM's mail from processing to allow multiple mail-from commands
  # per [RFC 2821](http://tools.ietf.org/html/rfc2821#section-4.1.1.2)
  def process_mail_from sender
    if @state.include? :mail_from
      @state -= [:mail_from, :rcpt, :data]
      receive_reset
    end

    super
  end

  def current_message
    @current_message ||= {}
  end

  def receive_reset
    @current_message = nil
    true
  end

  def receive_sender(sender)
    current_message[:sender] = sender
    true
  end

  def receive_recipient(recipient)
    current_message[:recipients] ||= []
    current_message[:recipients] << recipient
    true
  end

  def receive_data_chunk(lines)
    current_message[:source] ||= ""
    lines.each do |line|
      current_message[:source] << line << "\r\n"
    end
    true
  end

  def receive_plain_auth(user, password)
    user = user.to_s.strip
    @owner = user.empty? ? nil : user
    MailCatcher.config[:password].nil? || MailCatcher.config[:password] === password
  end

  def receive_message
    current_message[:owner] = @owner
    MailCatcher::Mail.add_message current_message
    puts "==> SMTP: Received message from '#{current_message[:sender]}' (#{current_message[:source].length} bytes)"
    true
  rescue Exception => e
    puts "*** Error receiving message: #{current_message.inspect}"
    puts "    Exception: #{e.class}: #{e.message}"
    puts "    Backtrace:"
    $!.backtrace.each do |line|
      puts "       #{line}"
    end
    puts "    Please submit this as an issue at http://github.com/sj26/mailcatcher/issues"
    false
  ensure
    @current_message = nil
  end

  def reset_protocol_state(keep_auth = false)
    init_protocol_state
    s,@state = @state,[]
    @state << :starttls if s.include?(:starttls)
    @state << :ehlo if s.include?(:ehlo)
    @state << :auth if s.include?(:auth) and keep_auth
    receive_transaction unless keep_auth
  end

  def process_data_line ln
    if ln == "."
      if @databuffer.length > 0
        receive_data_chunk @databuffer
        @databuffer.clear
      end


      succeeded = proc {
        send_data "250 Message accepted\r\n"
        reset_protocol_state(true)
      }
      failed = proc {
        send_data "550 Message rejected\r\n"
        reset_protocol_state(true)
      }
      d = receive_message

      if d.respond_to?(:set_deferred_status)
        d.callback(&succeeded)
        d.errback(&failed)
      else
        (d ? succeeded : failed).call
      end

      @state.delete :data
    else
      # slice off leading . if any
      ln.slice!(0...1) if ln[0] == ?.
      @databuffer << ln
      if @databuffer.length > @@parms[:chunksize]
        receive_data_chunk @databuffer
        @databuffer.clear
      end
    end
  end

  def receive_transaction
    @owner = nil
  end
end
