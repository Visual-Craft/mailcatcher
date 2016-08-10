require 'mail_catcher/user'

module MailCatcher
  class Users
    attr_reader :assigned_owners

    def no_auth?
      @no_auth
    end

    def initialize(config)
      @users = []
      @no_auth = config.nil?

      return if @no_auth

      names = {}
      assigned_owners = []

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
          raise "Invalid owners for user '#{name}' at index \##{index}, it should be array"
        end

        if item[:owners].is_a?(Array)
          owners = item[:owners]
        else
          owners = [item[:owners]]
        end

        owners = owners.map(&:to_s).uniq
        all_owners = owners.include?('!all')
        unassigned_owners = owners.include?('!unassigned')
        owners = owners.reject { |a| ['!all', '!unassigned'].include?(a) }
        assigned_owners << owners

        @users << User.new.tap do |user|
          user.name = name
          user.password = password
          user.owners = owners
          user.all_owners = all_owners
          user.unassigned_owners = unassigned_owners
        end
      end

      @assigned_owners = assigned_owners.flatten.uniq

      @users
    end

    def find(name)
      @users.detect { |user| name == user.name }
    end

    def all
      @users
    end

    def allowed_owner?(user, owner)
      user && (user.all_owners || (user.unassigned_owners && !assigned_owners.include?(owner)) || user.owners.include?(owner))
    end
  end
end
