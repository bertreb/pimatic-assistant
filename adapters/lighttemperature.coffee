module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  Chroma = require 'chroma-js'

  class LightTemperatureAdapter extends events.EventEmitter

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
      @device.on 'ct', deviceCTHandler #(0-254 color, 255 is white)
      @device.system = @

      _hsvWarmWhite = Chroma.temperature(2600).hsv()
      @state =
        online: true
        on: false
        brightness: 0
        color:
          spectrumHsv:
            hue: _hsvWarmWhite[0]
            saturation: _hsvWarmWhite[1]
            value: _hsvWarmWhite[2]



      #@publishState()

    deviceStateHandler = (state) ->
      # device status chaged, updating device status in Nora
      @system.updateState(state)

    deviceDimlevelHandler = (dimlevel) ->
      # device status changed, updating device status in Nora
      @system.updateDimlevel(dimlevel)

    deviceCTHandler = (ct) ->
      # device status changed, updating device status in Nora
      @system.updateCT(ct)

    executeAction: (change) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.on = change.on
      @state.brightness = change.brightness
      @state.color = change.color
      _ct = Chroma.hsv(change.color.spectrumHsv.hue, change.color.spectrumHsv.saturation, change.color.spectrumHsv.value).temperature()
      _ct2 = 100-100*(_ct-2000)/(4500)
      @device.setCT(_ct2)
      @device.changeDimlevelTo(change.brightness)
      @device.changeStateTo(change.on) if @stateAvavailable

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

    updateCT: (newCT)=>
      #if newCT < 2000 or newCT > 7000 or not newCT? then return
      #env.logger.debug "raw newCT: " + newCT
      _newCT = 6500-4500*newCT/100
      _ct = Chroma.hsv(@state.color.spectrumHsv.hue, @state.color.spectrumHsv.saturation, @state.color.spectrumHsv.value).temperature()
      unless _newCT is _ct
        env.logger.debug "Update ct to " + _newCT
        _hsv = Chroma.temperature(_newCT).hsv()
        env.logger.debug "Convert to hsv: " + _hsv
        @state.color.spectrumHsv.hue = _hsv[0]
        @state.color.spectrumHsv.saturation = _hsv[1]
        @state.color.spectrumHsv.value = _hsv[2]
        @UpdateState(@id, @state)

    getType: () ->
      return 'light'

    getState: () ->
      return @state

    destroy: ->
      @state.online = false;
      @UpdateState(@state)
      @device.removeListener 'state', deviceStateHandler if @stateAvavailable
      @device.removeListener 'dimlevel', deviceDimlevelHandler
      @device.removeListener 'hue', deviceHueHandler
