require 'mail_catcher/utils'

module MailCatcher
  class Config < Hash
    def initialize(opts = {})
      defaults = {
        :db => {
          :host => '127.0.0.1',
          :port => 27017,
          :database => 'mailcatcher',
        },
        :smtp => {
          :ip => '127.0.0.1',
          :port => 1025,
        },
        :http => {
          :ip => '127.0.0.1',
          :port => 1080,
        },
        :verbose => false,
        :password => nil,
        :users => nil,
      }
      merge!(defaults.merge(opts))
    end

    def load_file!(file_path)
      opts = YAML::load_file(file_path)
      raise "Invalid config file '#{file_path}'" unless opts.is_a?(Hash)
      merge!(MailCatcher::Utils.symbolize_hash_keys(opts))
    end
  end
end
