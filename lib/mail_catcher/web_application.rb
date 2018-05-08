require 'pathname'
require 'net/http'
require 'uri'
require 'sinatra'
require 'skinny'
require 'json'
require 'mail_catcher/events'
require 'mail_catcher/mail'
require 'jwt'
require 'sinatra/cookies'

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

        helpers Sinatra::Cookies

        configure do
          helpers do
            def authorized?
              if MailCatcher.users.no_auth?
                true
              else
                !current_user.nil?
              end
            end

            def authorize!
              error(403, 'Forbidden') unless authorized?
            end

            def current_user
              if MailCatcher.users.no_auth?
                nil
              else
                MailCatcher.users.find(token['data']) if token
              end
            end

            def generate_token(user)
              if MailCatcher.users.no_auth?
                nil
              else
                JWT.encode({ data: user.name }, MailCatcher.config[:token_secret], MailCatcher.config[:token_algorithm])
              end
            end

            def token
              if MailCatcher.users.no_auth?
                return nil
              end

              begin
                key = MailCatcher.config[:token_storage_key]
                data = cookies[key] || params[key]
                JWT.decode(data, MailCatcher.config[:token_secret], MailCatcher.config[:token_algorithm]).first
              rescue
                nil
              end
            end
          end

          before do
            if %w(/api/check-auth /api/login /).include?(request.path_info)
              return
            end

            authorize!
          end
        end
      end

      @class_initialized = true
    end

    get '/' do
      send_file(File.expand_path('index.html', settings.public_folder))
    end

    post '/api/login' do
      user = MailCatcher.users.find(params[:login])

      if user && user.password == params[:pass]
        content_type 'text/plain'
        generate_token(user)
      else
        error(401, 'Unauthorized')
      end
    end

    get '/api/check-auth' do
      content_type(:json)
      JSON.generate({
        :status => authorized?,
        :no_auth => MailCatcher.users.no_auth?,
        :username => current_user.try(:name),
        :token_storage_key => MailCatcher.config[:token_storage_key],
      })
    end

    get '/api/messages' do
      content_type(:json)
      messages = Mail.messages(current_user).map { |message| message.to_short_hash }
      JSON.generate(messages)
    end

    get '/ws/messages' do
      if request.websocket?
        request.websocket!(
          :on_start => proc do |websocket|
            subscription = Events::MessageAdded.subscribe do |message|
              websocket.send_message(JSON.generate(message.to_short_hash)) if MailCatcher.users.no_auth? || MailCatcher.users.allowed_owner?(current_user, message.to_h[:owner])
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
        Mail.delete!(current_user)
      else
        Mail.delete_by_owner!(owner, current_user)
      end

      status 204
    end

    get '/api/messages/:id' do
      message = Mail.message(params[:id], current_user)

      content_type(:json)
      JSON.generate(message.to_short_hash)
    end

    get '/api/messages/:id/source' do
      message = Mail.message(params[:id], current_user)

      if params.has_key?('download')
        content_type('message/rfc822')
        attachment('message.eml')
        message.source
      else
        content_type('text/plain')
        message.source
      end
    end

    get '/api/messages/:id/part/:part_id/body' do
      message = Mail.message(params[:id], current_user)

      if message && (part = message.parts[params[:part_id].to_sym])
        content_type(part[:type], :charset => (part[:charset] || 'utf8'))
        body(part[:body])
      else
        not_found
      end
    end

    get '/api/messages/:id/attachment/:attachment_id/body' do
      message = Mail.message(params[:id], current_user)

      if message && (part = message.attachments[params[:attachment_id].to_sym])
        content_type(part[:type], :charset => (part[:charset] || 'utf8'))
        attachment(part[:filename])
        body(part[:body])
      else
        not_found
      end
    end

    post '/api/messages/:id/mark-readed' do
      Mail.mark_readed(params[:id], current_user)
    end

    delete '/api/messages/:id' do
      Mail.delete_message!(params[:id], current_user)
    end

    not_found do
      'Not Found'
    end

    error do |e|
      if e.is_a? MailCatcher::Mail::NotFoundException
        not_found
      elsif e.is_a? MailCatcher::Mail::AccessDeniedException
        error(403, 'Forbidden')
      end
    end
  end
end
