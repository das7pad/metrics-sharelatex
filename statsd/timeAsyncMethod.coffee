
module.exports = (obj, methodName, prefix, logger) ->
	metrics = require('./metrics')

	if typeof obj[methodName] != 'function'
		throw new Error("[Metrics] expected object property '#{methodName}' to be a function")

	realMethod = obj[methodName]
	key = "#{prefix}.#{methodName}"

	obj[methodName] = (originalArgs...) ->

		[firstArgs..., callback] = originalArgs

		if !callback? || typeof callback != 'function'
			if logger?
				logger.log "[Metrics] expected wrapped method '#{methodName}' to be invoked with a callback"
			return realMethod.apply this, originalArgs

		timer = new metrics.Timer(key)

		realMethod.call this, firstArgs..., (callbackArgs...) ->
			elapsedTime = timer.done()
			possibleError = callbackArgs[0]
			if possibleError? 
				metrics.inc "#{key}.failure"
			else
				metrics.inc "#{key}.success"
			if logger?
				loggableArgs = {}
				try
					for arg, idx in firstArgs
						if arg.toString().match(/^[0-9a-f]{24}$/)
							loggableArgs["#{idx}"] = arg
				logger.log {key, args: loggableArgs, elapsedTime}, "[Metrics] timed async method call"
			callback.apply this, callbackArgs
