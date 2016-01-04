Stream = require 'string-stream'
sax = require 'sax'
{tagNames} = require '../enums'

tsToSeconds = (ts) ->
	parts = ts.split(':')
	hours = parseInt(parts[0]) * 60 * 60
	minutes = parseInt(parts[1]) * 60
	seconds = parseFloat(parts[2])

	return hours + minutes + seconds

class HSReplayParser
	constructor: (@xmlReplay) ->
		@entities = {}
		@state = ['root']
		@entityDefinition = {tags: {}}
		@actionDefinition = {}
		@stack = []

	parse: (replay) ->
		@replay = replay
		@sax = sax.createStream(true)

		@sax.on 'opentag', (node) => @onOpenTag(node)
		@sax.on 'closetag', => @onCloseTag()
		@sax.on 'error', (error) =>
			console.error 'error while parsing xml', error

		#@stream = fs.createReadStream(@path).pipe(@sax)
		#console.log 'preparing to parse replay'
		@stream = new Stream(@xmlReplay).pipe(@sax)
		console.log 'replay parsed', @replay

	rootState: (node) ->
		#console.log '\tparsing node', node.name, node
		switch node.name
			when 'Game'
				@replay.start(tsToSeconds(node.attributes.ts))

			when 'Action'
				#console.log 'enqueue action from rootState', node
				if (node?.attributes?.entity == '70')
					console.log '\tDebug', node
				@replay.enqueue tsToSeconds(node.attributes.ts), 'receiveAction', node
				@state.push('action')

			when 'TagChange'
				tag = {
					entity: parseInt(node.attributes.entity)
					tag: tagNames[node.attributes.tag]
					value: parseInt(node.attributes.value)
					parent: @stack[@stack.length - 2]
				}
				if (!tag.parent.tags)
					tag.parent.tags = []
				tag.parent.tags.push(tag)

				@replay.enqueue null, 'receiveTagChange', tag

			when 'GameEntity', 'Player', 'FullEntity', 'ShowEntity'
				# console.log '\tpushing game entity to state', node
				@state.push('entity')
				@entityDefinition.id = parseInt(node.attributes.entity or node.attributes.id)
				if node.name == 'ShowEntity'
					@stack[@stack.length - 2].showEntity = @entityDefinition
					node.parent = @stack[@stack.length - 2]
				if node.attributes.cardID
					@entityDefinition.cardID = node.attributes.cardID
					#console.log 'giving name to card', node.attributes.cardID, @entityDefinition.id, @entityDefinition
				if node.attributes.name
					@entityDefinition.name = node.attributes.name

			when 'Options'
				@state.push('options')

			when 'ChosenEntities'
				@chosen =
					entity: node.attributes.entity
					playerID: node.attributes.playerID
					ts: tsToSeconds(node.attributes.ts)
					cards: []
				@state.push('chosenEntities')

	chosenEntitiesState: (node) ->
		switch node.name
			when 'Choice'
				@chosen.cards.push(node.attributes.entity)

	chosenEntitiesStateClose: (node) ->
		switch node.name
			when 'ChosenEntities'
				@state.pop()
				@replay.enqueue @chosen.ts, 'receiveChosenEntities', @chosen

	optionsStateClose: (node) ->
		switch node.name
			when 'Options'
				@state.pop()
				@replay.enqueue tsToSeconds(node.attributes.ts), 'receiveOptions', node

	entityState: (node) ->
		switch node.name
			when 'Tag'
				@entityDefinition.tags[tagNames[parseInt(node.attributes.tag)]] = parseInt(node.attributes.value)

	entityStateClose: (node) ->
		if node.attributes.ts
			ts = tsToSeconds(node.attributes.ts)
		else
			ts = null

		switch node.name
			when 'GameEntity'
				@state.pop()
				@replay.enqueue ts, 'receiveGameEntity', @entityDefinition
				@entityDefinition = {tags: {}}
			when 'Player'
				@state.pop()
				@replay.enqueue ts, 'receivePlayer', @entityDefinition
				@entityDefinition = {tags: {}}
			when 'FullEntity'
				@state.pop()
				console.log '\tclosing full entity', @entityDefinition
				@replay.enqueue ts, 'receiveEntity', @entityDefinition
				@entityDefinition = {tags: {}}
			when 'ShowEntity'
				@state.pop()
				@replay.enqueue ts, 'receiveShowEntity', @entityDefinition
				@entityDefinition = {tags: {}}

	actionState: (node) ->
		switch node.name
			when 'ShowEntity', 'FullEntity'
				@state.push('entity')
				@entityDefinition.id = parseInt(node.attributes.entity or node.attributes.id)
				@entityDefinition.parent = @stack[@stack.length - 2]

				if node.name is 'ShowEntity'
					@stack[@stack.length - 2].showEntity = @entityDefinition
				# Need that to distinguish actions that create tokens
				else 
					@stack[@stack.length - 2].fullEntity = @entityDefinition

				if node.attributes.cardID
					@entityDefinition.cardID = node.attributes.cardID
					@replay.mainPlayer @stack[@stack.length - 2].attributes.entity
					#console.log 'giving name to card', node.attributes.cardID, @entityDefinition.id, @entityDefinition
				if node.attributes.name
					@entityDefinition.name = node.attributes.name

				if @entityDefinition.id is 69
					console.log 'parsing reinforce token', @entityDefinition, node

			when 'TagChange'
				tag = {
					entity: parseInt(node.attributes.entity)
					tag: tagNames[node.attributes.tag]
					value: parseInt(node.attributes.value)
					parent: @stack[@stack.length - 2]
				}
				if (!tag.parent.tags)
					tag.parent.tags = []
				tag.parent.tags.push(tag)

				#console.log '\tparsing tagchange', @stack[@stack.length - 1], @stack[@stack.length - 2]

				@replay.enqueue null, 'receiveTagChange', tag

			when 'Action'
				#console.log 'enqueue action from actionState', node, @stack[@stack.length - 1], @stack[@stack.length - 2]
				#@stack[@stack.length - 1].parent = @stack[@stack.length - 2]
				#node.parent = @stack[@stack.length - 2]
				#console.log '\tupdated', @stack[@stack.length - 1]
				node.parent = @stack[@stack.length - 2]

				#console.log 'parsing action', node

				@state.push('action')
				@replay.enqueue tsToSeconds(node.attributes.ts), 'receiveAction', node

			when 'Choices'
				@choices =
					entity: parseInt(node.attributes.entity)
					max: node.attributes.max
					min: node.attributes.min
					playerID: node.attributes.playerID
					source: node.attributes.source
					ts: tsToSeconds(node.attributes.ts)
					cards: []
				@state.push('choices')

	choicesState: (node) ->
		switch node.name
			when 'Choice'
				@choices.cards.push(node.attributes.entity)

	choicesStateClose: (node) ->
		switch node.name
			when 'Choices'
				@state.pop()
				@replay.enqueue @choices.ts, 'receiveChoices', @choices

	actionStateClose: (node) ->
		if node.attributes.ts
			ts = tsToSeconds(node.attributes.ts)
		else
			ts = null
		switch node.name
			when 'Action'
				#console.log 'closing action state', node, @entityDefinition
				node = @state.pop()

	onOpenTag: (node) ->
		#console.log 'opening tag', node
		@stack.push(node)
		#console.log 'opening tag', node.name
		#if @stack.length > 1
		#	node.parent = @stack[@stack.length - 2]
		#	node.parent.child = node
		#method = "#{@state[@state.length-1]}State"
		#console.log 'considering node and treatment', node, method, node.attributes.ts
		@["#{@state[@state.length-1]}State"]?(node)

	onCloseTag: () ->
		node = @stack.pop()
		#console.log 'closing tag', node.name
		@["#{@state[@state.length-1]}StateClose"]?(node)


module.exports = HSReplayParser
