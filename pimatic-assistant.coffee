module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'

  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  lightColorAdapter = require('./adapters/lightcolor')(env)
  buttonAdapter = require('./adapters/button')(env)
  shutterAdapter = require('./adapters/shutter')(env)
  heatingThermostatAdapter = require('./adapters/heatingthermostat')(env)
  ###
  contactAdapter = require('./adapters/contact')(env)
  temperatureAdapter = require('./adapters/temperature')(env)
  #sceneAdapter = require('./adapters/scene')(env)
  ###

  io = require('socket.io-client')
  _ = require('lodash')


  class AssistantPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-assistant-config-schema'
      @configProperties = pluginConfigDef.properties

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
      @group = "pimatic"

      @devMgr = @framework.deviceManager

      @handlers = {}

      checkMultipleDevices = []
      @configDevices = []
      for _device in @config.devices
        do(_device) =>
          if _.find(checkMultipleDevices, (d) => d.pimatic_device_id is _device.pimatic_device_id and d.pimatic_subdevice_id is _device.pimatic_device_id)?
            throw new Error "#{_device.pimatic_device_id} is already used"
          else
            checkMultipleDevices.push _device
          @configDevices.push _device

      version = "0.0.34" # is latest node-red-nora-contrib version
      notify = true
      uri = 'https://node-red-google-home.herokuapp.com/?' + 
        'version=' + version + 
        '&token=' + encodeURIComponent(@config.token) + 
        '&notify=' + notify + 
        '&group=' + encodeURIComponent(@group)

      @socket = io(uri) if _.size(@configDevices) > 0
  
      @socket.on 'connect', () =>
        env.logger.debug "NORA - connected to Nora server"
        @_setPresence(true)
        @getSyncDevices(@configDevices)
        .then((syncDevices)=>
          @socket.emit('sync', syncDevices, 'req:sync')
          env.logger.debug "NORA - devices synced: " + JSON.stringify(syncDevices,null,2)
        )

      @socket.on 'disconnect', =>
        env.logger.debug "NORA - disconnected from Nora server"
        @_setPresence(false)
      
      @socket.on 'update', (changes) => 
        env.logger.debug "NORA - update received " + JSON.stringify(changes,null,2)
        @handleUpdate(changes)
        .then((result)=>
        )

      @socket.on 'action-error', (reqId, msg) =>
        env.logger.debug "NORA - action-error received, reqId " + reqId + ", msg: " + JSON.stringify(msg,null,2)

      @socket.on 'activate-scene', (ids, deactivate) =>
        env.logger.debug "NORA - activate-scene, ids " + JSON.stringify(ids,null,2) + ", deactivate: " + deactivate

      @framework.on "deviceRemoved", (device) =>
        if _.find(@config.devices, (d) => d.pimatic_device_id == device.id)
          #throw new Error "Please remove device also in Assistant"
          env.logger.info "please remove device also in Assistant!"

      super()

    updateState: (id, newState) =>
      _a = {}
      _a[id] = newState
      @socket.emit('update', _a, "req:" + id)


    getSyncDevices: (configDevices) =>
      return new Promise((resolve,reject) =>
        devices = {}
        for _device, key in configDevices
          pimaticDevice = @devMgr.getDeviceById(_device.pimatic_device_id)
          if pimaticDevice?
            _adapterConfig =
              id: _device.pimatic_device_id
              pimaticDevice: pimaticDevice
              updateState: @updateState
              pimaticSubDeviceId: _device.pimatic_subdevice_id
              auxiliary: _device.auxiliary
              auxiliary2: _device.auxiliary2
              twoFa: _device.twofa
            #twoFaPin: if _value.twofaPin? then _value.twofaPin else undefined
            ###
            if pimaticDevice.config.class is "MilightRGBWZone" or pimaticDevice.config.class is "MilightFullColorZone"
              env.logger.debug "Add MilightRGBWZone adapter with ID: " + pimaticDevice.id
            ###
            #else if pimaticDevice.config.class is "ShellSwitch"
            #  env.logger.debug "Add scene adapter with ID: " + pimaticDevice.id
            #  @addAdapter(new sceneAdapter(_adapterConfig))
          
            if (pimaticDevice.config.class).indexOf("Dimmer") >= 0
              env.logger.debug "Light device found"
              _newDevice = new lightAdapter(_adapterConfig)
              devices[_device.pimatic_device_id] = 
                type: _newDevice.getType()
                brightnessControl: true
                turnOnWhenBrightnessChanges: false
                colorControl: false
                name: _device.name
                state: _newDevice.getState()
              devices[_device.pimatic_device_id]["roomHint"] = _device.roomHint if _device.roomHint?
              @handlers[_device.pimatic_device_id] = _newDevice

            else if (pimaticDevice.config.class).indexOf("RGB") >= 0
              env.logger.debug "Light device found"
              _newDevice = new lightColorAdapter(_adapterConfig)
              devices[_device.pimatic_device_id] = 
                type: _newDevice.getType()
                brightnessControl: true
                turnOnWhenBrightnessChanges: false
                colorControl: true
                name: _device.name
                state: _newDevice.getState()
              devices[_device.pimatic_device_id]["roomHint"] = _device.roomHint if _device.roomHint?
              @handlers[_device.pimatic_device_id] = _newDevice

            else if (pimaticDevice.config.class).indexOf("Switch") >= 0
              env.logger.debug "Switch device found"
              _newDevice = new switchAdapter(_adapterConfig)
              devices[_device.pimatic_device_id] = 
                type: _newDevice.getType()
                name: _device.name
                state: _newDevice.getState()
              devices[_device.pimatic_device_id]["roomHint"] = _device.roomHint if _device.roomHint?
              @handlers[_device.pimatic_device_id] = _newDevice

            else if pimaticDevice instanceof env.devices.ButtonsDevice
              env.logger.debug "Buttons device found"
              _newDevice = new buttonAdapter(_adapterConfig)
              devices[_device.pimatic_device_id] = 
                type: _newDevice.getType()
                name: _device.name
                state: _newDevice.getState()
              devices[_device.pimatic_device_id]["roomHint"] = _device.roomHint if _device.roomHint?
              @handlers[_device.pimatic_device_id] = _newDevice

              ###
              else if pimaticDevice instanceof env.devices.Sensor and pimaticDevice.hasAttribute('contact')
                env.logger.debug "Add contact adapter with ID: " + pimaticDevice.id
                @addAdapter(new contactAdapter(_adapterConfig))
              ###

            else if pimaticDevice instanceof env.devices.DummyHeatingThermostat
              env.logger.debug "Thermostat device found"
              #add thermostat and humidity devices
              @ambiantDevice = if _device.auxiliary? then @devMgr.getDeviceById(_device.auxiliary) else null
              _adapterConfig["auxiliary"] = @ambiantDevice
              _newDevice = new heatingThermostatAdapter(_adapterConfig)
              devices[_device.pimatic_device_id] = 
                type: _newDevice.getType()
                name: _device.name
                state: _newDevice.getState()
                temperatureUnit: "C"
                bufferRangeCelsius: 2
                commandOnlyTemperatureSetting: false
                queryOnlyTemperatureSetting: false
              devices[_device.pimatic_device_id]["availableModes"] = _newDevice.getModes()
              devices[_device.pimatic_device_id]["roomHint"] = _device.roomHint if _device.roomHint?
              #devices[_device.pimatic_device_id]["auxiliary"] = _newDevice.getAmbiant() if @ambiantDevice?
              @handlers[_device.pimatic_device_id] = _newDevice

            else if pimaticDevice instanceof env.devices.ShutterController
              env.logger.debug "Shutter device found"
              _newDevice = new shutterAdapter(_adapterConfig)
              devices[_device.pimatic_device_id] = 
                type: _newDevice.getType()
                name: _device.name
                state: _newDevice.getState()
              devices[_device.pimatic_device_id]["roomHint"] = _device.roomHint if _device.roomHint?
              @handlers[_device.pimatic_device_id] = _newDevice

              ###
              else if pimaticDevice.hasAttribute(_value.auxiliary)
                env.logger.debug "Add temperature adapter with ID: " + pimaticDevice.id
                @addAdapter(new temperatureAdapter(_adapterConfig))
              ###

            else
              env.logger.debug "Device type does not exist"
        resolve(devices)
      )

    handleUpdate: (changes) =>
      return new Promise((resolve,reject)=>
        for key, value of changes
          @handlers[key].executeAction(value)
        resolve()
      )

    destroy: ->
      @socket.disconnect()
      @socket.removeAllListeners()
      @_setPresence(false)
      super()


  plugin = new AssistantPlugin
  return plugin
