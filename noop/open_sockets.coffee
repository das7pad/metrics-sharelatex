require("http").globalAgent.maxSockets = Infinity
require("https").globalAgent.maxSockets = Infinity

module.exports = OpenSocketsMonitor =
	monitor: (logger) ->

	gaugeOpenSockets: () ->
