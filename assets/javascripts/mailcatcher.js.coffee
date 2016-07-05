#= require jquery
#= require date
#= require keymaster
#= require underscore

class Resizer
  constructor: () ->
    mouseEvents =
      mouseup: (e) =>
        e.preventDefault()
        $(window).unbind(mouseEvents)
      mousemove: (e) =>
        e.preventDefault()
        @resizeTo(e.clientY)

    $("#resizer").live
      mousedown: (e) =>
        e.preventDefault()
        $(window).bind(mouseEvents)

    @resizeToSaved()


  resizeToSavedKey: "mailcatcherSeparatorHeight"

  resizeTo: (height) ->
    blockHeight = Math.max(height, 60) - $(".wrapper").offset().top
    $(".folders-wrapper").css(height: blockHeight)
    $("#messages").css(height: blockHeight + 14)
    window.localStorage?.setItem(@resizeToSavedKey, height)

  resizeToSaved: ->
    height = parseInt(window.localStorage?.getItem(@resizeToSavedKey))

    unless isNaN(height)
      @resizeTo(height)


Vue.filter('moment', (value, format) ->
  if value
    moment(value).format(format)
  else
    ''
)

class MailCatcher
  constructor: () ->
    @vm = new Vue(
      el: '#mc-app'

      data:
        messages : []
        selectedOwner: null
        search: ''
        selectedMessage: null
        selectedPart: null

      watch:
        'messages': (messages, oldMessages) ->
          if this.selectedMessage != null
            if messages.length == 0
              this.selectedMessage = null
            else
              selectedId = this.selectedMessage.id
              findById = (v) -> selectedId == v.id
              selectedFound = _.any(messages, findById)

              unless selectedFound
                index = Math.min(_.findIndex(oldMessages, findById), messages.length - 1)

                if index >= 0
                  this.selectedMessage = messages[index]
                else
                  this.selectedMessage = null

        'selectedMessage': (message) ->
          if message
            this.scrollToRow(message)

            if message.new
              $.post("/api/messages/#{message.id}/mark-readed", {}, () ->
                message.new = 0
              )

            this.selectedPart = message.parts[0]
          else
            this.selectedPart = null

        'selectedPart': (part) ->
          if this.selectedMessage && part
            body = $('iframe.body').contents().find("body")
            body.html(part.body);

      methods:
        selectMessage: (message) ->
          this.selectedMessage = message

        selectMessageRelative: (offset) ->
          unless this.selectedMessage
            return

          index = _.findIndex(this.messages, (v) => this.selectedMessage.id == v.id) + offset

          if index >= 0
            this.selectMessageIndex(index)

        selectMessageIndex: (index) ->
          if index >= 0
            return if index >= this.messages.length
          else
            index = this.messages.length + index
            return if index < 0

          this.selectedMessage = this.messages[index]

        selectOwner: (owner) ->
          this.selectedOwner = owner
          this.selectedMessage = null

        clearMessages: (owner) ->
          if owner == null
            message = 'all messages'
          else if owner == ''
            message = 'messages without owner'
          else
            message = "messages with owner '#{owner}'"

          if confirm("Are you sure you want to clear #{message}?")
            if owner == null
              params = ''
            else
              params = '?' + $.param({"owner": owner})

            $.ajax
              url: "/api/messages#{params}"
              type: "DELETE"
              success: =>

              error: ->
                alert "Error while clearing messages."

        filterMessage: (message) ->
          if this.selectedOwner != null and message.owner != this.selectedOwner
            return false

          search = $.trim(this.search)

          if search == ''
            return true

          sources = []
          sources.push(message.subject) if message.subject
          sources.push(message.sender) if message.sender
          sources.push(message.recipients.join(', ')) if message.recipients and message.recipients.length

          for part in message.parts
            sources.push(part.body) if part.body

          search = search.toUpperCase().split(/\s+/)

          for source in sources
            for searchItem in search
              if source.toUpperCase().indexOf(searchItem) >= 0
                return true

          false

        downloadUrl: (message) ->
          "/api/messages/#{message.id}.eml"

        contentTypeName: (type) ->
          switch type
            when 'text/plain' then 'Plain Text'
            when 'text/html' then 'HTML'
            else 'Other'

        isMessageSelected: (message) ->
          this.selectedMessage and this.selectedMessage.id == message.id

        deleteMessage: (message) ->
          if not confirm("Are you sure?")
            return

          $.ajax
            url: "/api/messages/#{message.id}"
            type: "DELETE"
            success: =>
              this.messages = _.reject(this.messages, (v) -> v.id == message.id)

            error: ->
              alert "Error while removing message."

        deleteSelectedMessage: () ->
          this.deleteMessage(this.selectedMessage) if this.selectedMessage

        scrollToRow: (message) ->
          row = $("[data-message-id='#{message.id}']")
          relativePosition = row.offset().top - $("#messages").offset().top

          if relativePosition < 0
            $("#messages").scrollTop($("#messages").scrollTop() + relativePosition - 20)
          else
            overflow = relativePosition + row.height() - $("#messages").height()
            if overflow > 0
              $("#messages").scrollTop($("#messages").scrollTop() + overflow + 20)

        selectPart: (part) ->
          this.selectedPart = part

        isPartSelected: (part) ->
          this.selectedPart and this.selectedPart.type == part.type

      computed:
        owners: () ->
          result = {}
          for k,v of this.messages
            if result[v.owner]
              result[v.owner]++
            else
              result[v.owner] = 1
          result
    )

    key "up", =>
      @vm.selectMessageRelative(-1)
      false

    key "down", =>
      @vm.selectMessageRelative(+1)
      false

    key "⌘+up, ctrl+up, home", =>
      @vm.selectMessageIndex(0)
      false

    key "⌘+down, ctrl+down, end", =>
      @vm.selectMessageIndex(-1)
      false

    key "delete", =>
      @vm.deleteSelectedMessage()
      false

  loadMessages: () ->
    $.getJSON("/api/messages", (messages) =>
      @vm.$set('messages', messages)
    )

  subscribe: () ->
    if WebSocket?
      return if @websocket?

      secure = window.location.protocol is "https:"
      protocol = if secure then "wss" else "ws"
      @websocket = new WebSocket("#{protocol}://#{window.location.host}/ws/messages")
      @websocket.onmessage = (event) =>
        message = $.parseJSON(event.data)

        # handle ping, which just returns empty object
        if not $.isEmptyObject(message)
          @vm.$get('messages').push(message)

      $(window).bind('beforeunload', () =>
        if @websocket
          @websocket.close()
          @websocket = null
      )
    else
      return if @refreshInterval?

      @refreshInterval = setInterval(() =>
        @loadMessages()
      , 2000)


jQuery(() ->
  new Resizer

  m = new MailCatcher()
  m.loadMessages()
  m.subscribe()
)
