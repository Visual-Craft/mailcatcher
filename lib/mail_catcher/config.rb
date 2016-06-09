module MailCatcher
  class Config
    attr_accessor :options

    def initialize(opts = {})
      @options = defaults.merge(permit_options(opts))
    end

    def load_file!(file_path)
      opts = permit_options(YAML::load_file(file_path))
      @options.merge!(opts) if opts
    end

    def method_missing(m, *args, &block)
      if @options.include?(m.to_sym)
        @options[m.to_sym]
      elsif m.to_s[-1, 1] == '=' && (method = m.to_s.chop.to_sym) && @options.include?(method)
        @options.send("[]=", method, *args)
      else
        raise ArgumentError.new("Method `#{m}` doesn't exist.")
      end
    end

    def respond_to?(method_name, include_private = false)
      @options.include?(method_name.to_sym) || super
    end

    private

    def defaults
      @_defaults ||= {
          smtp_ip: '127.0.0.1',
          smtp_port: '1025',
          http_ip: '127.0.0.1',
          http_port: '1080',
          verbose: false,
          password: nil,
          database_path: nil,
          users: nil,
      }
    end

    def permit_options(opts)
      opts.slice(*defaults.keys)
    end
  end
end
