module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class SwitchAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      ###
      syncDevices: {
        "42474293.441c2c": {
          "type": "switch",
          "name": "Switch",
          "state": {
            "online": true,
            "on": false,
          }
          "twoFactor": "ack|pin"
          "pin": "12345"
        }
      }
      ###

      @id = adapterConfig.id
      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @device.on "state", deviceStateHandler
      @device.system = @
      @state =
        online: true
        on: false

      @device.getState()
      .then((state)=>
        @state.on = state
        @UpdateState(@id, @state)
      )

    deviceStateHandler = (state) ->
      # device status changed, updating device status in Nora
      @system.updateState(state)

    executeAction: (change) ->
      # device status changed, updating device status in Nora
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.on = change.on
      @device.changeStateTo(change.on)

    updateState: (newState) =>
      unless newState is @state.on
        env.logger.debug "Update state to " + newState
        @state.on = newState
        @UpdateState(@id, @state)

    getType: () ->
      return "switch"

    getState: () ->
      return @state

    destroy: ->
      @device.removeListener "state", deviceStateHandler
