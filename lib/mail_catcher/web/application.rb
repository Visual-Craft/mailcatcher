require "pathname"
require "net/http"
require "uri"

require "sinatra"
require "skinny"
require 'json'

require "mail_catcher/events"
require "mail_catcher/mail"

class Sinatra::Request
  include Skinny::Helpers
end

module MailCatcher
  module Web
    class Application < Sinatra::Base
      set :development, ENV["MAILCATCHER_ENV"] == "development"
      set :root, File.expand_path("#{__FILE__}/../../../..")

      if development?
        require "sprockets-helpers"

        configure do
          require "mail_catcher/web/assets"
          Sprockets::Helpers.configure do |config|
            config.environment = Assets
            config.prefix      = "/assets"
            config.digest      = false
            config.public_path = public_folder
            config.debug       = true
          end
        end

        helpers do
          include Sprockets::Helpers
        end
      else
        helpers do
          def javascript_tag(name)
            %{<script src="/assets/#{name}.js"></script>}
          end

          def stylesheet_tag(name)
            %{<link rel="stylesheet" href="/assets/#{name}.css">}
          end
        end
      end

      get "/" do
        erb :index
      end

      get "/messages" do
        content_type :json
        messages = Mail.messages.map { |v| v.to_h }
        JSON.generate(messages)
      end

      get "/ws/messages" do
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

              websocket.on_close do |websocket|
                timer.cancel
                Events::MessageAdded.unsubscribe subscription
              end
            end
          )
        else
          status 400
        end
      end

      delete "/messages" do
        owner = params[:owner]

        if owner.nil?
          Mail.delete!
        else
          Mail.delete_by_owner!(owner)
        end

        status 204
      end

      get "/messages/:id.json" do
        if message = Mail.message(params[:id])
          content_type :json
          hash = message.to_h
          hash[:formats] = ['source']
          hash[:formats] << 'html' if message.has_html?
          hash[:formats] << 'plain' if message.has_plain?
          hash[:attachments].map! do |attachment|
            attachment.merge({ "href" => "/messages/#{escape(message.id)}/parts/#{escape(attachment[:cid])}" })
          end
          JSON.generate(hash)
        else
          not_found
        end
      end

      get "/messages/:id.html" do
        message = Mail.message(params[:id])
        if message && message.has_html?
          content_type message.html_part[:type], :charset => (message.html_part[:charset] || "utf8")

          body = message.html_part[:body]

          # Rewrite body to link to embedded attachments served by cid
          body.gsub! /cid:([^'"> ]+)/, "#{message.id}/parts/\\1"

          content_type :html
          body
        else
          not_found
        end
      end

      get "/messages/:id.plain" do
        message = Mail.message(params[:id])
        if message && message.has_plain?
          content_type message.plain_part[:type], :charset => (message.plain_part[:charset] || "utf8")
          message.plain_part[:body]
        else
          not_found
        end
      end

      get "/messages/:id.source" do
        if message = Mail.message(params[:id])
          content_type "text/plain"
          message.source
        else
          not_found
        end
      end

      get "/messages/:id.eml" do
        if message = Mail.message(params[:id])
          content_type "message/rfc822"
          message.source
        else
          not_found
        end
      end

      get "/messages/:id/parts/:cid" do
        message = Mail.message(params[:id])
        if message && (part = message.cid_part(params[:cid]))
          content_type part[:type], :charset => (part[:charset] || "utf8")
          attachment part[:filename] if part[:is_attachment] == 1
          body part[:body].to_s
        else
          not_found
        end
      end

      get "/messages/:id/analysis.?:format?" do
        message = Mail.message(params[:id])
        if message && message.has_html?
          # TODO: Server-side cache? Make the browser cache based on message create time? Hmm.
          uri = URI.parse("http://api.getfractal.com/api/v2/validate#{"/format/#{params[:format]}" if params[:format].present?}")
          response = Net::HTTP.post_form(uri, :api_key => "5c463877265251386f516f7428", :html => message.html_part[:body])
          content_type ".#{params[:format]}" if params[:format].present?
          body response.body
        else
          not_found
        end
      end

      post '/messages/:id/mark-readed' do
        if Mail.mark_readed(params[:id])
          status 204
        else
          not_found
        end
      end

      delete "/messages/:id" do
        if Mail.delete_message!(params[:id])
          status 204
        else
          not_found
        end
      end

      not_found do
        erb :"404"
      end
    end
  end
end
