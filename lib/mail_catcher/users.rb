require 'mail_catcher/user'

module MailCatcher
  class Users
    def initialize(config)
      @users = []
      @assigned_folders = []
      @no_auth = config.nil?

      return if @no_auth

      names = {}
      assigned_folders = []

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

        if item[:folders].nil?
          raise "Invalid folders for user '#{name}' at index \##{index}, it should be array"
        end

        if item[:folders].is_a?(Array)
          folders = item[:folders]
        else
          folders = [item[:folders]]
        end

        folders = folders.map(&:to_s).uniq
        all_folders = folders.include?('!all')
        unassigned_folders = folders.include?('!unassigned')
        folders = folders.reject { |a| ['!all', '!unassigned'].include?(a) }
        assigned_folders << folders

        @users << User.new.tap do |user|
          user.name = name
          user.password = password
          user.folders = folders
          user.all_folders = all_folders
          user.unassigned_folders = unassigned_folders
        end
      end

      @assigned_folders = assigned_folders.flatten.uniq
    end

    def find(name)
      @users.detect { |user| name == user.name }
    end

    def all
      @users
    end

    def no_auth?
      @no_auth
    end

    def assigned_folders
      @assigned_folders
    end

    def allowed_folder?(user, folder)
      if no_auth?
        return true
      end

      !user.nil? && (user.all_folders || (user.unassigned_folders && !assigned_folders.include?(folder)) || user.folders.include?(folder))
    end
  end
end
