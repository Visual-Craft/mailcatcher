require 'mail_catcher/user'

module MailCatcher
  class Users
    def initialize(config)
      @users = []
      config.each do |item|
        @users << User.new.tap do |user|
          raise 'Invalid user in config' if item['name'].blank?
          raise "Duplicate user name #{item['name']} in config" if find_by_name(item['name'].to_s)

          user.name = item['name'].to_s
          user.password = item['password'].to_s
          user.owners = item['owners'] ? [item['owners']].flatten.reject(&:empty?).map(&:to_s) : nil
        end
      end
    end

    def find_by_name(name)
      @users.detect { |user| name == user.name }
    end

    def all
      @users
    end

    def exists?
      @users.present?
    end
  end
end
