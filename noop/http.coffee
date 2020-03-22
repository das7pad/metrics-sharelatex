module.exports.monitor = (logger) ->
	return (req, res, next) ->
		startTime = process.hrtime()
		end = res.end
		res.end = () ->
			end.apply(this, arguments)
			responseTime = process.hrtime(startTime)
			responseTimeMs = Math.round(responseTime[0] * 1000 + responseTime[1] / 1000)
			if req.route?.path?
				remoteIp = req.ip || req.socket?.socket?.remoteAddress || req.socket?.remoteAddress
				reqUrl = req.originalUrl || req.url
				referrer = req.headers['referer'] || req.headers['referrer']
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
				if res.statusCode >= 500
					logger.error(info, "%s %s", req.method, reqUrl)
				else if res.statusCode >= 400 and res.statusCode < 500
					logger.warn(info, "%s %s", req.method, reqUrl)
				else
					logger.info(info, "%s %s", req.method, reqUrl)
		next()
