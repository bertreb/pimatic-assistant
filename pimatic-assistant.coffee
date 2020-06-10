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
  temperatureAdapter = require('./adapters/temperature')(env)
  # vacuumAdapter = require('./adapters/vacuum')(env)
  # assistantThermostatAdapter = require('./adapters/assistantthermostat')(env)
  # contactAdapter = require('./adapters/contact')(env)
  # sceneAdapter = require('./adapters/scene')(env)

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
      @nrOfDevices = 0
      @framework.variableManager.waitForInit()
      .then(()=>
        for _device in @config.devices
          do(_device) =>
            if _.find(checkMultipleDevices, (d) => d.pimatic_device_id is _device.pimatic_device_id and d.pimatic_subdevice_id is _device.pimatic_device_id)?
              env.logger.info "Pimatic device '#{_device.pimatic_device_id}' is already used"
            else
              _fullDevice = @framework.deviceManager.getDeviceById(_device.pimatic_device_id)
              if _fullDevice?
                if @selectAdapter(_fullDevice, _device.auxiliary, _device.auxiliary2)?
                  if _fullDevice.config.class is "ButtonsDevice"
                    _button = _.find(_fullDevice.config.buttons, (b) => _device.pimatic_subdevice_id == b.id)
                    if _button?
                      checkMultipleDevices.push _device
                      @configDevices.push _device
                    else
                      #throw new Error "Please remove button in Assistant"
                      env.logger.info "Please remove button also in Assistant!"
                  else
                    checkMultipleDevices.push _device
                    @configDevices.push _device
                else
                  env.logger.info "Pimatic device class '#{_fullDevice.config.class}' is not supported"                  
              else
                env.logger.info "Pimatic device '#{_device.pimatic_device_id}' does not excist"
                
        @nrOfDevices = _.size(@configDevices)
        env.logger.debug "Number of devices: " + @nrOfDevices + ", " + JSON.stringify(@configDevices,null,2)
        @initNoraConnection()
      )


      @framework.on "deviceRemoved", (device) =>
        if _.find(@config.devices, (d) => d.pimatic_device_id == device.id or d.pimatic_subdevice_id == device.id)
          #throw new Error "Please remove device also in Assistant"
          env.logger.info "Please remove device also in Assistant!"

      @framework.on "deviceChanged", (device) =>
        if device.config.class is "ButtonsDevice"
          _device = _.find(@config.devices, (d) => d.pimatic_device_id == device.id)
          if _device?
            unless _.find(device.config.buttons, (b)=> b.id == _device.pimatic_subdevice_id)
              #throw new Error "Please remove device also in Assistant"
              env.logger.info "Please remove button also in Assistant!"

      #if @socket.connected then @_setPresence(true) else @_setPresence(false)

      super()

    updateState: (id, newState) =>
      _a = {}
      _a[id] = newState
      env.logger.debug "updateState: " + JSON.stringify(_a,null,2)
      @socket.emit('update', _a, "req:" + id)

    initNoraConnection: () =>

      @socket = io(@uri, {autoConnect:true, reconnection:true, reconnectionDelay:20000, randomizationFactor:0.2})

      @socket.on 'connect', () =>
        env.logger.debug "NORA - connected to Nora server"
        @getSyncDevices(@configDevices)
        .then((syncDevices)=>
          @socket.emit('sync', syncDevices, 'req:sync')
          @nrOfDevices = _.size(syncDevices)
          env.logger.debug "NORA - after device start, devices synced: " + @nrOfDevices
          if @nrOfDevices > 0
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
        env.logger.debug "GUARD: Interval check, nrOfDevices: " + @nrOfDevices
        if @nrOfDevices is 0
          env.logger.debug "GUARD: stopping, nr of devices is #{@nrOfDevices}"
          return
        if not @socket? or @socket.connected is false
          env.logger.debug "GUARD: Nora not connected, try to force re-connect"
          @socket.close()
          @socket.removeAllListeners()
          @socket = null
          @initNoraConnection()
        else
          env.logger.debug "GUARD: Nora connected"
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
            switch @selectAdapter(pimaticDevice, _device.auxiliary, _device.auxiliary2)
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
                #when "vacuum"
                #_newDevice = new vacuumAdapter(_adapterConfig)
                #devices[gaDeviceId] =
                #  pausable: true
              when "temperature"
                _newDevice = new temperatureAdapter(_adapterConfig)
                devices[gaDeviceId] =
                  temperatureUnit: "C"
                  bufferRangeCelsius: pimaticDevice.bufferRangeCelsius
                  commandOnlyTemperatureSetting: false
                  queryOnlyTemperatureSetting: true
                  availableModes: _newDevice.getModes()
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

    selectAdapter: (pimaticDevice, aux1, aux2) ->
      _foundAdapter = null
      if pimaticDevice.config.class is "MilightRGBWZone" or pimaticDevice.config.class is "MilightFullColorZone"
        _foundAdapter = "lightColorMilight"
      else if ((pimaticDevice.config.class).toLowerCase()).indexOf("rgb") >= 0
        _foundAdapter = "lightColor"
      else if ((pimaticDevice.config.class).toLowerCase()).indexOf("ct") >= 0
        _foundAdapter = "lightTemperature"
      else if (pimaticDevice.config.class).indexOf("Dimmer") >= 0
        _foundAdapter = "light"
      else if ((pimaticDevice.config.id).toLowerCase()).indexOf("vacuum") >= 0
        _foundAdapter = "vacuum"
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
      else if pimaticDevice.hasAttribute(aux1)
        _foundAdapter = "temperature"

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

  plugin = new AssistantPlugin
  return plugin
