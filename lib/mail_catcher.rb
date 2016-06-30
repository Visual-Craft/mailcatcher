require 'optparse'
require 'eventmachine'
require 'thin'
require 'mail_catcher/events'
require 'mail_catcher/mail'
require 'mail_catcher/smtp'
require 'mail_catcher/web_application'
require 'mail_catcher/users'
require 'mail_catcher/config'
require 'mail_catcher/version'

module EventMachine
  # Monkey patch fix for 10deb4
  # See https://github.com/eventmachine/eventmachine/issues/569
  def self.reactor_running?
    (@reactor_running || false)
  end
end

module MailCatcher extend self
  attr_reader :config, :users, :env, :root_dir

  def run!
    @config = Config.new

    OptionParser.new do |parser|
      parser.banner = 'Usage: mailcatcher [options]'
      parser.version = MailCatcher::VERSION
      parser.on('-c FILE_PATH', '--config FILE_PATH', 'Set config') do |file_path|
        config.load_file!(file_path)
      end
      parser.on('-v', '--verbose', 'Be more verbose') do
        config[:verbose] = true
      end

      parser.on('-h', '--help', 'Display this help information') do
        puts parser
        exit
      end
    end.parse!

    config.freeze

    # If we're running in the foreground sync the output.
    $stdout.sync = $stderr.sync = true

    puts 'Starting MailCatcher'

    @users = config[:users] ? Users.new(config[:users]) : nil
    @env = (ENV['MAILCATCHER_ENV'] || 'production')
    @root_dir = File.expand_path('..', File.dirname(__FILE__))

    Thin::Logging.silent = (env != 'development')
    Smtp.parms = { :auth => :required }

    # One EventMachine loop...
    EventMachine.run do
      # Set up an SMTP server to run within EventMachine
      rescue_port config[:smtp][:port] do
        EventMachine.start_server(config[:smtp][:ip], config[:smtp][:port], Smtp)
        puts "==> smtp://#{config[:smtp][:ip]}:#{config[:smtp][:port]}"
      end

      # Let Thin set itself up inside our EventMachine loop
      # (Skinny/WebSockets just works on the inside)
      rescue_port config[:http][:port] do
        Thin::Server.start(config[:http][:ip], config[:http][:port], WebApplication)
        puts "==> http://#{config[:http][:ip]}:#{config[:http][:port]}"
      end
    end
  end

protected

  def rescue_port(port)
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
