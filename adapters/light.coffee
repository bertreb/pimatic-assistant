module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class LightColorAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      ###
      syncDevices: {
        "42474293.441c2c": {
          "type": "light",
          "brightnessControl": true,
          "turnOnWhenBrightnessChanges": false,
          "colorControl": false,
          "name": "Light",
          "state": {
            "online": true,
            "on": false,
            "brightness": 100,
          }
        }
      }
      ###

      @id = adapterConfig.id
      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @stateAvavailable = @device.hasAction("changeStateTo")
    
      @device.on 'state', deviceStateHandler if @stateAvavailable
      @device.on 'dimlevel', deviceDimlevelHandler
      @device.system = @

      @state =
        online: true
        on: false
        brightness: 0
      if @stateAvavailable 
        @device.getState()
        .then((state)=>
          @state.on = state
          return @device.getDimlevel()
        )
        .then((dimlevel)=>
          @state.brightness = dimlevel
          @UpdateState(@id, @state)
        )
      else
        @device.getDimlevel()
        .then((dimlevel)=>
          @state.brightness = dimlevel
          @UpdateState(@id, @state)
        )


    deviceStateHandler = (state) ->
      # device status chaged, updating device status in Nora
      @system.updateState(state)

    deviceDimlevelHandler = (dimlevel) ->
      # device status changed, updating device status in Nora
      @system.updateDimlevel(dimlevel)

    executeAction: (change) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.on = change.on
      @state.brightness = change.brightness
      @device.changeStateTo(change.on) if @stateAvavailable
      @device.changeDimlevelTo(change.brightness)

    updateState: (newState) =>
      unless newState is @state.on
        env.logger.debug "Update state to " + newState
        @state.on = newState
        @UpdateState(@id, @state)

    updateDimlevel: (newDimlevel) =>
      unless newDimlevel is @state.brightness
        env.logger.debug "Update state to " + newDimlevel
        @state.brightness = newDimlevel
        @UpdateState(@id, @state)

    getType: () ->
      return 'light'

    getState: () ->
      return @state

    setTwofa: (_twofa) =>
      @twoFa = _twofa

    getTwoFa: () =>
      _twoFa = null
      switch @twoFa
        when "ack"
          _twoFa = "ack"
        #when "pin"
        #  _twoFa["used"] = true
        #  _twoFa["method"] = "pin"
        #  _twoFa["pin"] = @twoFaPin
      return _twoFa

    destroy: ->
      
      @device.removeListener 'state', deviceStateHandler if @stateAvavailable
      @device.removeListener 'dimlevel', deviceDimlevelHandler
