module MailCatcher
  class User
    attr_accessor :name, :password, :folders, :all_folders, :unassigned_folders

    def initialize
      @all_folders = false
      @unassigned_folders = false
      @folders = []
    end
  end
end
