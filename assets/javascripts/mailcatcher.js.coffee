#= require modernizr
#= require jquery
#= require date
#= require flexie
#= require keymaster
#= require underscore

# Add a new jQuery selector expression which does a case-insensitive :contains
jQuery.expr[":"].icontains = (a, i, m) ->
  (a.textContent ? a.innerText ? "").toUpperCase().indexOf(m[3].toUpperCase()) >= 0

class MailCatcher
  constructor: ->
    @foldersRoot = $(".folders-wrapper ul")

    $("#messages tr").live "click", (e) =>
      e.preventDefault()
      @loadMessage $(e.currentTarget).attr("data-message-id")

    $("input[name=search]").keyup (e) =>
      query = $.trim $(e.currentTarget).val()
      if query
        @searchMessages query
      else
        @clearSearch()

    $("#message .views .format.tab a").live "click", (e) =>
      e.preventDefault()
      @loadMessageBody @selectedMessage(), $($(e.currentTarget).parent("li")).data("message-format")

    $("#message .views .delete a").live "click", (e) =>
      e.preventDefault()
      @deleteSelectedMessage()

    $("#message iframe").load =>
      @decorateMessageBody()

    $("#resizer").live
      mousedown: (e) =>
        e.preventDefault()
        $(window).bind events =
          mouseup: (e) =>
            e.preventDefault()
            $(window).unbind events
          mousemove: (e) =>
            e.preventDefault()
            @resizeTo e.clientY

    @resizeToSaved()

    $("nav.app .quit a").live "click", (e) =>
      e.preventDefault()
      if confirm "You will lose all your received messages.\n\nAre you sure you want to quit?"
        $.ajax
          type: "DELETE"
          success: ->
            location.replace $("body > header h1 a").attr("href")
          error: ->
            alert "Error while quitting."

    @foldersRoot.find("li, .clear-folder").live('click', (e) =>
      $element = $(e.target)

      unless $element.is('li')
        e.stopPropagation()
        $element = $element.closest('li')

      return if $element.is('.selected')

      if $element.data('all-owners')
        @allOwners = true
        @selectedOwner = null
      else if $element.data('no-owner')
        @allOwners = false
        @selectedOwner = null
      else if $element.data('owner')
        @allOwners = false
        @selectedOwner = $element.data('owner')
      else
        return

      @displayMessages()
    )

    @foldersRoot.find(".clear-folder").live("click", () =>
      if @allOwners
        message = 'all messages'
        owner = null
      else if @selectedOwner == null
        message = 'messages without owner'
        owner = ''
      else
        message = "messages with owner '#{@selectedOwner}'"
        owner = @selectedOwner

      if confirm("Are you sure you want to clear #{message}?")
        @deleteMessages(owner)
    )

    key "up", =>
      if @selectedMessage()
        @loadMessage $("#messages tr.selected").prev().data("message-id")
      else
        @loadMessage $("#messages tbody tr[data-message-id]:first").data("message-id")
      false

    key "down", =>
      if @selectedMessage()
        @loadMessage $("#messages tr.selected").next().data("message-id")
      else
        @loadMessage $("#messages tbody tr[data-message-id]:first").data("message-id")
      false

    key "⌘+up, ctrl+up", =>
      @loadMessage $("#messages tbody tr[data-message-id]:first").data("message-id")
      false

    key "⌘+down, ctrl+down", =>
      @loadMessage $("#messages tbody tr[data-message-id]:last").data("message-id")
      false

    key "left", =>
      @openTab @previousTab()
      false

    key "right", =>
      @openTab @nextTab()
      false

    key "delete", =>
      @deleteSelectedMessage()
      false

    @refresh()
    @subscribe()

  reset: () ->
    @messages = []
    @owners = {}
    @selectedOwner = null
    @allOwners = true

  # Only here because Safari's Date parsing *sucks*
  # We throw away the timezone, but you could use it for something...
  parseDateRegexp: /^(\d{4})[-\/\\](\d{2})[-\/\\](\d{2})(?:\s+|T)(\d{2})[:-](\d{2})[:-](\d{2})(?:([ +-]\d{2}:\d{2}|\s*\S+|Z?))?$/
  parseDate: (date) ->
    if match = @parseDateRegexp.exec(date)
      new Date match[1], match[2] - 1, match[3], match[4], match[5], match[6], 0

  offsetTimeZone: (date) ->
    offset = Date.now().getTimezoneOffset() * 60000 #convert timezone difference to milliseconds
    date.setTime(date.getTime() - offset)
    date

  formatDate: (date) ->
    date &&= @parseDate(date) if typeof(date) == "string"
    date &&= @offsetTimeZone(date)
    date &&= date.toString("dddd, d MMM yyyy h:mm:ss tt")

  tabs: ->
    $("#message ul").children(".tab")

  getTab: (i) =>
    $(@tabs()[i])

  selectedTab: =>
    @tabs().index($("#message li.tab.selected"))

  openTab: (i) =>
    @getTab(i).children("a").click()

  previousTab: (tab)=>
    i = if tab || tab is 0 then tab else @selectedTab() - 1
    i = @tabs().length - 1 if i < 0
    if @getTab(i).is(":visible")
      i
    else
      @previousTab(i - 1)

  nextTab: (tab) =>
    i = if tab then tab else @selectedTab() + 1
    i = 0 if i > @tabs().length - 1
    if @getTab(i).is(":visible")
      i
    else
      @nextTab(i + 1)

  selectedMessage: ->
    $("#messages tr.selected").data "message-id"

  searchMessages: (query) ->
    selector = (":icontains('#{token}')" for token in query.split /\s+/).join("")
    $rows = $("#messages tbody tr")
    $rows.not(selector).hide()
    $rows.filter(selector).show()

  clearSearch: ->
    $("#messages tbody tr").show()

  addMessage: (message) ->
    $("<tr />").attr("data-message-id", message.id.toString())
      .addClass(if message.new == 1 then 'new' else '')
      .append($("<td/>").text(message.sender or "No sender").toggleClass("blank", !message.sender))
      .append($("<td/>").text((message.recipients || []).join(", ") or "No receipients").toggleClass("blank", !message.recipients.length))
      .append($("<td/>").text(message.subject or "No subject").toggleClass("blank", !message.subject))
      .append($("<td/>").text(@formatDate(message.created_at)))
      .prependTo($("#messages tbody"))

  scrollToRow: (row) ->
    relativePosition = row.offset().top - $("#messages").offset().top
    if relativePosition < 0
      $("#messages").scrollTop($("#messages").scrollTop() + relativePosition - 20)
    else
      overflow = relativePosition + row.height() - $("#messages").height()
      if overflow > 0
        $("#messages").scrollTop($("#messages").scrollTop() + overflow + 20)

  unselectMessage: ->
    $("#message .metadata dd").empty()
    $("#message .metadata .attachments").hide()
    $("#message iframe").attr("src", "about:blank")
    null

  loadMessage: (id) ->
    id = id.id if id?.id?
    id ||= $("#messages tr.selected").attr "data-message-id"
    id = parseInt(id)

    if id? and not isNaN(id)
      $("#messages tbody tr:not([data-message-id='#{id}'])").removeClass("selected")
      messageRow = $("#messages tbody tr[data-message-id='#{id}']")
      messageRow.addClass("selected")
      @scrollToRow(messageRow)

      $.getJSON "/messages/#{id}.json", (message) =>
        $("#message .metadata dd.created_at").text(@formatDate message.created_at)
        $("#message .metadata dd.from").text(message.sender)
        $("#message .metadata dd.to").text((message.recipients || []).join(", "))
        $("#message .metadata dd.subject").text(message.subject)
        $("#message .views .tab.format").each (i, el) ->
          $el = $(el)
          format = $el.attr("data-message-format")
          if $.inArray(format, message.formats) >= 0
            $el.find("a").attr("href", "/messages/#{id}.#{format}")
            $el.show()
          else
            $el.hide()

        if $("#message .views .tab.selected:not(:visible)").length
          $("#message .views .tab.selected").removeClass("selected")
          $("#message .views .tab:visible:first").addClass("selected")

        if message.attachments.length
          $ul = $("<ul/>").appendTo($("#message .metadata dd.attachments").empty())

          $.each message.attachments, (i, attachment) ->
            $ul.append($("<li>").append($("<a>").attr("href", attachment["href"]).addClass(attachment["type"].split("/", 1)[0]).addClass(attachment["type"].replace("/", "-")).text(attachment["filename"])))
          $("#message .metadata .attachments").show()
        else
          $("#message .metadata .attachments").hide()

        $("#message .views .download a").attr("href", "/messages/#{id}.eml")

        @loadMessageBody()
        @markMessageReaded(id)

  deleteSelectedMessage: () ->
    id = @selectedMessage()
    if id?
      return if not confirm("Are you sure?")

      $.ajax
        url: "/messages/" + id
        type: "DELETE"
        success: =>
          @unselectMessage()
          idx = @getMessageIndex(id)
          switchTo = null

          if idx != -1
            messageRow = $("""#messages tbody tr[data-message-id="#{id}"]""")
            switchTo = messageRow.next().data("message-id") || messageRow.prev().data("message-id")
            @messages.splice(idx, 1)

          @displayMessages()

          if switchTo
            @loadMessage(switchTo)

        error: ->
          alert "Error while removing message."

  deleteMessages: (owner) ->
    if owner == null
      params = ''
    else
      params = '?' + $.param({"owner": owner})

    $.ajax
      url: "/messages#{params}"
      type: "DELETE"
      success: =>
        @unselectMessage()
        @refresh()
      error: ->
        alert "Error while clearing messages."


  # XXX: These should probably cache their iframes for the current message now we're using a remote service:

  loadMessageBody: (id, format) ->
    id ||= @selectedMessage()
    format ||= $("#message .views .tab.format.selected").attr("data-message-format")
    format ||= "html"

    $("""#message .views .tab[data-message-format="#{format}"]:not(.selected)""").addClass("selected")
    $("""#message .views .tab:not([data-message-format="#{format}"]).selected""").removeClass("selected")

    if id?
      $("#message iframe").attr("src", "/messages/#{id}.#{format}")

  decorateMessageBody: ->
    format = $("#message .views .tab.format.selected").attr("data-message-format")

    switch format
      when "html"
        body = $("#message iframe").contents().find("body")
        $("a", body).attr("target", "_blank")
      when "plain"
        message_iframe = $("#message iframe").contents()
        text = message_iframe.text()
        text = text.replace(/((http|ftp|https):\/\/[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&amp;:\/~\+#]*[\w\-\@?^=%&amp;\/~\+#])?)/g, """<a href="$1" target="_blank">$1</a>""")
        text = text.replace(/\n/g, "<br/>")
        message_iframe.find("html").html("<html><body>#{text}</html></body>")

  refresh: ->
    @reset()
    $.getJSON "/messages", (messages) =>
      $.each messages, (i, message) =>
        @addMessageData(message)
      @displayMessages()

  displayMessages: _.throttle(() ->
    $("#messages tbody").empty()
    @clearFolders()
    allCount = 0
    noOwnerCount = 0
    byOwnerCount = {}

    $.each(@messages, (i, message) =>
      allCount++

      if message.owner?
        byOwnerCount[message.owner] ||= 0
        byOwnerCount[message.owner]++
      else
        noOwnerCount++

      if @allOwners or message.owner == @selectedOwner
        @addMessage(message)
    )

    @addFolder('All', allCount, 'data-all-owners', 'true')
    @addFolder('No owner', noOwnerCount, 'data-no-owner', 'true')

    $.each(@owners, (owner) =>
      @addFolder(owner, byOwnerCount[owner], 'data-owner', owner)
    )

    @selectFolder()
  , 1000)

  clearFolders: () ->
    @foldersRoot.empty()

  selectFolder: () ->
    if @allOwners
      filter = '[data-all-owners]'
    else if @selectedOwner == null
      filter = '[data-no-owner]'
    else
      filter = "[data-owner='#{@selectedOwner}']"

    @foldersRoot.find("li#{filter}").addClass('selected')

  addFolder: (text, count, attrName, attrValue) ->
    @foldersRoot
      .append(
        $('<li class="noselect" />')
          .attr(attrName, attrValue)
          .text("#{text} (#{count})")
          .append($('<span class="clear-folder" />').text('Clear'))
      )

  subscribe: ->
    if WebSocket?
      @subscribeWebSocket()
    else
      @subscribePoll()

  subscribeWebSocket: ->
    secure = window.location.protocol is "https:"
    protocol = if secure then "wss" else "ws"
    @websocket = new WebSocket("#{protocol}://#{window.location.host}/ws/messages")
    @websocket.onmessage = (event) =>
      data = $.parseJSON(event.data)

      # handle ping, which just returns empty object
      if not $.isEmptyObject(data)
        @addMessageData(data)
        @displayMessages()

    $(window).bind('beforeunload', () =>
      @websocket.close() if @websocket
    )

  subscribePoll: ->
    unless @refreshInterval?
      @refreshInterval = setInterval (=> @refresh()), 1000

  resizeToSavedKey: "mailcatcherSeparatorHeight"

  resizeTo: (height) ->
    blockHeight = height - $(".wrapper").offset().top
    $(".folders-wrapper").css
      height: blockHeight
    $("#messages").css
      height: blockHeight + 14
    window.localStorage?.setItem(@resizeToSavedKey, height)

  resizeToSaved: ->
    height = parseInt(window.localStorage?.getItem(@resizeToSavedKey))
    unless isNaN height
      @resizeTo height

  addMessageData: (message) ->
    if (idx = @getMessageIndex(message.id)) != -1
      @messages[idx] = message
    else
      @messages.push(message)

    if message.owner
      @owners[message.owner] = true

  getMessageIndex: (id) ->
    _.findIndex(@messages, (v) -> v.id == id)

  getMessage: (id) ->
    _.find(@messages, (v) -> v.id == id)

  markMessageReaded: (id) ->
    message = @getMessage(id)

    return unless message

    row = $("""#messages tbody tr[data-message-id="#{id}"]""")

    return unless row.hasClass('new')

    $.post("/messages/#{id}/mark-readed", {}, () =>
      row.removeClass('new')
      message.new = 0
    )

$ -> window.MailCatcher = new MailCatcher
