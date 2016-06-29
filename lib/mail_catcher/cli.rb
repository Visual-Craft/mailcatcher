require 'mail_catcher'
require 'mail_catcher/config'

module MailCatcher
  module Cli extend self
    def run!
      config = Config.new
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

      # If we're running in the foreground sync the output.
      $stdout.sync = $stderr.sync = true

      puts 'Starting MailCatcher'
      MailCatcher.run!(config.freeze)
    end
  end
end
