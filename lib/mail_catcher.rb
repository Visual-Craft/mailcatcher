require "optparse"
require "active_support/all"
require "eventmachine"
require "thin"

module EventMachine
  # Monkey patch fix for 10deb4
  # See https://github.com/eventmachine/eventmachine/issues/569
  def self.reactor_running?
    (@reactor_running || false)
  end
end

require "mail_catcher/events"
require "mail_catcher/mail"
require "mail_catcher/smtp"
require "mail_catcher/web"
require "mail_catcher/version"

module MailCatcher extend self
  @@defaults = {
    :smtp_ip => '127.0.0.1',
    :smtp_port => '1025',
    :http_ip => '127.0.0.1',
    :http_port => '1080',
    :verbose => false,
  }

  def options
    @@options
  end

  def parse! arguments=ARGV, defaults=@defaults
    @@defaults.dup.tap do |options|
      OptionParser.new do |parser|
        parser.banner = "Usage: mailcatcher [options]"
        parser.version = VERSION

        parser.on("--ip IP", "Set the ip address of both servers") do |ip|
          options[:smtp_ip] = options[:http_ip] = ip
        end

        parser.on("--smtp-ip IP", "Set the ip address of the smtp server") do |ip|
          options[:smtp_ip] = ip
        end

        parser.on("--smtp-port PORT", Integer, "Set the port of the smtp server") do |port|
          options[:smtp_port] = port
        end

        parser.on("--http-ip IP", "Set the ip address of the http server") do |ip|
          options[:http_ip] = ip
        end

        parser.on("--http-port PORT", Integer, "Set the port address of the http server") do |port|
          options[:http_port] = port
        end

        parser.on("--database PATH", "Set emails database path") do |path|
          Mail.database_path = path
        end

        parser.on('-p PASS', '--password PASS', 'Set password for SMTP authentication') do |password|
          options[:password] = password
        end

        parser.on('-v', '--verbose', 'Be more verbose') do
          options[:verbose] = true
        end

        parser.on('-h', '--help', 'Display this help information') do
          puts parser
          exit
        end
      end.parse!
    end
  end

  def run! options=nil
    # If we are passed options, fill in the blanks
    options &&= options.reverse_merge @@defaults
    # Otherwise, parse them from ARGV
    options ||= parse!

    # Stash them away for later
    @@options = options

    # If we're running in the foreground sync the output.
    $stdout.sync = $stderr.sync = true

    puts "Starting MailCatcher"

    Thin::Logging.silent = (ENV["MAILCATCHER_ENV"] != "development")
    Smtp.parms = { :auth => :required }

    # One EventMachine loop...
    EventMachine.run do
      smtp_url = "smtp://#{options[:smtp_ip]}:#{options[:smtp_port]}"
      http_url = "http://#{options[:http_ip]}:#{options[:http_port]}"

      # Set up an SMTP server to run within EventMachine
      rescue_port options[:smtp_port] do
        EventMachine.start_server options[:smtp_ip], options[:smtp_port], Smtp
        puts "==> #{smtp_url}"
      end

      # Let Thin set itself up inside our EventMachine loop
      # (Skinny/WebSockets just works on the inside)
      rescue_port options[:http_port] do
        Thin::Server.start(options[:http_ip], options[:http_port], Web)
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
