module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'


  class TemperatureAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @id = adapterConfig.id
      @device = adapterConfig.pimaticDevice
      @temperatureAttribute = adapterConfig.auxiliary
      @humidityAttribute = adapterConfig.auxiliary2
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @modes = ["off", "heat", "on", "eco"]

      @state =
        online: true
        thermostatMode: "heat"
        thermostatTemperatureAmbient: 20
        thermostatHumidityAmbient: 50
        thermostatTemperatureSetpoint: 20
        thermostatTemperatureSetpointLow: 15
        thermostatTemperatureSetpointHigh: 30


      @temperature = 0
      @temperatureSensor = false
      @humidity = 0
      @humiditySensor = false

      if @device?
        @device.system = @
        if @device.hasAttribute(@temperatureAttribute)
          temp = @device.getLastAttributeValue(@temperatureAttribute)
          @state.thermostatTemperatureAmbient = temp
          @device.on @temperatureAttribute, temperatureHandler
          @temperatureSensor = true
        if @device.hasAttribute(@humidityAttribute)
          humidity = @device.getLastAttributeValue(@humidityAttribute)
          @humidity = humidity
          @state.thermostatHumidityAmbient = humidity
          @device.on @humidityAttribute, humidityHandler
          @humiditySensor = true

      @UpdateState(@id, @state) 

      #modeItems = ["off", "heat", "cool", "on", "auto", "fan-only", "purifier", "eco", "dry"]
      #Default gBridge supported modes: ["off","heat","on","auto"]

    temperatureHandler = (temperature) ->
      # device status changed, updating device status in Nora
      @system.updateTemperature(temperature)

    humidityHandler = (humidity) ->
      # device status changed, updating device status in Nora
      @system.updateHumidity(humidity)

    executeAction: (change) ->
      # device status changed, updating device status in Nora
      env.logger.debug "Received action: '#{change}' not executed"

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
      if @temperatureSensor
        @device.removeListener @temperatureAttribute, temperatureHandler
      if @humiditySensor
        @device.removeListener @humidityAttribute, humidityHandler

