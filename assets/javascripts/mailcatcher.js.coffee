#= require modernizr
#= require jquery
#= require date
#= require favcount
#= require flexie
#= require keymaster
#= require underscore

# Add a new jQuery selector expression which does a case-insensitive :contains
jQuery.expr[":"].icontains = (a, i, m) ->
  (a.textContent ? a.innerText ? "").toUpperCase().indexOf(m[3].toUpperCase()) >= 0

class MailCatcher
  constructor: ->
    @reset()

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

    $("nav.app .clear a").live "click", (e) =>
      e.preventDefault()
      if confirm "You will lose all your received messages.\n\nAre you sure you want to clear all messages?"
        $.ajax
          url: "/messages"
          type: "DELETE"
          success: =>
            @reset()
            @unselectMessage()
            @updateMessagesCount()
          error: ->
            alert "Error while clearing all messages."

    $("nav.app .quit a").live "click", (e) =>
      e.preventDefault()
      if confirm "You will lose all your received messages.\n\nAre you sure you want to quit?"
        $.ajax
          type: "DELETE"
          success: ->
            location.replace $("body > header h1 a").attr("href")
          error: ->
            alert "Error while quitting."

    $(".folders ul li").live('click', (e) =>
      $element = $(e.target)

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

    @favcount = new Favcount($("""link[rel="icon"]""").attr("href"))

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

  messagesCount: ->
    $("#messages tr").length - 1

  updateMessagesCount: ->
    @favcount.set(@messagesCount())
    document.title = 'MailCatcher (' + @messagesCount() + ')'

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
      .append($("<td/>").text(message.sender or "No sender").toggleClass("blank", !message.sender))
      .append($("<td/>").text((message.recipients || []).join(", ") or "No receipients").toggleClass("blank", !message.recipients.length))
      .append($("<td/>").text(message.subject or "No subject").toggleClass("blank", !message.subject))
      .append($("<td/>").text(@formatDate(message.created_at)))
      .prependTo($("#messages tbody"))
    @updateMessagesCount()

  scrollToRow: (row) ->
    relativePosition = row.offset().top - $("#messages").offset().top
    if relativePosition < 0
      $("#messages").scrollTop($("#messages").scrollTop() + relativePosition - 20)
    else
      overflow = relativePosition + row.height() - $("#messages").height()
      if overflow > 0
        $("#messages").scrollTop($("#messages").scrollTop() + overflow + 20)

  unselectMessage: ->
    $("#messages tbody, #message .metadata dd").empty()
    $("#message .metadata .attachments").hide()
    $("#message iframe").attr("src", "about:blank")
    null

  loadMessage: (id) ->
    id = id.id if id?.id?
    id ||= $("#messages tr.selected").attr "data-message-id"

    if id?
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

  deleteSelectedMessage: () ->
    id = @selectedMessage()
    if id?
      return if not confirm("Are you sure?")

      $.ajax
        url: "/messages/" + id
        type: "DELETE"
        success: =>
          messageRow = $("""#messages tbody tr[data-message-id="#{id}"]""")
          switchTo = messageRow.next().data("message-id") || messageRow.prev().data("message-id")
          messageRow.remove()
          if switchTo
            @loadMessage switchTo
          else
            @unselectMessage()
          @updateMessagesCount()

        error: ->
          alert "Error while removing message."

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
    $.getJSON "/messages", (messages) =>
      $.each messages, (i, message) =>
        @addMessageData(message)
      @displayMessages()
      @updateMessagesCount()

  displayMessages: ->
    $("#messages tbody").empty()
    foldersWrapper = $(".folders-wrapper ul")
    foldersWrapper.empty()

    $.each(@messages, (i, message) =>
      if @allOwners or message.owner == @selectedOwner
        @addMessage(message)
    )

    folderTemplate = $('<li class="noselect" />')
    foldersWrapper
      .append(folderTemplate.clone().attr('data-all-owners', 'true').text('All'))
      .append(folderTemplate.clone().attr('data-no-owner', 'true').text('No owner'))

    $.each(@owners, (owner) =>
      foldersWrapper.append(folderTemplate.clone().attr("data-owner", owner).text(owner))
    )

    if @allOwners
      filter = '[data-all-owners]'
    else if @selectedOwner == null
      filter = '[data-no-owner]'
    else
      filter = "[data-owner='#{@selectedOwner}']"

    foldersWrapper.find("li#{filter}").addClass('selected')

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

$ -> window.MailCatcher = new MailCatcher
