path = require 'path'
_ = require 'underscore-plus'
{CompositeDisposable, Emitter} = require 'event-kit'
PathWatcher = require 'pathwatcher'
NaturalSort = require 'javascript-natural-sort'
File = require './file'
{repoForPath} = require './helpers'

realpathCache = {}

module.exports =
class Folder
  constructor: ({@name, @mailFolder, @expansionState}) ->
    @emitter = new Emitter()
    @subscriptions = new CompositeDisposable()

    @expansionState ?= {}
    @expansionState.isExpanded ?= false
    @subscribeToMailFolder()

  subscribeToMailFolder: ->
    @subscriptions.add @mailFolder.onDidAddChildren (children) =>
      @reload()

    @subscriptions.add @mailFolder.onDidRemoveChildren (children) =>
      @reload()

  onDidAddEntries: (callback) ->
    @emitter.on('did-add-entries', callback)

  onDidRemoveEntries: (callback) ->
    @emitter.on('did-remove-entries', callback)

  getEntries: ->
    @sortEntries @mailFolder.getChildren()

  sortEntries: (combinedEntries) ->
    combinedEntries.sort (first, second) =>
      first.name.localeCompare(second.name)

  # Public: Perform a synchronous reload of the directory.
  reload: ->
    newEntries = []
    removedEntries = _.clone(@entries)
    index = 0

    for entry in @getEntries()
      if @entries.hasOwnProperty(entry)
        delete removedEntries[entry]
        index++
        continue

      entry.indexInParentDirectory = index
      index++
      newEntries.push(entry)

    entriesRemoved = false
    for name, entry of removedEntries
      entriesRemoved = true
      delete @entries[name]
      delete @expansionState[name]
    @emitter.emit('did-remove-entries', removedEntries) if entriesRemoved

    if newEntries.length > 0
      @entries[entry.name] = entry for entry in newEntries
      @emitter.emit('did-add-entries', newEntries)

  # Public: Collapse this directory and stop watching it.
  collapse: ->
    @expansionState.isExpanded = false
    @expansionState = @serializeExpansionState()

  # Public: Expand this directory, load its children, and start watching it for
  # changes.
  expand: ->
    @expansionState.isExpanded = true

  serializeExpansionState: ->
    expansionState = {}
    expansionState.isExpanded = @expansionState.isExpanded
    expansionState.entries = {}
    for name, entry of @entries when entry.expansionState?
      expansionState.entries[name] = entry.serializeExpansionState()
    expansionState
