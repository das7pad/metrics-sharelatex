destructors = []

require "./uv_threadpool_size"

module.exports = Metrics =
	initialize: () ->

	registerDestructor: (func) ->
		destructors.push func

	set : (key, value, sampleRate)->

	inc : (key, sampleRate)->

	count : (key, count, sampleRate)->

	timing: (key, timeSpan, sampleRate)->

	Timer : class
		constructor: (key, sampleRate)->
			this.start = new Date()
		done:->
			return new Date - this.start

	gauge : (key, value, sampleRate)->

	globalGauge: (key, value, sampleRate)->

	mongodb: require "./mongodb"
	http: require "./http"
	open_sockets: require "./open_sockets"
	event_loop: require "./event_loop"
	memory: require "./memory"

	timeAsyncMethod: require('./timeAsyncMethod')

	injectMetricsRoute: (app) ->
		app.get('/metrics', (req, res) ->
			res.send("noop")
		)

	close: () ->
		for func in destructors
			func()
