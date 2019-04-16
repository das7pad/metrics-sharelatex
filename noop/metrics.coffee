console.log("using noop")

name = "unknown"

destructors = []

require "./uv_threadpool_size"

module.exports = Metrics =
	initialize: (_name) ->
		name = _name

	registerDestructor: (func) ->
		destructors.push func

	set : (key, value, sampleRate = 1)->

	inc : (key, sampleRate = 1)->

	count : (key, count, sampleRate = 1)->

	timing: (key, timeSpan, sampleRate)->

	Timer : class
		constructor :(key, sampleRate = 1)->
		done:->
			return 42

	gauge : (key, value, sampleRate = 1)->

	globalGauge: (key, value, sampleRate = 1)->

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
