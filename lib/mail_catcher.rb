require 'optparse'
require 'eventmachine'
require 'thin'
require 'mail_catcher/events'
require 'mail_catcher/mail'
require 'mail_catcher/smtp'
require 'mail_catcher/web'
require 'mail_catcher/users'
require 'mail_catcher/config'

module EventMachine
  # Monkey patch fix for 10deb4
  # See https://github.com/eventmachine/eventmachine/issues/569
  def self.reactor_running?
    (@reactor_running || false)
  end
end

module MailCatcher extend self
  def config
    @config
  end

  def users
    @users
  end

  def env
    @env
  end

  def run!(config)
    @config = config
    @users = @config[:users] ? Users.new(@config[:users]) : nil
    @env = ENV['MAILCATCHER_ENV'] || 'production'

    Thin::Logging.silent = (env != 'development')
    Smtp.parms = { :auth => :required }

    # One EventMachine loop...
    EventMachine.run do
      smtp_url = "smtp://#{@config[:smtp][:ip]}:#{@config[:smtp][:port]}"
      http_url = "http://#{@config[:http][:ip]}:#{@config[:http][:port]}"

      # Set up an SMTP server to run within EventMachine
      rescue_port @config[:smtp][:port] do
        EventMachine.start_server @config[:smtp][:ip], @config[:smtp][:port], Smtp
        puts "==> #{smtp_url}"
      end

      # Let Thin set itself up inside our EventMachine loop
      # (Skinny/WebSockets just works on the inside)
      rescue_port @config[:http][:port] do
        Thin::Server.start(@config[:http][:ip], @config[:http][:port], Web)
        puts "==> #{http_url}"
      end
    end
  end

protected

  def rescue_port port
    begin
      yield

    # XXX: EventMachine only spits out RuntimeError with a string description
    rescue RuntimeError
      if $!.to_s =~ /\bno acceptor\b/
        puts "~~> ERROR: Something's using port #{port}. Are you already running MailCatcher?"
        exit -1
      else
        raise
      end
    end
  end
end
