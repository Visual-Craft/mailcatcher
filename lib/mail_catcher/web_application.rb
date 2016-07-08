require 'pathname'
require 'net/http'
require 'uri'
require 'sinatra'
require 'skinny'
require 'json'
require 'mail_catcher/events'
require 'mail_catcher/mail'

class Sinatra::Request
  include Skinny::Helpers
end

module MailCatcher
  class WebApplication < Sinatra::Base
    def initialize(app = nil)
      @class_initialized || initialize_class
      super(app)
    end

    def initialize_class
      self.class.class_eval do
        set :environment, MailCatcher.env
        set :root, MailCatcher.root_dir

        configure do
          helpers do
            def javascript_tag(name)
              %{<script src="/assets/#{name}.js"></script>}
            end

            def stylesheet_tag(name)
              %{<link rel="stylesheet" href="/assets/#{name}.css">}
            end
          end
        end

        configure :development do
          require 'sprockets'
          require 'sprockets-sass'
          require 'compass'
          require 'sprockets-helpers'

          assets_env = Sprockets::Environment.new(File.expand_path('assets', MailCatcher.root_dir)).tap do |sprockets|
            Dir["#{sprockets.root}/**/*/"].each do |path|
              sprockets.append_path(path)
            end
          end
          assets_prefix = 'assets_dev'

          Sprockets::Helpers.configure do |config|
            config.environment = assets_env
            config.prefix      = "/#{assets_prefix}"
            config.digest      = false
            config.public_path = public_folder
            config.debug       = true
          end

          helpers(Sprockets::Helpers)

          get "/#{assets_prefix}/*" do
            sub_env = env.clone
            %w(REQUEST_PATH PATH_INFO REQUEST_URI).each do |k|
              sub_env[k] = sub_env[k].gsub(/\A\/#{assets_prefix}\//, '/')
            end
            assets_env.call(sub_env)
          end
        end
      end

      @class_initialized = true
    end

    get '/' do
      erb :index
    end

    get '/api/messages' do
      content_type :json
      messages = Mail.messages.map do |message|
        hash = message.to_h
        hash[:source] = nil
        hash[:parts].each { |_,v| v[:body] = nil }
        hash[:attachments].each { |_,v| v[:body] = nil }
        hash
      end

      JSON.generate(messages)
    end

    get '/ws/messages' do
      if request.websocket?
        request.websocket!(
          :on_start => proc do |websocket|
            subscription = Events::MessageAdded.subscribe do |message|
              websocket.send_message(JSON.generate(message.to_h))
            end

            # send ping responses to correctly work with forward proxies
            # which may close inactive connections after timeout
            # for example nginx by default closes connection after 60 seconds of inactivity
            timer = EventMachine::PeriodicTimer.new(30) do
              websocket.send_message('{}')
            end

            websocket.on_close do
              timer.cancel
              Events::MessageAdded.unsubscribe subscription
            end
          end
        )
      else
        status 400
      end
    end

    delete '/api/messages' do
      owner = params[:owner]

      if owner.nil?
        Mail.delete!
      else
        Mail.delete_by_owner!(owner)
      end

      status 204
    end

    get '/api/messages/:id' do
      message = Mail.message(params[:id])

      if message
        content_type :json
        JSON.generate(message.to_h)
      else
        not_found
      end
    end

    get '/api/messages/:id.eml' do
      message = Mail.message(params[:id])

      if message
        content_type 'message/rfc822'
        message.source
      else
        not_found
      end
    end

    get '/api/messages/:id/source' do
      message = Mail.message(params[:id])

      if message
        content_type('text/plain')
        message.source
      else
        not_found
      end
    end

    get '/api/messages/:id/part/:part_id/body' do
      message = Mail.message(params[:id])

      if message && (part = message.parts[params[:part_id].to_sym])
        content_type(part[:type], :charset => (part[:charset] || 'utf8'))
        body(part[:body])
      else
        not_found
      end
    end

    get '/api/messages/:id/attachment/:attachment_id/body' do
      message = Mail.message(params[:id])

      if message && (part = message.attachments[params[:attachment_id].to_sym])
        content_type(part[:type], :charset => (part[:charset] || 'utf8'))
        attachment(part[:filename])
        body(part[:body])
      else
        not_found
      end
    end

    post '/api/messages/:id/mark-readed' do
      if Mail.mark_readed(params[:id])
        status 204
      else
        not_found
      end
    end

    delete '/api/messages/:id' do
      if Mail.delete_message!(params[:id])
        status 204
      else
        not_found
      end
    end

    not_found do
      'Not Found'
    end
  end
end
