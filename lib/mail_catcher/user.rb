module MailCatcher
  class User
    attr_accessor :name, :password, :owners, :all_owners, :unassigned_owners

    def initialize
      @all_owners = false
      @unassigned_owners = false
      @owners = []
    end
  end
end
