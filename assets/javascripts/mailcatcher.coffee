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
    try
      window.localStorage?.setItem(@resizeToSavedKey, height)
    catch

  resizeToSaved: ->
    height = 0

    try
      height = parseInt(window.localStorage?.getItem(@resizeToSavedKey))
    catch
      height = -1

    if isNaN(height) || height <= 0
      @resizeTo(200)
    else
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
      this.checkAuth()
        .done((data) =>
          this.tokenStorageKey = data.token_storage_key
          this.noAuth = data.no_auth

          if data.status
            this.toMain(data.username)
          else
            this.toLogin()
        )

    data:
      currentComponent: null
      currentUserName: null
      noAuth: false
      tokenStorageKey: null

    methods:
      toLogin: () ->
        this.currentUserName = null
        this.currentComponent = 'mc-login'

      toMain: (username = null) ->
        this.currentUserName = username
        this.currentComponent = 'mc-main'

      checkAuth: () ->
        $.ajax
          url: "/api/check-auth"
          dataType: 'json'
          type: "GET"

      authenticate: (username, token) ->
        Cookies.set(this.tokenStorageKey, token)
        this.toMain(username)

      deAuthenticate: () ->
        Cookies.set(this.tokenStorageKey, null)
        this.toLogin()

    components:
      'mc-login':
        template: '#mc-login'

        data: () ->
          username: ''
          password: ''

        methods:
          dataFilled: () ->
            this.username != '' and this.password != ''

          loginSubmit: () ->
            if !this.dataFilled()
              return

            $.ajax
              url: "/api/login"
              data:
                login: this.username
                pass: this.password
              type: "POST"
              success: (token) =>
                this.$parent.authenticate(this.username, token)
              error: () ->
                noty({
                  text: "Invalid login or password"
                  type: 'error'
                  layout: 'bottomRight'
                  timeout: 5000
                })

      'mc-main':
        template: '#mc-main'

        created: () ->
          this.loadFolders()
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
            blockHeight = Math.max(height, 60) - $(".wrapper").offset().top / 2
            $(".folders-wrapper").css(height: blockHeight)
            $("#messages").css(height: blockHeight + 4)
          )

        data: () ->
          folders: []
          selectedFolderId: null
          messages : []
          selectedMessageId: null
          search: ''
          selectedPresentation: null
          resizer: null
          messageExpanded: null

        watch:
          'selectedFolderId': (value) ->
            if value != null and this.findFolderById(value) == null
              this.selectedFolderId = null

            this.messages = []
            this.selectedMessageId = null
            this.loadMessages()

          'messages': (messages, oldMessages) ->
            if this.selectedMessageId != null
              if messages.length == 0
                this.selectedMessageId = null
              else
                messages = _.filter(messages, this.filterMessage)
                selectedId = this.selectedMessage.id
                findById = (v) -> selectedId == v.id
                selectedFound = _.any(messages, findById)

                unless selectedFound
                  index = Math.min(_.findIndex(oldMessages, findById), messages.length - 1)

                  if index >= 0
                    this.selectedMessageId = messages[index].id
                  else
                    this.selectedMessageId = null

                if this.selectedMessage != null
                  this.scrollToRow(this.selectedMessage)

          'selectedMessageId': (value) ->
            message = null

            if value != null
              message = this.findMessageById(value)

              if message == null
                this.selectedMessageId = null

            if message != null
              this.scrollToRow(message)

              if message.new
                this.wrapAjax
                  url: "/api/messages/#{message.id}/mark-readed"
                  type: "POST"
                  success: ->
                    message.new = 0

              this.selectedPresentation = this.presentations[0]
              this.messageExpanded = false
            else
              this.selectedPresentation = null
              this.messageExpanded = null

          'messageExpanded': (value) ->
            if value == null
              return

            $(".folders-wrapper")[if value then 'slideUp' else 'slideDown'](300)
            $("#messages")[if value then 'slideUp' else 'slideDown'](300)

        methods:
          wrapAjax: (options) ->
            $.ajax(options)
              .fail((data) =>
                if data && (data.status == 403 || data.status == 401)
                  this.$parent.toLogin()

                  if data.status == 401
                    noty({
                      text: "Invalid login or password"
                      type: 'error'
                      layout: 'bottomRight'
                      timeout: 5000
                    })
                  else
                    noty({
                      text: "Access denied"
                      type: 'error'
                      layout: 'bottomRight'
                      timeout: 5000
                    })
              )

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
                  if this.acceptedMessageFolderId(message.folder)
                    this.messages.unshift(message)

                  this.loadFolders()
            else
              return if this.refreshInterval?

              this.refreshInterval = setInterval(() =>
                this.loadMessages()
              , 2000)

          loadMessages: () ->
            if this.selectedFolder == null
              return

            requestData = {}

            if !this.selectedFolder.all
              requestData['folder'] = this.selectedFolder.id

            this.wrapAjax
              url: "/api/messages"
              type: "GET"
              dataType: 'json'
              data: requestData
              success: (data) =>
                this.messages = data

          loadFolders: () ->
            this.wrapAjax
              url: "/api/folders"
              type: "GET"
              dataType: 'json'
              success: (data) =>
                this.folders = data

          toggleSelectedMessage: (message) ->
            if this.isMessageSelected(message)
              this.selectedMessageId = null
            else
              this.selectedMessageId = message.id

          selectMessageRelative: (offset) ->
            if this.selectedMessage == null
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

            this.selectedMessageId = this.messages[index].id

          isFolderSelected: (folder) ->
            this.selectedFolder != null and this.selectedFolder.id == folder.id

          acceptedMessageFolderId: (id) ->
            this.selectedFolder != null and (this.selectedFolder.all or this.selectedFolder.id == id)

          toggleSelectedFolder: (folder) ->
            if this.isFolderSelected(folder)
              this.selectedFolderId = null
            else
              this.selectedFolderId = folder.id

          clearMessages: (folder) ->
            if folder.all == null
              message = 'all messages'
            else
              message = "messages in folder '#{folder.name}'"

            if confirm("Are you sure you want to clear #{message}?")
              requestData = {}

              if !folder.all
                requestData['folder'] = folder.name

              this.wrapAjax
                url: "/api/messages"
                type: "DELETE"
                data: requestData
                success: =>
                  this.loadMessages()
                error: ->
                  alert "Error while clearing messages."

          filterMessage: (message) ->
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
            this.selectedMessage != null and this.selectedMessage.id == message.id

          deleteMessage: (message) ->
            if not confirm("Are you sure?")
              return

            this.wrapAjax
              url: "/api/messages/#{message.id}"
              type: "DELETE"
              success: =>
                this.messages = _.reject(this.messages, (v) -> v.id == message.id)
              error: ->
                alert "Error while removing message."

          deleteSelectedMessage: () ->
            this.deleteMessage(this.selectedMessage) if this.selectedMessage != null

          scrollToRow: (message) ->
            row = $("[data-message-id='#{message.id}']")

            if row.length == 0
              return

            $messages = $("#messages")
            relativePosition = row.offset().top - $messages.offset().top

            if relativePosition < 0
              $messages.scrollTop($messages.scrollTop() + relativePosition - 20)
            else
              overflow = relativePosition + row.height() - $messages.height()
              if overflow > 0
                $messages.scrollTop($messages.scrollTop() + overflow + 20)

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

          attachmentUrl: (message, attachment) ->
            "/api/messages/#{message.id}/attachment/#{attachment.id}/body"

          logout: () ->
            this.$parent.deAuthenticate()

          showLogoutButton: () ->
            !this.$parent.noAuth

          userName: () ->
            this.$parent.currentUserName

          preparePresentationContent: (event) ->
            if this.selectedPresentation && this.selectedPresentation.contentType == 'text/html'
              $(event.target).contents().find('a').attr('target','_blank')

          toggleMessageExpanded: () ->
            this.messageExpanded = !this.messageExpanded

          findFolderById: (id) ->
            for item in this.folders
              if id == item.id
                return item

            return null

          findMessageById: (id) ->
            for item in this.messages
              if id == item.id
                return item

            return null

        computed:
          presentations: () ->
            if this.selectedMessage == null
              return null

            result = []
            addPresentation = (type, id = null, contentType = null) -> result.push({ type: type, id: id, contentType: contentType })
            priorityPresentation = (item) ->
              switch item.contentType
                when 'text/html' then 0
                when 'text/plain' then 1
                when null then 3
                else 2


            for k,p of this.selectedMessage.parts
              addPresentation('part', p.id, p.type)

            addPresentation('source')

            result.sort((a, b) ->
              if priorityPresentation(a) < priorityPresentation(b)
                -1
              else if priorityPresentation(a) == priorityPresentation(b)
                0
              else
                1
            )

          filteredMessages: () ->
            _.filter(this.messages, this.filterMessage)

          selectedFolder: () ->
            if this.selectedFolderId != null
              this.findFolderById(this.selectedFolderId)
            else
              null

          selectedMessage: () ->
            if this.selectedMessageId != null
              this.findMessageById(this.selectedMessageId)
            else
              null
  )
)
