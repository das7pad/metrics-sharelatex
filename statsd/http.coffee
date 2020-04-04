os = require("os")

STACKDRIVER_LOGGING = process.env['STACKDRIVER_LOGGING'] == 'true'

module.exports.monitor = (logger) ->
	return (req, res, next) ->
		Metrics = require("./metrics")
		startTime = process.hrtime()
		end = res.end
		res.end = () ->
			end.apply(this, arguments)
			responseTime = process.hrtime(startTime)
			responseTimeMs = Math.round(responseTime[0] * 1000 + responseTime[1] / 1000000)
			if req.route?.path?
				routePath = req.route.path.toString().replace(/\//g, '_').replace(/\:/g, '').slice(1)
				key = "http-requests.#{routePath}.#{req.method}.#{res.statusCode}"
				Metrics.timing(key, responseTimeMs)
				remoteIp = req.ip || req.socket?.socket?.remoteAddress || req.socket?.remoteAddress
				reqUrl = req.originalUrl || req.url
				referrer = req.headers['referer'] || req.headers['referrer']
				if STACKDRIVER_LOGGING
					info =
						httpRequest:
							requestMethod: req.method
							requestUrl: reqUrl
							requestSize: req.headers["content-length"]
							status: res.statusCode
							responseSize: res.getHeader("content-length")
							userAgent: req.headers["user-agent"]
							remoteIp: remoteIp
							referer: referrer
							latency:
								seconds: responseTime[0]
								nanos: responseTime[1]
							protocol: req.protocol
				else
					info =
						req:
							url: reqUrl
							method: req.method
							referrer: referrer
							"remote-addr": remoteIp
							"user-agent": req.headers["user-agent"]
							"content-length": req.headers["content-length"]
						res:
							"content-length": res.getHeader("content-length")
							statusCode: res.statusCode
						"response-time": responseTimeMs
				logger.info(info, "%s %s", req.method, reqUrl)
		next()
