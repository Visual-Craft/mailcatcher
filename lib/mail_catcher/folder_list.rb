module MailCatcher
  class FolderList
    def initialize(all_folder_name)
      @list = [
        {
          :id => '!all',
          :name => all_folder_name,
          :count => 0,
          :new => 0,
          :all => true,
        },
      ]
    end

    def add(name, count, new)
      @list.push({
        :id => name,
        :name => name,
        :count => count,
        :new => new,
        :all => false,
      })
      @list[0][:count] += count
      @list[0][:new] += new
    end

    def to_a
      @list
    end
  end
end
