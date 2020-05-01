module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  Color = require 'color'

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

    deviceCTHandler = (ct) ->
      # device status changed, updating device status in Nora
      @system.updateCT(ct)

    executeAction: (change) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.on = change.on
      @state.brightness = change.brightness
      @state.color = change.color
      @device.changeStateTo(change.on) if @stateAvavailable
      @device.changeDimlevelTo(change.brightness)
      #hueMilight = (256 + 176 - Math.floor(Number(change.color.spectrumHsv.hue) / 360.0 * 255.0)) % 256
      hsv =[change.color.spectrumHsv.hue, change.color.spectrumHsv.saturation, change.color.spectrumHsv.value]
      _xy = Color(hsv).xy()
      _ct = @xyY_to_kelvin(_xy)

      env.logger.debug "ct = " + _ct
      @device.setCT(_ct)

    xyY_to_kelvin = (x, y) ->
      n = (x-0.3320) / (y-0.1858)
      kelvin = parseInt((-449*n**3 + 3525*n**2 - 6823.3*n + 5520.33) + 0.5)

    kelvin_to_xy = (T) ->
      # Source https://en.wikipedia.org/wiki/Planckian_locus#Approximation
      # and http://fcam.garage.maemo.org/apiDocs/_color_8cpp_source.html
      if T <= 4000
        x = -0.2661239*(10**9)/T**3 - 0.2343589*(10**6)/T**2 + 0.8776956*(10**3)/T + 0.17991
      else if T <= 25000
        x = -3.0258469*(10**9)/T**3 + 2.1070379*(10**6)/T**2 + 0.2226347*(10**3)/T + 0.24039

      if T <= 2222
        y = -1.1063814*x**3 - 1.3481102*x**2 + 2.18555832*x - 0.20219683
      else if T <= 4000
        y = -0.9549476*x**3 - 1.37418593*x**2 + 2.09137015*x - 0.16748867
      else if T <= 25000
        y = 3.081758*x**3 - 5.8733867*x**2 + 3.75112997*x - 0.37001483

      xr = x*65535+0.5
      yr = y*65535+0.5

      [
        x
        y
      ]

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
      hsv =[@state.color.spectrumHsv.hue, @state.color.spectrumHsv.saturation, @state.color.spectrumHsv.value]
      _xy = Color(hsv).xy()
      _ct = @xyY_to_kelvin(_xy)
      unless newCT is _ct
        env.logger.debug "Update ct to " + newCT
        _newXy = kelvin_to_xy(newCT)
        _hsv = Color(_newXy).hsv()
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
      @device.removeListener 'state', deviceStateHandler if @stateAvavailable
      @device.removeListener 'dimlevel', deviceDimlevelHandler
      @device.removeListener 'hue', deviceHueHandler
