module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  Chroma = require 'chroma-js'

  class LightColorMilightAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      ###
      syncDevices: {
        "42474293.441c2c": {
          "type": "light",
          "brightnessControl": true,
          "turnOnWhenBrightnessChanges": false,
          "colorControl": true,
          "name": "Light",
          "state": {
            "online": true,
            "on": false,
            "brightness": 100,
            "color": {
              "spectrumHsv": {
                "hue": 0,
                "saturation": 0,
                "value": 1
              }
            }
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
      #env.logger.info "HasAction state " + @stateAvavailable 

      @device.on 'state', deviceStateHandler if @stateAvavailable
      @device.on 'dimlevel', deviceDimlevelHandler
      @device.on 'hue', deviceHueHandler #(0-254 color, 255 is white)
      @device.system = @

      @state =
        online: true
        on: false
        brightness: 0
        color:
          spectrumHsv:
            hue: 0
            saturation: 0
            value: 1

      #@publishState()

    deviceStateHandler = (state) ->
      # device status chaged, updating device status in Nora
      @system.updateState(state)

    deviceDimlevelHandler = (dimlevel) ->
      # device status changed, updating device status in Nora
      @system.updateDimlevel(dimlevel)

    deviceHueHandler = (hue) ->
      # device status changed, updating device status in Nora
      @system.updateHue(hue)

    executeAction: (change) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.on = change.on
      @state.brightness = change.brightness
      @state.color = change.color
      @device.changeStateTo(change.on) if @stateAvavailable
      @device.changeDimlevelTo(change.brightness)
      hueMilight = (256 + 176 - Math.floor(Number(change.color.spectrumHsv.hue) / 360.0 * 255.0)) % 256
      #hsv =[hueMilight,change.color.spectrumHsv.saturation,change.color.spectrumHsv.value]
      #color = Color(hsv).hex()
      #env.logger.info "hueMilight = " + hueMilight
      @device.changeHueTo(hueMilight)

    updateState: (newState) =>
      unless newState is @state.on
        env.logger.debug "Update state to " + newState
        @state.on = newState
        @UpdateState(@id, @state)

    updateDimlevel: (newDimlevel) =>
      unless newDimlevel is @state.brightness
        env.logger.debug "Update dimlevel to " + newDimlevel
        @state.brightness = newDimlevel
        @UpdateState(@id, @state)

    updateHue: (newHue)=>
      unless newHue is @state.color.spectrumHsv.hue
        env.logger.debug "Update hue to " + newHue
        @state.color.spectrumHsv.hue = newHue*360/255
        @UpdateState(@id, @state)

    getType: () ->
      return 'light'

    getState: () ->
      return @state

    destroy: ->
      @state.online = false;
      @system.updateState(@state)
      @device.removeListener 'state', deviceStateHandler if @stateAvavailable
      @device.removeListener 'dimlevel', deviceDimlevelHandler
      @device.removeListener 'hue', deviceHueHandler
