module MailCatcher
  class User
    attr_accessor :name, :password, :owners

    def restrict_owners?
      !owners.nil?
    end

    def allowed_owner?(owner)
      return true if !restrict_owners? || owner.nil?
      owners.include?(owner.to_s)
    end
  end
end
