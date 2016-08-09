require 'mail_catcher/user'

module MailCatcher
  class Users
    def no_auth?
      @no_auth
    end

    def initialize(config)
      @users = []
      @no_auth = config.nil?

      return if @no_auth

      names = {}

      unless config.is_a?(Array) && !config.empty?
        raise 'Invalid users configuration, it should be array of users and have at least one element'
      end

      config.each_with_index do |item, index|
        name = item[:name].to_s
        password = item[:password].to_s
        raise "Missing name for user at index \##{index}" if name.empty?
        raise "Duplicate user name '#{name}' at index \##{index}" if names.has_key?(name)
        raise "Missing password for user '#{name}' at index \##{index}" if password.empty?
        names[name] = true

        if item[:owners].nil?
          owners = nil
        elsif item[:owners].is_a?(Array)
          owners = item[:owners].map(&:to_s).uniq
        else
          raise "Invalid owners for user '#{name}' at index \##{index}, it should be nil or array"
        end

        @users << User.new.tap do |user|
          user.name = name
          user.password = password
          user.owners = owners
        end
      end
    end

    def find(name)
      @users.detect { |user| name == user.name }
    end

    def all
      @users
    end
  end
end
