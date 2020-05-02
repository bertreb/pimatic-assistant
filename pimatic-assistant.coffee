module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'

  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  lightColorAdapter = require('./adapters/lightcolor')(env)
  lightTemperatureAdapter = require('./adapters/lighttemperature')(env)
  lightColorMilightAdapter = require('./adapters/lightcolormilight')(env)
  buttonAdapter = require('./adapters/button')(env)
  shutterAdapter = require('./adapters/shutter')(env)
  heatingThermostatAdapter = require('./adapters/heatingthermostat')(env)
  ###
  contactAdapter = require('./adapters/contact')(env)
  temperatureAdapter = require('./adapters/temperature')(env)
  sceneAdapter = require('./adapters/scene')(env)
  ###

  io = require('socket.io-client')
  _ = require('lodash')


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
      @initialized = false

      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('AssistantDevice', {
        configDef: deviceConfigDef.AssistantDevice,
        createCallback: (config, lastState) => new AssistantDevice(config, lastState, @framework, @)
      })

  class AssistantDevice extends env.devices.PresenceSensor

    constructor: (@config, lastState, @framework, @plugin) ->
      #@config = config
      @id = @config.id
      @name = @config.name

      if @_destroyed then return

      version = "0.0.34" # is latest node-red-nora-contrib version
      notify = true
      group = "pimatic"
      uri = 'https://node-red-google-home.herokuapp.com/?' +
        'version=' + version +
        '&token=' + encodeURIComponent(@plugin.config.token) +
        '&notify=' + notify +
        '&group=' + encodeURIComponent(group)

      @socket = io(uri, {reconnectionDelay:20000, randomizationFactor:0.2})

      @_presence = lastState?.presence?.value or off

      @devMgr = @framework.deviceManager

      @handlers = {}

      checkMultipleDevices = []
      @configDevices = []
      for _device in @config.devices
        do(_device) =>
          if _.find(checkMultipleDevices, (d) => d.pimatic_device_id is _device.pimatic_device_id and d.pimatic_subdevice_id is _device.pimatic_device_id)?
            throw new Error "Pimatic device '#{_device.pimatic_device_id}' is already used"
          else
            checkMultipleDevices.push _device
          @configDevices.push _device
          _fullDevice = @devMgr.getDeviceById(_device.pimatic_device_id)
          unless _fullDevice?
            throw new Error "Pimatic device '#{_device.pimatic_device_id}' does not excist"
          unless @selectAdapter(_fullDevice)?
            throw new Error "Pimatic device class '#{_fullDevice.config.class}' is not supported"

      @socket.on 'update', (changes) =>
        env.logger.debug "NORA - update received " + JSON.stringify(changes,null,2)
        @handleUpdate(changes)
        .then((result)=>
        )

      @socket.on 'action-error', (reqId, msg) =>
        env.logger.debug "NORA - action-error received, reqId " + reqId + ", msg: " + JSON.stringify(msg,null,2)

      @socket.on 'activate-scene', (ids, deactivate) =>
        env.logger.debug "NORA - activate-scene, ids " + JSON.stringify(ids,null,2) + ", deactivate: " + deactivate

      @framework.on 'after init', () =>
        @_setPresence(yes)
        env.logger.debug "NORA - connected to Nora server"
        @getSyncDevices(@configDevices)
        .then((syncDevices)=>
          @socket.emit('sync', syncDevices, 'req:sync')
          env.logger.debug "NORA - after init devices synced: " + JSON.stringify(syncDevices,null,2)
          if _.size(syncDevices)>0
            @_setPresence(true)
          else
            @socket.disconnect()
            @_setPresence(false)
        )
        @plugin.initialized = true

      @socket.on 'connect', () =>
        if @plugin.initialized
          @_setPresence(yes)
          env.logger.debug "NORA - connected to Nora server"
          @getSyncDevices(@configDevices)
          .then((syncDevices)=>
            @socket.emit('sync', syncDevices, 'req:sync')
            env.logger.debug "NORA - devices synced: " + JSON.stringify(syncDevices,null,2)
            if _.size(syncDevices)>0
              @_setPresence(true)
            else
              @socket.disconnect()
              @_setPresence(false)
          )

      ###
      @socket.on 'reconnect', () =>
        @_setPresence(yes)
        env.logger.debug "NORA - reconnected to Nora server"
        @getSyncDevices(@configDevices)
        .then((syncDevices)=>
          @socket.emit('sync', syncDevices, 'req:sync')
          env.logger.debug "NORA - devices synced: " + JSON.stringify(syncDevices,null,2)
        )
      ###

      @socket.on 'connect_error', () =>
        env.logger.debug "NORA - connect_error"
      @socket.on 'reconnect_error', () =>
        env.logger.debug "NORA - reconnect_error"
      @socket.on 'reconnect_failed', () =>
        env.logger.debug "NORA - reconnect_failed"

      @socket.on 'reconnecting', () =>
        env.logger.debug "Try to reconnect to Nora server..."
 
      @socket.on 'disconnect', () =>
        @_setPresence(no)
        env.logger.debug "NORA - disconnected from Nora server"

      @framework.on "deviceRemoved", (device) =>
        if _.find(@config.devices, (d) => d.pimatic_device_id == device.id)
          #throw new Error "Please remove device also in Assistant"
          env.logger.info "please remove device also in Assistant!"

      if @socket.connected then @_setPresence(true) else @_setPresence(false)

      super()

    updateState: (id, newState) =>
      _a = {}
      _a[id] = newState
      @socket.emit('update', _a, "req:" + id)

    toGA = (id) ->
      return id.replace('-','.')

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
                  bufferRangeCelsius: 2
                  commandOnlyTemperatureSetting: false
                  queryOnlyTemperatureSetting: false
                  availableModes: _newDevice.getModes()
              when "shutter"
                _newDevice = new shutterAdapter(_adapterConfig)
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
      else if pimaticDevice instanceof env.devices.ShutterController
        _foundAdapter = "shutter"

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
      super()


  plugin = new AssistantPlugin
  return plugin
