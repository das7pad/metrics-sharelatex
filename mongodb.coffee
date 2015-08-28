# Aim: record the time taken for mongo queries in the client
#
# We have several drivers and wrappers to deal with
#
# 1) the original 'mongodb' (1.x series)
#
#  This has 4 methods _execute{Query,Remove,Insert,Update}Command() on
#  the Db.prototype which can be wrapped in a timer.
#
# 2) the new 'mongodb' (2.x series) which uses the 'mongodb-core' driver
#
#  The mongodb-core driver is found in the directory
#  node_modules/mongodb/node_modules/mongodb-core
#
#  There are two levels where we could wrap functions, in mongodb itself or
#  in mongodb-core driver.
#
#  The relevant functions in mongodb would be collection.js
#
#    - Collection.prototype.find()
#    - Collection.prototype.insertOne()
#    - Collection.prototype.insertMany()
#    - Collection.prototype.insert()
#    - ...
#
#  but there are about 50 of these functions and, unlike in the 1.x
#  series, the simpler functions that they go through are not publicly
#  exported.
#
#  Therefore we have to look deeper to wrap functions in mongodb-core,
#  which are publicly exported and called by the mongodb collection.js
#  methods.
#
#  The mongodb Collection.prototype functions call methods like
#
#    self.s.topology.insert(namespace, docs, finalOptions, callback)
#
#  which are defined in mongodb-core for each topology: "server",
#  "replset" and "mongos".
#
#  Taking "server" as an example we find four functions with callbacks
#  that we can wrap:
#
#  mongodb-core/lib/topologies/server.js:
#    Server.prototype.command = function(ns, cmd, options, callback) ...
#    Server.prototype.insert = function(ns, ops, options, callback) ...
#    Server.prototype.update = function(ns, ops, options, callback) ...
#    Server.prototype.remove = function(ns, ops, options, callback) ...
#
#  These are the functions we can wrap! However, these do not include
#  queries that return a cursor.  To catch those we wrap the function
#  which returns a cursor
#
#  mongodb-core/lib/topologies/server.js:
#    Server.prototype.cursor = function(ns, cmd, cursorOptions) ...
#
#  and capture the returned cursor, modifying its .next() method to
#  return the time to the first result, then restoring the original
#  .next() method for further results.
#
# 3) mongojs (0.x)
#
#  Uses the mongodb v1 driver
#
# 4) mongojs (1.x)
#
#  Uses the mongodb-core driver directly, it does not use the
#  higher-level mongodb package.
#
# 5) mongoose (3.x)
#
#  Uses the mongodb v1 driver
#
# 6) mongoose (4.x)
#
#  Uses the higher-level mongodb 2.x package, which in turn uses
#  mongodb-core.

module.exports =
	monitor: (mongodb_require_path, logger) ->

		try
			# for the v1 driver the methods to wrap are in the mongodb
			# module in lib/mongodb/db.js
			mongodb = require("#{mongodb_require_path}")
			logger.log {mongodb_require_path}, "loaded mongodb in metrics"

		try
			# for the v2 driver the relevant methods are in the mongodb-core
			# module in lib/topologies/{server,replset,mongos}.js
			v2_path = mongodb_require_path.replace(/\/mongodb$/, '/mongodb-core')
			mongodbCore = require(v2_path)
			logger.log {mongodb_require_path, v2_path}, "loaded mongodb-core in metrics"

		try
			v2_path = mongodb_require_path.replace(/\/mongodb$/, '/mongodb/node_modules/mongodb-core')
			mongodbCore = require(v2_path)
			logger.log {mongodb_require_path, v2_path}, "loaded mongodb-core (from subdir) in metrics"

		Metrics = require("./metrics")

		monitorMethod = (base, method, type, version) ->
			return unless base?
			return unless (_method = base[method])?

			mongo_driver_v1 = (db_command, options, callback) ->
				if (typeof callback == 'undefined')
					callback = options
					options = {}
				collection = db_command.collectionName
				if collection.match(/\$cmd$/)
					# Ignore noisy command methods like authenticating, ismaster and ping
					return _method.call this, db_command, options, callback
				key = "mongo-requests.#{collection}.#{type}"
				if db_command.query?
					query = Object.keys(db_command.query).sort().join("_")
					key += "." + query
				timer = new Metrics.Timer(key)
				start = new Date()
				_method.call this, db_command, options, () ->
					timer.done()
					time = new Date() - start
					logger.log
						query: db_command.query
						query_type: type
						collection: collection
						"response-time": new Date() - start
						"mongo request"
					callback.apply this, arguments

			# general timer for mongo functions with callback as final argument
			timeCallback = (params, method, self, args...) ->
				key = "mongo-requests.#{params.collection}.#{params.query_type}"
				if params.query?
					key += "." + Object.keys(params.query).sort().join("_")
				timer = new Metrics.Timer(key)
				start = new Date()
				cb = args[args.length-1]
				newcb = () ->
					timer.done()
					time = new Date() - start
					params["response-time"] = time
					logger.log params, "mongo request"
					cb.apply this, arguments
				args[args.length-1] = newcb
				method.apply self, args

			mongo_driver_v2 = (ns, ops, options, callback) ->
				if (typeof callback == 'undefined')
					callback = options
					options = {}
				if ns.match(/\$cmd$/)
					# Ignore noisy command methods like authenticating, ismaster and ping
					#console.log 'ignoring noisy command'
					return _method.call this, ns, ops, options, callback
				else
					timeCallback {query: ops[0].q, query_type: type, collection: ns}, _method, this, ns, ops, options, callback

			mongo_driver_v2_mongodb_find = (callback) ->
				if typeof callback != "function"
					return _method.apply this, arguments
				else
					timeCallback {query: this.cmd.query, query_type: type, collection: this.ns}, _method, this, callback

			mongo_driver_v2_mongodb_cursor = (ns, cms, cursorOptions) ->
				# start the timer when we create the cursor
				key = "mongo-requests.#{ns}.#{type}"
				if cms.query?
					key += "." + Object.keys(cms.query).sort().join("_")
				timer = new Metrics.Timer(key)
				start = new Date()
				cursor = _method.apply this, arguments
				# now override the cursor.next() method to measure the
				# time to the first result
				_next = cursor.next
				cursor.next = (callback) ->
					cb = () ->
						cursor.next = _next # restore the original next method
						timer.done()
						time = new Date() - start
						params = {query: cms.query, query_type: type, collection: ns}
						params["response-time"] = time
						logger.log params, "mongo request cursor"
						callback(arguments) # execute the user callback
					_next.call this, cb
				return cursor # remember we need to return the cursor!

			switch version
				when "v1" then base[method] = mongo_driver_v1
				when "v2" then base[method] = mongo_driver_v2
				when "v2:find" then base[method] = mongo_driver_v2_mongodb_find
				when "v2:cursor" then base[method] = mongo_driver_v2_mongodb_cursor
				else logger.err {version}, "unknown mongo version"

			if _method.length != base[method].length
				logger.err {originalSignature: _method.length, newSignature: _base[method].length}, "mismatch in mongo metrics wrapping"
				thow new Error("cannot inject mongo metrics")

		monitorMethod(mongodb?.Db.prototype, "_executeQueryCommand",  "query", "v1")
		monitorMethod(mongodb?.Db.prototype, "_executeRemoveCommand", "remove", "v1")
		monitorMethod(mongodb?.Db.prototype, "_executeInsertCommand", "insert", "v1")
		monitorMethod(mongodb?.Db.prototype, "_executeUpdateCommand", "update", "v1")

		monitorMethod(mongodbCore?.Server.prototype, "command", "command", "v2")
		monitorMethod(mongodbCore?.Server.prototype, "remove", "remove", "v2")
		monitorMethod(mongodbCore?.Server.prototype, "insert", "insert", "v2")
		monitorMethod(mongodbCore?.Server.prototype, "update", "update", "v2")
		monitorMethod(mongodbCore?.Server.prototype, "cursor", "query", "v2:cursor")

		monitorMethod(mongodbCore?.ReplSet.prototype, "command", "command", "v2")
		monitorMethod(mongodbCore?.ReplSet.prototype, "remove", "remove", "v2")
		monitorMethod(mongodbCore?.ReplSet.prototype, "insert", "insert", "v2")
		monitorMethod(mongodbCore?.ReplSet.prototype, "update", "update", "v2")
		monitorMethod(mongodbCore?.ReplSet.prototype, "cursor", "query", "v2:cursor")

		monitorMethod(mongodbCore?.Mongos.prototype, "command", "command", "v2")
		monitorMethod(mongodbCore?.Mongos.prototype, "remove", "remove", "v2")
		monitorMethod(mongodbCore?.Mongos.prototype, "insert", "insert", "v2")
		monitorMethod(mongodbCore?.Mongos.prototype, "update", "update", "v2")
		monitorMethod(mongodbCore?.Mongos.prototype, "cursor", "query", "v2:cursor")
