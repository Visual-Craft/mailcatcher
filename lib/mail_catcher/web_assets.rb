require "sprockets"
require "sprockets-sass"
require "compass"

module MailCatcher
  WebAssets = Sprockets::Environment.new(File.expand_path(File.expand_path('../..', File.dirname(__FILE__)))).tap do |sprockets|
    Dir["#{sprockets.root}/assets/**/*/"].each do |path|
      sprockets.append_path(path)
    end
  end
end
