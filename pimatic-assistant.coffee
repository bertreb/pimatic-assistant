module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'

  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  lightColorAdapter = require('./adapters/lightcolor')(env)
  lightTemperatureAdapter = require('./adapters/lighttemperature')(env)
  lightColorMilightAdapter = require('./adapters/lightcolormilight')(env)
  buttonAdapter = require('./adapters/button')(env)
  blindsAdapter = require('./adapters/blinds')(env)
  heatingThermostatAdapter = require('./adapters/heatingthermostat')(env)
  assistantThermostatAdapter = require('./adapters/assistantthermostat')(env)
  ###
  contactAdapter = require('./adapters/contact')(env)
  temperatureAdapter = require('./adapters/temperature')(env)
  sceneAdapter = require('./adapters/scene')(env)
  ###

  io = require('socket.io-client')
  _ = require('lodash')
  M = env.matcher

  class AssistantPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-assistant-config-schema'
      @configProperties = pluginConfigDef.properties

      ###
      version = "0.0.34" # is latest node-red-nora-contrib version
      notify = true
      group = "pimatic"
      uri = 'https://node-red-google-home.herokuapp.com/?' +
        'version=' + version +
        '&token=' + encodeURIComponent(@config.token) +
        '&notify=' + notify +
        '&group=' + encodeURIComponent(group)

      @socket = io(uri, {reconnection:true,reconnectionDelay:15000})
      ###
      #@initialized = 0

      deviceConfigDef =  require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('AssistantDevice', {
        configDef: deviceConfigDef.AssistantDevice,
        createCallback: (config, lastState) => new AssistantDevice(config, lastState, @framework, @)
      })
      @framework.deviceManager.registerDeviceClass('AssistantThermostat', {
        configDef: deviceConfigDef.AssistantThermostat,
        createCallback: (config, lastState) => new AssistantThermostat(config, lastState, @framework, @)
      })

      @framework.ruleManager.addActionProvider(new AssistantThermostatActionProvider(@framework))

      @framework.on "after init", =>
        # Check if the mobile-frontend was loaded and get a instance
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', 'pimatic-assistant/app/thermostat.coffee'
          mobileFrontend.registerAssetFile 'css', 'pimatic-assistant/app/thermostat.css'
          mobileFrontend.registerAssetFile 'html', 'pimatic-assistant/app/thermostat.jade'
          #mobileFrontend.registerAssetFile 'js', 'pimatic-assistant/ui/vendor/spectrum.js'
          #mobileFrontend.registerAssetFile 'css', 'pimatic-assistant/ui/vendor/spectrum.css'
          #mobileFrontend.registerAssetFile 'js', 'pimatic-assistant/ui/vendor/async.js'
        else
          env.logger.warn 'Your plugin could not find the mobile-frontend. No gui will be available'


  class AssistantDevice extends env.devices.PresenceSensor

    constructor: (@config, lastState, @framework, @plugin) ->
      #@config = config
      @id = @config.id
      @name = @config.name

      #if @_destroyed then return

      version = "0.0.34" # is latest node-red-nora-contrib version
      notify = true
      group = "pimatic"
      @uri = 'https://node-red-google-home.herokuapp.com/?' +
        'version=' + version +
        '&token=' + encodeURIComponent(@plugin.config.token) +
        '&notify=' + notify +
        '&group=' + encodeURIComponent(group)

 
      @_presence = lastState?.presence?.value or off

      @devMgr = @framework.deviceManager

      @handlers = {}

      checkMultipleDevices = []
      @configDevices = []
      @framework.variableManager.waitForInit()
      .then(()=>
        for _device in @config.devices
          do(_device) =>
            if _.find(checkMultipleDevices, (d) => d.pimatic_device_id is _device.pimatic_device_id and d.pimatic_subdevice_id is _device.pimatic_device_id)?
              throw new Error "Pimatic device '#{_device.pimatic_device_id}' is already used"
            else
              checkMultipleDevices.push _device
            @configDevices.push _device
            _fullDevice = @framework.deviceManager.getDeviceById(_device.pimatic_device_id)
            unless _fullDevice?
              throw new Error "Pimatic device '#{_device.pimatic_device_id}' does not excist"
            unless @selectAdapter(_fullDevice)?
              throw new Error "Pimatic device class '#{_fullDevice.config.class}' is not supported"

        @initNoraConnection()
      )


      @framework.on "deviceRemoved", (device) =>
        if _.find(@config.devices, (d) => d.pimatic_device_id == device.id)
          #throw new Error "Please remove device also in Assistant"
          env.logger.info "please remove device also in Assistant!"

      #if @socket.connected then @_setPresence(true) else @_setPresence(false)

      super()

    updateState: (id, newState) =>
      _a = {}
      _a[id] = newState
      #env.logger.debug "updateState: " + JSON.stringify(_a,null,2)
      @socket.emit('update', _a, "req:" + id)

    initNoraConnection: () =>

      @socket = io(@uri, {autoConnect:true, reconnection:true, reconnectionDelay:20000, randomizationFactor:0.2})

      @socket.on 'connect', () =>
        @_setPresence(yes)
        env.logger.debug "NORA - connected to Nora server"
        @getSyncDevices(@configDevices)
        .then((syncDevices)=>
          @socket.emit('sync', syncDevices, 'req:sync')
          env.logger.debug "NORA - after device start, devices synced: " + JSON.stringify(syncDevices,null,2)
          if _.size(syncDevices)>0
            @_setPresence(true)
          else
            @socket.disconnect()
            @_setPresence(false)
        )

      @socket.on 'update', (changes) =>
        env.logger.debug "NORA - update received " + JSON.stringify(changes,null,2)
        @handleUpdate(changes)
        .then((result)=>
        )

      @socket.on 'action-error', (reqId, msg) =>
        env.logger.debug "NORA - action-error received, reqId " + reqId + ", msg: " + JSON.stringify(msg,null,2)

      @socket.on 'activate-scene', (ids, deactivate) =>
        env.logger.debug "NORA - activate-scene, ids " + JSON.stringify(ids,null,2) + ", deactivate: " + deactivate

      @socket.on 'connect_error', (err) =>
        env.logger.debug "NORA - connect_error " + err
      @socket.on 'reconnect_error', (err) =>
        env.logger.debug "NORA - reconnect_error " + err
      @socket.on 'reconnect_failed', (err) =>
        env.logger.debug "NORA - reconnect_failed " + err

      @socket.on 'reconnecting', () =>
        env.logger.debug "Try to reconnect to Nora server..."
 
      @socket.on 'disconnect', () =>
        @_setPresence(false)
        env.logger.debug "NORA - disconnected from Nora server"

      @guardInterval = 300000
      connectionGuard = () =>
        #env.logger.debug "GUARD: connection status connected: " + JSON.stringify(@socket.connected,null,2)
        if not @socket? or @socket.connected is false
          env.logger.debug "GUARD: Nora not connected, try to force re-connect"
          @socket.close()
          @socket.removeAllListeners()
          @socket = null
          @initNoraConnection()
        else
          @connectionGuardTimer = setTimeout(connectionGuard, @guardInterval)
      @connectionGuardTimer = setTimeout(connectionGuard, @guardInterval)


    toGA = (id) ->
      return id.split('-').join('.')

    getSyncDevices: (configDevices) =>
      return new Promise((resolve,reject) =>
        devices = {}
        for _device, key in configDevices
          pimaticDevice = @devMgr.getDeviceById(_device.pimatic_device_id)
          _newDevice = null
          if pimaticDevice?
            gaDeviceId = toGA(_device.pimatic_device_id)
            _adapterConfig =
              id: gaDeviceId #_device.pimatic_device_id
              pimaticDevice: pimaticDevice
              updateState: @updateState
              pimaticSubDeviceId: _device.pimatic_subdevice_id
              auxiliary: _device.auxiliary
              auxiliary2: _device.auxiliary2
            #twoFa: _device.twofa
            #twoFaPin: if _value.twofaPin? then _value.twofaPin else undefined
            switch @selectAdapter(pimaticDevice)
              when "lightColorMilight"
                _newDevice = new lightColorMilightAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  brightnessControl: true
                  turnOnWhenBrightnessChanges: false
                  colorControl: true
              when "lightColor"
                _newDevice = new lightColorAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  brightnessControl: true
                  turnOnWhenBrightnessChanges: false
                  colorControl: true
              when "lightTemperature"
                _newDevice = new lightTemperatureAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  brightnessControl: true
                  turnOnWhenBrightnessChanges: false
                  colorControl: true
              when "light"
                _newDevice = new lightAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  brightnessControl: true
                  turnOnWhenBrightnessChanges: true
                  colorControl: false
              when "switch"
                _newDevice = new switchAdapter(_adapterConfig)
                devices[gaDeviceId] = {}
              when "button"
                _newDevice = new buttonAdapter(_adapterConfig)
                devices[gaDeviceId] = {}
              when "heatingThermostat"
                @ambiantDevice = if _device.auxiliary? then @devMgr.getDeviceById(_device.auxiliary) else null
                _adapterConfig["auxiliary"] = @ambiantDevice
                _newDevice = new heatingThermostatAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  temperatureUnit: "C"
                  bufferRangeCelsius: pimaticDevice.bufferRangeCelsius
                  commandOnlyTemperatureSetting: false
                  queryOnlyTemperatureSetting: false
                  availableModes: _newDevice.getModes()
              when "assistantThermostat"
                #@ambiantDevice = if _device.auxiliary? then @devMgr.getDeviceById(_device.auxiliary) else null
                #_adapterConfig["auxiliary"] = @ambiantDevice
                _newDevice = new assistantThermostatAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  temperatureUnit: "C"
                  bufferRangeCelsius: 2#pimaticDevice.bufferRangeCelsius
                  commandOnlyTemperatureSetting: false
                  queryOnlyTemperatureSetting: false
                  availableModes: _newDevice.getModes()
              when "blinds"
                _newDevice = new blindsAdapter(_adapterConfig)
                devices[gaDeviceId] = {}

                ###
                else if pimaticDevice instanceof env.devices.Sensor and pimaticDevice.hasAttribute('contact')
                  env.logger.debug "Add contact adapter with ID: " + pimaticDevice.id
                  @addAdapter(new contactAdapter(_adapterConfig))
                ###
                ###
                else if pimaticDevice.hasAttribute(_value.auxiliary)
                  env.logger.debug "Add temperature adapter with ID: " + pimaticDevice.id
                  @addAdapter(new temperatureAdapter(_adapterConfig))
                ###

              else
                env.logger.debug "Device type #{pimaticDevice.config.class} is not supported!"


            if _newDevice?
              devices[gaDeviceId]["type"] = _newDevice.getType()
              devices[gaDeviceId]["name"] = _device.name
              devices[gaDeviceId]["state"] = _newDevice.getState()
              unless _device.twofa is "none"
                devices[gaDeviceId]["twoFactor"] = _device.twofa
                if _device.twofa is "pin"
                  devices[gaDeviceId]["pin"] = _device.pin ? "0000"

              devices[gaDeviceId]["roomHint"] = _device.roomHint if _device.roomHint?
              @handlers[gaDeviceId] = _newDevice

        resolve(devices)
      )

    selectAdapter: (pimaticDevice) ->
      _foundAdapter = null
      if pimaticDevice.config.class is "MilightRGBWZone" or pimaticDevice.config.class is "MilightFullColorZone"
        _foundAdapter = "lightColorMilight"
      else if ((pimaticDevice.config.class).toLowerCase()).indexOf("rgb") >= 0
        _foundAdapter = "lightColor"
      else if ((pimaticDevice.config.class).toLowerCase()).indexOf("ct") >= 0
        _foundAdapter = "lightTemperature"
      else if (pimaticDevice.config.class).indexOf("Dimmer") >= 0
        _foundAdapter = "light"
      else if (pimaticDevice.config.class).indexOf("Switch") >= 0
        _foundAdapter = "switch"
      else if pimaticDevice instanceof env.devices.ButtonsDevice
        _foundAdapter = "button"
      else if pimaticDevice instanceof env.devices.DummyHeatingThermostat
        _foundAdapter = "heatingThermostat"
      else if pimaticDevice.config.class is "AssistantThermostat"
        _foundAdapter = "assistantThermostat"
      else if pimaticDevice instanceof env.devices.ShutterController
        _foundAdapter = "blinds"

      if _foundAdapter?
        env.logger.debug _foundAdapter + " device found"
      return _foundAdapter


    handleUpdate: (changes) =>
      return new Promise((resolve,reject)=>
        for key, value of changes
          @handlers[key].executeAction(value)
        resolve()
      )

    destroy: ->
      if @socket?
        @socket.disconnect()
        @socket.removeAllListeners()
      clearTimeout(@connectionGuardTimer)
      for i, handler of @handlers
        handler.destroy()
        delete @handlers[i]

      super()

  class AssistantThermostat extends env.devices.Device

    template: "assistantthermostat"

    getTemplateName: -> "assistantthermostat"

    actions:
      changePowerTo:
        params:
          power:
            type: "boolean"
      toggleEco:
        description: "Eco button toggle"
      changeModeTo:
        params:
          mode:
            type: "string"
      changeTemperatureTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeTemperatureLowTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeTemperatureHighTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeProgramTo:
        params:
          program:
            type: "string"
      changeTemperatureAmbiantTo:
        params:
          temperature:
            type: "number"
      changeHumidityAmbiantTo:
        params:
          humidity:
            type: "number"

    constructor: (@config, lastState, @framework) ->
      @id = @config.id
      @name = @config.name
      @_temperatureSetpoint = lastState?.temperatureSetpoint?.value or 20
      @_temperatureSetpointLow = lastState?.temperatureSetpointLow?.value or 18
      @_temperatureSetpointHigh = lastState?.temperatureSetpointHigh?.value or 22 # + @config.bufferRangeCelsius
      @_mode = lastState?.mode?.value or "heat"
      @_power = lastState?.power?.value or true
      @_eco = lastState?.eco?.value or false
      @_program = lastState?.program?.value or "manual"
      @_temperatureAmbiant = lastState?.temperatureAmbiant?.value or 20
      @_timeToTemperatureSetpoint = lastState?.timeToTemperatureSetpoint?.value or 0
      @_humidityAmbiant = lastState?.humidityAmbiant?.value or 50
      @_battery = lastState?.battery?.value or "ok"
      @_synced = true
      @_active = false
      @_heater = lastState?.heater?.value or false
      @_cooler = lastState?.cooler?.value or false
      @temperatureSensor = false
      @humiditySensor = false
      @minThresholdCelsius = @config.minThresholdCelsius? or 5
      @maxThresholdCelsius = @config.maxThresholdCelsius? or 30


      @attributes =
        temperatureSetpoint:
          description: "The temp that should be set"
          type: "number"
          label: "Temperature Setpoint"
          unit: "°C"
          hidden: true
        temperatureSetpointLow:
          description: "The tempersture low that should be set in heatcool mode"
          type: "number"
          label: "Temperature SetpointLow"
          unit: "°C"
          hidden: true
        temperatureSetpointHigh:
          description: "The tempersture high that should be set in heatcool mode"
          type: "number"
          label: "Temperature SetpointHigh"
          unit: "°C"
          hidden: true
        power:
          description: "The power mode"
          type: "boolean"
          hidden: true
        eco:
          description: "The eco mode"
          type: "boolean"
          hidden: true
        mode:
          description: "The current mode"
          type: "string"
          enum: ["heat", "heatcool", "cool"]
          default: ["heat"]
          hidden: true
        program:
          description: "The program mode"
          type: "string"
          enum: ["manual", "auto"]
          default: ["manual"]
          hidden: true
        active:
          description: "If heating or cooling is active"
          type: "boolean"
          labels: ["active","ready"]
          acronym: "status"
        heater:
          description: "If heater is enabled"
          type: "boolean"
          labels: ["on","off"]
          acronym: "heater"
        cooler:
          description: "If cooler is enabled"
          type: "boolean"
          labels: ["on","off"]
          acronym: "cooler"
        timeToTemperatureSetpoint:
          description: "The time to reach the temperature setpoint"
          type: "number"
          unit: "sec"
          acronym: "time to setpoint"
        temperatureAmbiant:
          description: "The room temperatue of the thermostat"
          type: "number"
          acronym: "T"
          unit: "°C"
        humidityAmbiant:
          description: "The room humidity of the thermostat"
          type: "number"
          acronym: "H"
          unit: "%"
        battery:
          description: "Battery status"
          type: "string"
          #enum: ["ok", "low"]
          hidden: true
        synced:
          description: "Pimatic and thermostat in sync"
          type: "boolean"
          hidden: true

      @framework.variableManager.waitForInit()
      .then(()=>
        @_temperatureDevice = @config.temperatureDevice.replace("$","").trim()      
        @_temperatureDevice = @_temperatureDevice.split('.')
        if @_temperatureDevice[0]?
          @temperatureDevice = @framework.deviceManager.getDeviceById(@_temperatureDevice[0])     
          unless @temperatureDevice?
            throw new Error "Unknown temperature device '#{@temperatureDevice}'"
          @temperatureAttribute = @_temperatureDevice[1]
          env.logger.info "@temperatureAttribute " + JSON.stringify(@temperatureAttribute,null,2)
          unless @temperatureDevice.hasAttribute(@temperatureAttribute)
            throw new Error "Unknown temperature attribute '#{@temperatureAttribute}'"
          env.logger.debug "Temperature device found " + JSON.stringify(@temperatureDevice.config,null,2)
          @temperatureDevice.getTemperature()
          .then((temperatureAmbiant)=>
            @changeTemperatureAmbiantTo(temperatureAmbiant)
          )
          @temperatureDevice.system = @
          @temperatureDevice.on @temperatureAttribute, @temperatureHandler
          @temperatureSensor = true
        @_humidityDevice = @config.humidityDevice.replace("$","").trim()
        @_humidityDevice = @_humidityDevice.split('.')
        if @_humidityDevice[0]?
          @humidityDevice = @framework.deviceManager.getDeviceById(@_humidityDevice[0])     
          unless @humidityDevice?
            throw new Error "Unknown humidity device '#{@humidityDevice}'"
          @humidityAttribute = @_humidityDevice[1]
          unless @humidityDevice.hasAttribute(@humidityAttribute)
            throw new Error "Unknown humidity attribute '#{@humidityAttribute}'"
          env.logger.debug "Temperature device found " + JSON.stringify(@humidityDevice.config,null,2)
          @humidityDevice.getHumidity()
          .then((humidityAmbiant)=>
            @changeHumidityAmbiantTo(humidityAmbiant)
          )
          @humidityDevice.system = @
          @humidityDevice.on @humidityAttribute, @humidityHandler
          @humiditySensor = true
      )

      super()

    temperatureHandler: (temperatureAmbiant) =>
      @changeTemperatureAmbiantTo(temperatureAmbiant)

    humidityHandler: (humidityAmbiant) =>
      @changeHumidityAmbiantTo(humidityAmbiant)

    getMode: () -> Promise.resolve(@_mode)
    getPower: () -> Promise.resolve(@_power)
    getEco: () -> Promise.resolve(@_eco)
    getProgram: () -> Promise.resolve(@_program)
    getTemperatureSetpoint: () -> Promise.resolve(@_temperatureSetpoint)
    getTemperatureSetpointLow: () -> Promise.resolve(@_temperatureSetpointLow)
    getTemperatureSetpointHigh: () -> Promise.resolve(@_temperatureSetpointHigh)
    getActive: () -> Promise.resolve(@_active)
    getHeater: () -> Promise.resolve(@_heater)
    getCooler: () -> Promise.resolve(@_cooler)
    getTemperatureAmbiant: () -> Promise.resolve(@_temperatureAmbiant)
    getHumidityAmbiant: () -> Promise.resolve(@_humidityAmbiant)
    getTimeToTemperatureSetpoint: () -> Promise.resolve(@_timeToTemperatureSetpoint)
    getBattery: () -> Promise.resolve(@_battery)
    getSynced: () -> Promise.resolve(@_synced)

    _setMode: (mode) ->
      if mode is @_mode then return
      @_mode = mode
      @emit "mode", @_mode

    _setPower: (power) ->
      if power is @_power then return
      @_power = power
      @handleTemperatureChange()
      @emit "power", @_power

    _setEco: (eco) ->
      if eco is @_eco then return
      @_eco = eco
      @emit "eco", @_eco

    _setProgram: (program) ->
      if program is @_program then return
      @_program = program
      @emit "program", @_program

    _setSynced: (synced) ->
      if synced is @_synced then return
      @_synced = synced
      @emit "synced", @_synced

    _setSetpoint: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpoint then return
      @_temperatureSetpoint = temperatureSetpoint
      @emit "temperatureSetpoint", @_temperatureSetpoint

    _setSetpointLow: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpointLow then return
      @_temperatureSetpointLow = temperatureSetpoint
      @emit "temperatureSetpointLow", @_temperatureSetpointLow

    _setSetpointHigh: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpointHigh then return
      @_temperatureSetpointHigh = temperatureSetpoint
      @emit "temperatureSetpointHigh", @_temperatureSetpointHigh

    _setHeater: (heater) ->
      if heater is @_heater then return
      @_heater = heater
      @emit "heater", @_heater

    _setCooler: (cooler) ->
      if cooler is @_cooler then return
      @_cooler = cooler
      @emit "cooler", @_cooler

    _setBattery: (battery) ->
      if battery is @_battery then return
      @_battery = battery
      @emit "battery", @_battery

    _setActive: (active) ->
      if active is @_active or @_power is false then return
      @_active = active
      @emit "active", @_active

    _setTimeToTemperatureSetpoint: (time) ->
      if time is @_timeToTemperatureSetpoint then return
      @_timeToTemperatureSetpoint = time
      @emit "timeToTemperatureSetpoint", @_timeToTemperatureSetpoint

    _setTemperatureAmbiant: (temperatureAmbiant) ->
      if temperatureAmbiant is @_temperatureAmbiant then return
      @_temperatureAmbiant = temperatureAmbiant
      @emit "temperatureAmbiant", @_temperatureAmbiant

    _setHumidityAmbiant: (humidityAmbiant) ->
      if humidityAmbiant is @_humidityAmbiant then return
      @_humidityAmbiant = humidityAmbiant
      @emit "humidityAmbiant", @_humidityAmbiant

    changeModeTo: (mode) ->
      @_setMode(mode)
      @handleTemperatureChange()
      return Promise.resolve()

    changeProgramTo: (program) ->
      @_setProgram(program)
      return Promise.resolve()

    changePowerTo: (power) ->
      @_setPower(power)
      return Promise.resolve()

    toggleEco: () ->
      @_setEco(!@_eco)
      return Promise.resolve()

    changeEcoTo: (eco) ->
      @_setEco(eco)
      return Promise.resolve()

    changeActiveTo: (active) ->
      @_setActive(active)
      return Promise.resolve()

    changeHeaterTo: (heater) ->
      @_setHeater(heater)
      @_setActive(heater)
      return Promise.resolve()
    changeCoolerTo: (cooler) ->
      @_setCooler(cooler)
      @_setActive(cooler)
      return Promise.resolve()

    changeTimeToTemperatureSetpointTo: (time) ->
      @_setTimeToTemperatureSetpoint(time)
      return Promise.resolve()

    changeTemperatureAmbiantTo: (temperatureAmbiant) ->
      @_setTemperatureAmbiant(temperatureAmbiant)
      @handleTemperatureChange()
      return Promise.resolve()

    changeHumidityAmbiantTo: (humidityAmbiant) ->
      @_setHumidityAmbiant(humidityAmbiant)
      return Promise.resolve()

    changeTemperatureTo: (temperatureSetpoint) ->
      @_setSetpoint(temperatureSetpoint)
      @handleTemperatureChange()
      return Promise.resolve()

    changeTemperatureLowTo: (temperatureSetpoint) ->
      @_setSetpointLow(temperatureSetpoint)
      @handleTemperatureChange()
      return Promise.resolve()

    changeTemperatureHighTo: (temperatureSetpoint) ->
      @_setSetpointHigh(temperatureSetpoint)
      @handleTemperatureChange()
      return Promise.resolve()

    handleTemperatureChange: () =>
      # check if pid -> enable pid
      @getPower()
      .then((power)=>
        if power       
          @getMode()
          .then((mode)=>
            switch mode
              when "heat"
                if @_temperatureSetpoint > @_temperatureAmbiant
                  @changeHeaterTo(on)
                else
                  @changeHeaterTo(off)
              when "cool"
                if @_temperatureSetpoint < @_temperatureAmbiant
                  @changeCoolerTo(on)
                else
                  @changeCoolerTo(off)
              when "heatcool"
                if @_temperatureSetpointLow > @_temperatureAmbiant
                  @changeHeaterTo(on)
                else
                  @changeHeaterTo(off)
                if @_temperatureSetpointHigh < @_temperatureAmbiant
                  @changeCoolerTo(on)
                else
                  @changeCoolerTo(off)
        )
        else
          @changeHeaterTo(off)
          @changeCoolerTo(off)
          @changeActiveTo(off)
      )

    execute: (device, command, options) =>
      env.logger.debug "Execute command: #{command} with options: " + JSON.stringify(options,null,2)
      return new Promise((resolve, reject) =>
        unless device?
          env.logger.info "Device '#{@name}' is unknown"
          return reject()
        switch command
          when "heat"
            @changeModeTo("heat")
          when "heatcool"
            @changeModeTo("heatcool")
          when "cool"
            @changeModeTo("cool")
          when "eco"
            @changeEcoTo(true)
          when "off"
            @changePowerTo(false)
          when "on"
            @changePowerTo(true)
          when "setpoint"
            @changeTemperatureTo(options.setpoint)
          when "setpointlow"
            @changeTemperatureLowTo(options.setpointHigh)
          when "setpointhigh"
            @changeTemperatureHighTo(options.setpointLow)
          when "manual"
            @changeProgramTo("manual")
          when "schedule"
            @changeProgramTo("schedule")
          else
            env.logger.debug "Unknown command received: " + command
            reject()
      )

    destroy: ->
      if @temperatureDevice?
        @temperatureDevice.removeListener(@temperatureAttribute, @temperatureHandler)
      if @humidityDevice?
        @humidityDevice.removeListener(@humidityAttribute, @humidityHandler)
      super()


  class AssistantThermostatActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>

      @assistantThermostatDevice = null

      @command = ""

      @parameters = {}

      assistantThermostatDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "AssistantThermostat"
      ).value()

      setCommand = (_command) =>
        @command = _command

      setpoint = (m,tokens) =>
        unless tokens >= @assistantThermostatDevice.config.minThresholdCelsius and tokens <= @assistantThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@assistantThermostatDevice.config.minThresholdCelsius} and #{@assistantThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpoint")
        @parameters["setpoint"] = Number tokens

      setpointlow = (m,tokens) =>
        unless tokens >= @assistantThermostatDevice.config.minThresholdCelsius and tokens <= @assistantThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@assistantThermostatDevice.config.minThresholdCelsius} and #{@assistantThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpointlow")
        @parameters["setpointLow"] = Number tokens

      setpointhigh = (m,tokens) =>
        unless tokens >= @assistantThermostatDevice.config.minThresholdCelsius and tokens <= @assistantThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@assistantThermostatDevice.config.minThresholdCelsius} and #{@assistantThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpointhigh")
        @parameters["setpointHigh"] = Number tokens

      m = M(input, context)
        .match('thermostat ')
        .matchDevice(assistantThermostatDevices, (m, d) =>
          # Already had a match with another device?
          if assistantThermostatDevice? and assistantThermostatDevice.config.id isnt d.config.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          @assistantThermostatDevice = d
        )
        .or([
          ((m) =>
            return m.match(' heat', (m)=>
              setCommand('heat')
              match = m.getFullMatch()    
            )            
          ),
          ((m) =>
            return m.match(' heatcool', (m)=>
              setCommand('heatcool')
              match = m.getFullMatch()
            )             
          ),
          ((m) =>
            return m.match(' cool', (m)=>
              setCommand('cool')
              match = m.getFullMatch()
            )             
          ),
          ((m) =>
            return m.match(' eco', (m)=>
              setCommand('eco')
              match = m.getFullMatch()
            )           
          ),
          ((m) =>
            return m.match(' off', (m)=>
              setCommand('off')
              match = m.getFullMatch()
            )              
          ),
          ((m) =>
            return m.match(' on', (m)=>
              setCommand('on')
              match = m.getFullMatch()
            )              
          )
          ((m) =>
            return m.match(' setpoint ')
              .matchNumber(setpoint)
          ),
          ((m) =>
            return m.match(' setpoint low ')
              .matchNumber(setpointlow)
          ),
          ((m) =>
            return m.match(' setpoint high ')
              .matchNumber(setpointhigh)
          ),
          ((m) =>
            return m.match(' program ')
              .or([
                ((m) =>
                  return m.match(' manual', (m)=>
                    setCommand('manual')
                    match = m.getFullMatch()
                  )              
                ),
                ((m) =>
                  return m.match(' schedule', (m)=>
                    setCommand('schedule')
                    match = m.getFullMatch() 
                  )              
                )
              ])
          )
        ])

      match = m.getFullMatch()
      if match?
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new AssistantThermostatActionHandler(@framework, @assistantThermostatDevice, @command, @parameters)
        }
      else
        return null

  class AssistantThermostatActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @assistantThermostatDevice, @command, @parameters) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have cleaned \"%s\"", "")
      else
        @assistantThermostatDevice.execute(@assistantThermostatDevice, @command, @parameters)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )

  plugin = new AssistantPlugin
  return plugin
