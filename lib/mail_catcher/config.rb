module MailCatcher
  class Config
    attr_accessor :options

    def initialize(opts = {})
      @options = defaults.deep_merge(opts)
    end

    def load_file!(file_path)
      opts = YAML::load_file(file_path)
      @options.deep_merge!(opts) if opts
    end

    def verbose=(val)
      @options[:verbose] = !!val
    end

    private

    def defaults
      @defaults ||= {
        :db => {
          :host => '127.0.0.1',
          :port => 27017,
          :name => 'mailcatcher',
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
    end
  end
end
