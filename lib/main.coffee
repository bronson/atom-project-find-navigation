{CompositeDisposable, Range} = require 'atom'

_ = require 'underscore-plus'
{$} = require 'atom-space-pen-views'
{
  isTextEditor, decorateRange, getVisibleEditors
  getAdjacentPaneForPane, activatePaneItem
  smartScrollToBufferPosition
} = require './utils'

Config =
  hideProjectFindPanel:
    type: 'boolean'
    default: true
    description: "Hide Project Find Panel on results pane shown"
  flashDuration:
    type: 'integer'
    default: 300

module.exports =
  config: Config
  URI: 'atom://find-and-replace/project-results'

  activate: ->
    @markersByEditor = new Map

    @subscriptions = new CompositeDisposable
    @subscribe atom.commands.add 'atom-workspace',
      'project-find-navigation:activate-results-pane': => @activateResultsPaneItem()
      'project-find-navigation:next': => @confirm('next', split: false, focusResultsPane: false)
      'project-find-navigation:prev': => @confirm('prev', split: false, focusResultsPane: false)

    @subscribe atom.workspace.onWillDestroyPaneItem ({item}) =>
      @disimprove() if (item is @resultPaneView)

    @subscribe atom.workspace.onDidOpen ({uri, item}) =>
      if (not @resultPaneView?) and (uri is @URI)
        @improve(item)

        if atom.config.get('project-find-navigation.hideProjectFindPanel')
          panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
            panel.getItem().constructor.name is 'ProjectFindView'
          panel?.hide()

  subscribe: (subscription) ->
    @subscriptions.add(subscription)

  deactivate: ->
    @reset()
    @subscriptions.dispose()
    {@subscriptions, @markersByEditor} = {}

  reset: ->
    @improveSubscriptions.dispose()
    {@improveSubscriptions, @resultPaneView, @model, @resultsView} = {}

  disimprove: ->
    @clearAllDecorations()
    @reset()

  improve: (@resultPaneView) ->
    {@model, @resultsView} = @resultPaneView

    # [FIXME]
    # This dispose() shuldn't necessary but sometimes onDidFinishSearching
    # hook called multiple time.
    @improveSubscriptions?.dispose()

    @improveSubscriptions = new CompositeDisposable
    subscribe = (subscription) =>
      @improveSubscriptions.add(subscription)

    subscribe @model.onDidFinishSearching(@refreshVisibleEditors.bind(this))

    subscribe atom.workspace.onDidChangeActivePaneItem (item) =>
      @refreshVisibleEditors() if isTextEditor(item)

    @resultPaneView.addClass('project-find-navigation')

    mouseHandler = ({target, which, ctrlKey}) =>
      @resultsView.find('.selected').removeClass('selected')
      view = $(target).view()
      view.addClass('selected')

      if (which is 1) and not ctrlKey
        if view.hasClass('list-nested-item')
          # Collapse or expand tree
          view.confirm()
        else
          @confirm('here', focusResultsPane: true, split: true)
      @resultsView.renderResults()

    @resultsView.off('mousedown')
    @resultsView.on('mousedown', '.match-result, .path', mouseHandler)

    commands =
      'confirm': => @confirm('here', split: false, focusResultsPane: false)
      'confirm-and-continue': => @confirm('here', split: false, focusResultsPane: true)
      'select-next-and-confirm': => @confirm('next', split: true,  focusResultsPane: true)
      'select-prev-and-confirm': => @confirm('prev', split: true,  focusResultsPane: true)
    commandPrefix = "project-find-navigation"
    commands = _.mapObject(commands, (name, fn) -> ["#{commandPrefix}:#{name}", fn])

    subscribe atom.commands.add(@resultPaneView.element, commands)

  confirm: (where, {focusResultsPane, split}={}) ->
    return unless @resultsView?
    switch where
      when 'next' then @resultsView.selectNextResult()
      when 'prev' then @resultsView.selectPreviousResult()

    view = @resultsView.find('.selected').view()
    range = view?.match?.range
    return unless range
    range = Range.fromObject(range)

    if pane = getAdjacentPaneForPane(atom.workspace.paneForItem(@resultPaneView))
      pane.activate()
    else
      atom.workspace.getActivePane().splitRight() if split

    atom.workspace.open(view.filePath).then (editor) =>
      if focusResultsPane
        smartScrollToBufferPosition(editor, range.start)
        @activateResultsPaneItem()
      else
        editor.setCursorBufferPosition(range.start)

      @refreshVisibleEditors()
      decorateRange editor, range,
        class: 'project-find-navigation-flash'
        timeout: atom.config.get('project-find-navigation.flashDuration')

  decorateEditor: (editor) ->
    matches = @model.getResult(editor.getPath())?.matches
    return unless matches

    decorate = (editor, range) ->
      decorateRange editor, range,
        invalidate: 'inside'
        class: 'project-find-navigation-match'

    ranges = _.pluck(matches, 'range')
    markers = (decorate(editor, range) for range in ranges)
    @markersByEditor.set(editor, markers)

  activateResultsPaneItem: ->
    activatePaneItem(@resultPaneView)

  # Utility
  # -------------------------
  clearAllDecorations: ->
    @markersByEditor.forEach (markers, editor) ->
      marker.destroy() for marker in markers
    @markersByEditor.clear()

  refreshVisibleEditors: ->
    @clearAllDecorations()
    for editor in getVisibleEditors()
      @decorateEditor(editor)
