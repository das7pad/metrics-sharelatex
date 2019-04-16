oneMegaByte = 1024 * 1024

inMegaBytes = (obj) ->
	# convert process.memoryUsage hash {rss,heapTotal,heapFreed} into megabytes
	result = {}
	for k, v of obj
		result[k] = (v / oneMegaByte).toFixed(2)
	return result

module.exports = MemoryMonitor =
	monitor: (logger) ->
		interval = setInterval () ->
			MemoryMonitor.Check(logger)
		, oneMinute
		Metrics = require "./metrics"
		Metrics.registerDestructor () ->
			clearInterval(interval)

	Check: (logger) ->
		mem = inMegaBytes process.memoryUsage()
		logger.log mem, "process.memoryUsage()"
