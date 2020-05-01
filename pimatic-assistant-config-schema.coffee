module.exports = {
  title: "Assistant"
  type: "object"
  properties:
    token:
      description: "the NORA token"
      type: "string"
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
}
