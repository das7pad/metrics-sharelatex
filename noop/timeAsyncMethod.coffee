module.exports = (obj, methodName, prefix, logger) ->
  if typeof obj[methodName] != 'function'
    throw new Error("[Metrics] expected object property '#{methodName}' to be a function")
