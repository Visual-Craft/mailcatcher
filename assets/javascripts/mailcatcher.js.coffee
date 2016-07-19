#= require jquery
#= require keymaster
#= require underscore
#= require moment
#= require vue

class Resizer
  constructor: (resizer, onResize) ->
    @resizer = resizer
    @onResize = onResize
    mouseEvents =
      mouseup: (e) =>
        e.preventDefault()
        $(window).unbind(mouseEvents)
      mousemove: (e) =>
        e.preventDefault()
        @resizeTo(e.clientY)

    @resizer.mousedown((e) =>
      e.preventDefault()
      $(window).bind(mouseEvents)
    )

    @resizeToSaved()

  resizeToSavedKey: "mailcatcherSeparatorHeight"

  resizeTo: (height) ->
    @onResize(height)
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

jQuery(() ->
  new Vue(
    el: '#mc-app'

    created: () ->
      this.loadMessages()
      this.subscribe()

    ready: () ->
      key "up", =>
        this.selectMessageRelative(-1)
        false

      key "down", =>
        this.selectMessageRelative(+1)
        false

      key "⌘+up, ctrl+up, home", =>
        this.selectMessageIndex(0)
        false

      key "⌘+down, ctrl+down, end", =>
        this.selectMessageIndex(-1)
        false

      key "delete", =>
        this.deleteSelectedMessage()
        false

      this.resizer = new Resizer($("#resizer"), (height) =>
        blockHeight = Math.max(height, 60) - $(".wrapper").offset().top
        $(".folders-wrapper").css(height: blockHeight)
        $("#messages").css(height: blockHeight + 14)
      )

    data:
      messages : []
      selectedOwner: null
      search: ''
      selectedMessage: null
      selectedPresentation: null

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

          this.selectedPresentation = this.presentations[0]
        else
          this.selectedPresentation = null

    methods:
      subscribe: () ->
        if WebSocket?
          return if this.websocket

          secure = window.location.protocol is "https:"
          protocol = if secure then "wss" else "ws"
          this.websocket = new WebSocket("#{protocol}://#{window.location.host}/ws/messages")
          this.websocket.onmessage = (event) =>
            message = $.parseJSON(event.data)

            # handle ping, which just returns empty object
            if not _.isEmpty(message)
              this.messages.unshift(message)

          $(window).bind('beforeunload', () =>
            if this.websocket
              this.websocket.close()
              this.websocket = null
          )
        else
          return if this.refreshInterval?

          this.refreshInterval = setInterval(() =>
            this.loadMessages()
          , 2000)

      loadMessages: () ->
        $.getJSON("/api/messages", (messages) =>
          this.messages = messages
        )

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
              this.loadMessages()
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
        "/api/messages/#{message.id}/source?download"

      presentationDisplayName: (presentation) ->
        if presentation.type == 'source'
          'Source'
        else
          switch presentation.contentType
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

      selectPresentation: (presentation) ->
        this.selectedPresentation = presentation

      isPresentationSelected: (presentation) ->
        unless this.selectedPresentation
          false
        else if this.selectedPresentation.type == presentation.type
          if this.selectedPresentation.id == null or this.selectedPresentation.id == presentation.id
            true
          else
            false

      selectedPresentationUrl: () ->
        unless this.selectedPresentation
          null
        else if this.selectedPresentation.type == 'source'
          "/api/messages/#{this.selectedMessage.id}/source"
        else
          "/api/messages/#{this.selectedMessage.id}/part/#{this.selectedPresentation.id}/body"

      hasAttachments: (message) ->
        not _.isEmpty(message.attachments)

    computed:
      folders: () ->
        result = []
        owners = {}
        totalNew = 0
        addFolder = (name, owner, count) -> result.push({ name: name, owner: owner, count: count })

        for k,v of this.messages
          if owners[v.owner]
            owners[v.owner]['total']++
          else
            owners[v.owner] = {
              'total': 1
              'new': 0
            };

          if v.new
            totalNew++
            owners[v.owner]['new']++

        addFolder('! All', null, {
          'total': this.messages.length
          'new': totalNew
        })

        unless this.messages.length
          return result

        for k,v of owners
          addFolder(k || '! No owner', k, v)

        ownersNames = _.keys(owners).sort()
        ownersPriority = {}

        for v,index in ownersNames
          ownersPriority[v] = index

        result.sort((a, b) ->
          if a.owner == null
            -1
          else if a.owner == ''
            -1
          else if a.owner == b.owner
            0
          else if ownersPriority[a.owner] < ownersPriority[b.owner]
            -1
          else
            1
        )

      presentations: () ->
        unless this.selectedMessage
          return null

        result = []
        addPresentation = (type, id = null, contentType = null) -> result.push({ type: type, id: id, contentType: contentType })

        for k,p of this.selectedMessage.parts
          addPresentation('part', p.id, p.type)

        addPresentation('source')

        result
  )
)
