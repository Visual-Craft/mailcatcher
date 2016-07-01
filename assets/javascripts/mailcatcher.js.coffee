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


data =
  messages : []
  selectedOwner: null
  search: ''
  selectedMessage: null

window.data = data

Vue.filter('moment', (value, format) ->
  if value
    moment(value).format(format)
  else
    ''
)

$vm = new Vue(
  el: '#mc-app'
  data: data,
  methods:
    selectMessage: (message) ->
      for k of data.messages
        data.messages[k].selected = false
      message.selected = true

      if message.new
        $.post("/api/messages/#{message.id}/mark-readed", {}, () ->
          message.new = 0
        )

    selectOwner: (owner) ->
      data.selectedOwner = owner

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
      if data.selectedOwner != null and message.owner != data.selectedOwner
        this.unselectMessageIfNeeded(message)
        return false

      search = $.trim(data.search)

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

      this.unselectMessageIfNeeded(message)

      false

    unselectMessageIfNeeded: (message) ->
      if data.selectedMessage and message.id == data.selectedMessage.id
        for k,v of this.messages
          if v.id == message.id
            v.selected = false
            return

    downloadUrl: (message) ->
      "/api/messages/#{message.id}.eml"

    contentTypeName: (type) ->
      switch type
        when 'text/plain' then 'Plain Text'
        when 'text/html' then 'HTML'
        else 'Other'


  computed:
    owners: () ->
      result = {}
      for k,v of this.messages
        if result[v.owner]
          result[v.owner]++
        else
          result[v.owner] = 1
      result

    selectedMessage: () ->
      for k,v of this.messages
        if v.selected
          return v

      null
)

$.getJSON("/api/messages", (messages) ->
  for k of messages
    messages[k].selected = false
  data.messages = messages
)

new Resizer
