module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'


  class AssistantThermostatAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @id = adapterConfig.id
      @device = adapterConfig.pimaticDevice
      @temperatureDevice = adapterConfig.auxiliary
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState
      @bufferRange = @device.bufferRangeCelsius
      @lastSettings = 
        mode: "heat"
        power: "on"
        program: "manual"
      @device.system = @

      @mode = "heat"
      @power = true
      @program = "manual"
      @eco = false

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @modes = ["heat", "heatcool", "cool", "off", "eco"]
      #@powers = ["off", "eco", "on"]
      @ecos = ['eco']
      @programs = ["manual","schedule"]

      @state =
        online: true
        thermostatMode: "heat"
        thermostatTemperatureAmbient: 20
        thermostatHumidityAmbient: 50
        thermostatTemperatureSetpoint: 20
        thermostatTemperatureSetpointLow: 18
        thermostatTemperatureSetpointHigh: 22

      @device.getTemperatureSetpoint()
      .then((temp)=>
        @state.thermostatTemperatureSetpoint = temp
        return @device.getTemperatureSetpointLow()
      )
      @device.getTemperatureSetpointLow()
      .then((tempLow)=>
        @state.thermostatTemperatureSetpointLow = tempLow
        return @device.getTemperatureSetpointHigh()
      )
      @device.getTemperatureSetpointHigh()
      .then((tempHigh)=>
        @state.thermostatTemperatureSetpointHigh = tempHigh
        return @device.getMode()
      )
      .then((mode)=>
        @state.thermostatMode = mode
        @ambient = 0
        @ambiantSensor = false
        if @device.hasAttribute('temperatureRoom')
          return @device.getTemperatureRoom()
        else
          return null
      )
      .then((temp)=>
        if temp?
          @state.thermostatTemperatureAmbient = temp
          @device.on "temperatureRoom", temperatureHandler
          @ambiantSensor = true
        @humidity = 0
        @humiditySensor = false
        if @device.hasAttribute('humidityRoom')
          return @device.getHumidityRoom()
        else
          return null
      )
      .then((humidity)=>
        if humidity?
          @state.thermostatHumidityAmbient = humidity
          @device.on "humidityRoom", humidityHandler
          @humiditySensor = true
      )
      .finally(()=>
        #env.logger.info "State: " + JSON.stringify(@state,null,2)
        @state.online = true
        @UpdateState(@id, @state)        
      )

      #modeItems = ["off", "heat", "cool", "on", "auto", "fan-only", "purifier", "eco", "dry"]

      @device.on "mode", modeHandler
      @device.on "power", powerHandler
      @device.on "eco", ecoHandler
      @device.on "program", programHandler
      @device.on "temperatureSetpoint", setpointHandler
      @device.on "temperatureSetpointLow", setpointHandlerLow
      @device.on "temperatureSetpointHigh", setpointHandlerHigh
      @device.system = @

    modeHandler = (mode) ->
      # device mode changed, updating device status in Nora
      @system.mode = mode
      @changeEcoTo(false)
      @changePowerTo(true)
      @system.updateMode(mode)

    ecoHandler = (eco) ->
      # device mode changed, updating device status in Nora
      if eco
        @system.state.thermostatMode = "eco"
      else
        @system.state.thermostatMode = @system.mode
      @system.UpdateState(@system.id, @system.state)

    powerHandler = (power) ->
      # device mode changed, updating device status in Nora
      if power is false
        @system.state.online = true
        @system.state.thermostatMode = "off"
      else
        @system.state.online = true
        @system.state.thermostatMode = @system.mode
      @system.UpdateState(@system.id, @system.state)

    programHandler = (program) ->
      # device mode changed, updating device status in Nora
      @system.program = program
      @system.updateProgram(program)

    setpointHandler = (setpoint) ->
      # device setpoint changed, updating device status in Nora
      @system.updateSetpoint(setpoint)
    setpointHandlerLow = (setpoint) ->
      # device setpoint changed, updating device status in Nora
      @system.updateSetpointLow(setpoint)
    setpointHandlerHigh = (setpoint) ->
      # device setpoint changed, updating device status in Nora
      @system.updateSetpointHigh(setpoint)

    temperatureHandler = (temperature) ->
      # device temperature changed, updating device status in Nora
      @system.updateTemperature(temperature)

    humidityHandler = (humidity) ->
      # device humidity changed, updating device status in Nora
      @system.updateHumidity(humidity)

    executeAction: (change) ->
      # device status changed, updating device status in Nora
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.thermostatMode = change.thermostatMode
      @state.thermostatTemperatureSetpoint = change.thermostatTemperatureSetpoint
      #@state.online = change.online

      switch change.thermostatMode
        when "heat"
          @mode = "heat"
          @power = true
          @eco = false
        when "cool"
          @mode = "cool"
          @power = true
          @eco = false
        when "heatcool"
          @mode = "heatcool"
          @power = true
          @eco = false
        when "eco"
          @eco = true
        when "off"
          @power = false

      @device.changeModeTo(@mode)
      .then(() =>
        env.logger.debug "Thermostat mode changed to " + @mode
      )
      @device.changePowerTo(@power)
      .then(() =>
        env.logger.debug "Thermostat power changed to " + @power
      )
      @device.changeProgramTo(@program)
      .then(() =>
        env.logger.debug "Thermostat program changed to " + @program
      )

      @device.changeEcoTo(@eco)
      @device.changeTemperatureTo(change.thermostatTemperatureSetpoint)
      @device.changeTemperatureLowTo(change.thermostatTemperatureSetpointLow)
      @device.changeTemperatureHighTo(change.thermostatTemperatureSetpointHigh)

    updateMode: (newMode) =>
      unless newMode is @state.thermostatMode
        env.logger.debug "Update thermostat mode to " + newMode
        @state.thermostatMode = newMode
        @UpdateState(@id, @state)

    updateEco: (newEco) =>
      env.logger.debug "Update thermostat mode to " + newEco
      @state.thermostatMode = newMode
      @UpdateState(@id, @state)

    updatePower: (newPower) =>
      env.logger.debug "Update thermostat power to " + @state
      @state.thermostatMode = newPower
      @UpdateState(@id, @state)

    updateProgram: (newProgram) =>
      #unless newMode is @state.thermostatMode
      env.logger.debug "Update thermostat program to " + newProgram
      if newProgram is "manual"
        #restore @laststetting.mode
        @state.thermostatMode = @mode
        @UpdateState(@id, @state)
      #else
      #  #store @lastSettings.mode
      #  @mode = @state.thermostatMode
      #  #@state.thermostatMode = "auto" #Mode = auto

    updateSetpoint: (newSetpoint) =>
      unless newSetpoint is @state.thermostatTemperatureSetpoint
        env.logger.debug "Update setpoint to " + newSetpoint
        @state.thermostatTemperatureSetpoint = newSetpoint
        @UpdateState(@id, @state)
    updateSetpointLow: (newSetpoint) =>
      unless newSetpoint is @state.thermostatTemperatureSetpointLow
        env.logger.debug "Update setpoint low to " + newSetpoint
        @state.thermostatTemperatureSetpointLow = newSetpoint
        @UpdateState(@id, @state)
    updateSetpointHigh: (newSetpoint) =>
      unless newSetpoint is @state.thermostatTemperatureSetpointHigh
        env.logger.debug "Update setpoint high to " + newSetpoint
        @state.thermostatTemperatureSetpointHigh = newSetpoint
        @UpdateState(@id, @state)

    updateTemperature: (newTemperature) =>
      unless newTemperature is @state.thermostatTemperatureAmbient
        env.logger.debug "Update ambiant temperature to " + newTemperature
        @state.thermostatTemperatureAmbient = newTemperature
        env.logger.debug "updateTemperature " + JSON.stringify(@state,null,2)
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
      @device.removeListener "mode", modeHandler
      @device.removeListener "temperatureSetpoint", setpointHandler
      @device.removeListener "temperatureSetpointLow", setpointHandlerLow
      @device.removeListener "temperatureSetpointHigh", setpointHandlerHigh
      @device.removeListener "power", powerHandler
      @device.removeListener "eco", ecoHandler
      @device.removeListener "program", programHandler
      @device.removeListener "temperature", temperatureHandler
      @device.removeListener "humidity", humidityHandler
      @state.online = false;
      @UpdateState(@state)


