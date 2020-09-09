module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class ButtonAdapter extends events.EventEmitter

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
        }
      }
      ###

      @id = adapterConfig.id
      env.logger.debug "Button created id: " + @id
      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @device.system = @

      @device.on "button", buttonHandler = (buttonId) =>
        #env.logger.debug "Pushed button ButtonId: " + buttonId
        #if buttonId is @subDeviceId
        @updateState(buttonId)

      @state =
        online: true
        on: false

      @device.getButton()
      .then((buttonId)=>
        if buttonId is @subDeviceId
          @state.on = true
          @UpdateState(@id, @state)
      )

    #buttonHandler = (buttonId) ->
    #  # device status changed, updating device status in Nora
    #  if buttonId is @device.system.subDeviceId
    #    @system.updateState(buttonId)

    executeAction: (change) ->
      # device status changed, updating device status in Nora
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.on = change.on
      if change.on
        @device.buttonPressed(@subDeviceId).then(() =>
          env.logger.debug "Button '" + @subDeviceId + "' pressed"       
        ).catch((err) =>
          env.logger.error "error: " + err
        )

    updateState: (buttonId) =>
      #unless newState is @state.on
      #env.logger.debug "ButtonId: " + buttonId + ", @subDeviceId: " + @subDeviceId
      if buttonId is @subDeviceId
        @state.on = true
        @UpdateState(@id, @state)
        env.logger.debug "Switch on " + @id
      else
        @state.on = false
        @UpdateState(@id, @state)
        env.logger.debug "Switch off " + @id
      #@state.on = newState
      #@UpdateState(@id, @state)

    getType: () ->
      return "switch"

    getState: () ->
      return @state

    destroy: ->
      @state.online = false;
      @updateState(@state)
      #@device.removeListener "button", buttonHandler
