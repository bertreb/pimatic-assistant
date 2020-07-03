module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'


  class HeatingThermostatAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @id = adapterConfig.id
      @device = adapterConfig.pimaticDevice
      @temperatureDevice = adapterConfig.auxiliary
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @modes = ["off","heat"]
      #@modes = ["off", "on", cool", "auto", "eco", "heat", "heatcool", "fan-only", "heat", "purifier"]

      @state =
        online: true
        thermostatMode: "on"
        thermostatTemperatureAmbient: 25
        thermostatHumidityAmbient: 50
        thermostatTemperatureSetpoint: 20
        thermostatTemperatureSetpointLow: 15
        thermostatTemperatureSetpointHigh: 30

      @device.getTemperatureSetpoint()
      .then((temp)=>
        @state.thermostatTemperatureSetpoint = temp
        return @device.getMode()
      )
      .then((mode)=>
        @state.thermostatMode = mode
        @ambient = 0
        @ambiantSensor = false
        if @temperatureDevice?
          if @temperatureDevice.hasAttribute('temperature')
            return @temperatureDevice.getTemperature()
          else
            return null
      )
      .then((temp)=>
        if temp?
          @state.thermostatTemperatureAmbient = temp
          @temperatureDevice.on "temperature", temperatureHandler
          @temperatureDevice.system = @
          @ambiantSensor = true
        @humidity = 0
        @humiditySensor = false
        if @temperatureDevice?
          if @temperatureDevice.hasAttribute('humidity')
            return @temperatureDevice.getHumidity()
      )
      .then((humidity)=>
        if humidity?
          @state.thermostatHumidityAmbient = humidity
          @temperatureDevice.on "humidity", humidityHandler
          @temperatureDevice.system = @
          @humiditySensor = true
      )
      .finally(()=>
        #env.logger.info "State: " + JSON.stringify(@state,null,2)
        @UpdateState(@id, @state)        
      )

      #modeItems = ["off", "heat", "cool", "on", "auto", "fan-only", "purifier", "eco", "dry"]
      #Default gBridge supported modes: ["off","heat","on","auto"]

      @device.on "mode", modeHandler
      @device.on "temperatureSetpoint", setpointHandler
      @device.system = @

    modeHandler = (mode) ->
      #env.logger.debug "Device mode change, no publish!!!" # publish mode: mqttHeader: " + _mqttHeader1 + ", mode: " + mode
      @system.updateMode(mode)

    setpointHandler = (setpoint) ->
      # device status changed, updating device status in Nora
      @system.updateSetpoint(setpoint)

    temperatureHandler = (temperature) ->
      # device status changed, updating device status in Nora
      @system.updateTemperature(temperature)

    humidityHandler = (humidity) ->
      # device status changed, updating device status in Nora
      @system.updateHumidity(humidity)

    executeAction: (change) ->
      # device status changed, updating device status in Nora
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.thermostatMode = change.thermostatMode
      @state.thermostatTemperatureSetpoint = change.thermostatTemperatureSetpoint
      @state.thermostatTemperatureSetpointLow = change.thermostatTemperatureSetpointLow
      @state.thermostatTemperatureSetpointHigh = change.thermostatTemperatureSetpointHigh

      switch change.thermostatMode
        when "heat"
          @thermostat = on
          @mode = "heat"
        when "eco"
          @thermostat = on
          @mode = "heat"
        when "on"
          @thermostat = on
          @mode = "heat"
        when "off"
          @thermostat = off
          @mode = "off"
      @device.changeModeTo(@mode)
      .then(() =>
        env.logger.debug "Thermostat mode changed to " + @mode
      )
      @device.changeTemperatureTo(change.thermostatTemperatureSetpoint)

    updateMode: (newMode) =>
      unless newMode is @state.thermostatMode
        env.logger.debug "Update thermostatMode to " + newMode
        @state.thermostatMode = newMode
        @UpdateState(@id, @state)

    updateSetpoint: (newSetpoint) =>
      unless newSetpoint is @state.thermostatTemperatureSetpoint
        env.logger.debug "Update setpoint to " + newSetpoint
        @state.thermostatTemperatureSetpoint = newSetpoint
        @UpdateState(@id, @state)

    updateTemperature: (newTemperature) =>
      unless newTemperature is @state.thermostatTemperatureAmbient
        env.logger.debug "Update ambiant temperature to " + newTemperature
        @state.thermostatTemperatureAmbient = newTemperature
        @UpdateState(@id, @state)

    updateHumidity: (newHumidity) =>
      unless newHumidity is @state.thermostatHumidityAmbient
        env.logger.debug "Update ambiant humidity to " + newHumidity
        @state.thermostatHumidityAmbient = newHumidity
        @UpdateState(@id, @state)

    getType: () ->
      return "thermostat"

    getState: () ->
      return @state

    getModes: () ->
      return @modes

    destroy: ->
      @state.online = false;
      @UpdateState(@state)
      @device.removeListener "mode", modeHandler
      @device.removeListener "temperatureSetpoint", setpointHandler
      if @ambientDevice?
        @temperatureDevice.removeListener "temperature", temperatureHandler
      if @humidityDevice?
        @temperatureDevice.removeListener "humidity", humidityHandler

