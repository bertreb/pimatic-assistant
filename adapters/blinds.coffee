module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  childProcess = require("child_process")


  class ShutterAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      ###
      syncDevices: {
        "42474293.441c2c": {
          "type": "shutter",
          "name": "Shutter",
          "state": {
            "online": true,
            "openPercent": 0-100
          }
        }
      }
      ###
      @id = adapterConfig.id
      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @UpdateState = adapterConfig.updateState

      @positionCommand = adapterConfig.auxiliary

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @position = 0

      @device.on "position", devicePositionHandler
      @device.system = @
      @state =
        online: true
        openPercent: 0

      #@device.getPosition()
      #.then((position)=>
      #  @state.openPercent = position
      #  @UpdateState(@id, @state)
      #)

    devicePositionHandler = (position) ->
      # device status changed, updating device status in Nora
      switch position
        when "up"
          newPosition = @system.position + 10
          if newPosition > 100
            newPosition = 100
            env.logger.debug "Shutter already fully open"
          @system.updatePosition(newPosition)
        when "down"
          newPosition = @system.position - 10
          if newPosition < 0
            newPosition = 0
            env.logger.debug "Shutter already fully closed"
          @system.updatePosition(newPosition)
        when "stopped"
          env.logger.debug "Stopped received, no further action"
        else
          env.logger.debug "Unknown position command '#{position}' from '#{@system.id}'"


    executeAction: (change) ->
      # device status changed, updating device status in Nora
      env.logger.debug "Received action, change: " + JSON.stringify(change,null,2)
      @state.openPercent = change.openPercent
      #if @position is change.openPercent
      #  env.logger.debug "Shutter already in requested postion"
      #  return
      @changePositionTo(change.openPercent)

    changePositionTo: (value) =>
      if @positionCommand? and @positionCommand isnt ""
        value=Math.max(0,value)
        value = Math.min(100,value)
        command = @positionCommand + " #{value}"
        childProcess.exec(command, (err, stdout, stderr) =>
          if (err)
            #some err occurred
            env.logger.error "Error in Shutter adapter aux command " + err
            return
          else
            # the *entire* stdout and stderr (buffered)
            env.logger.debug "stdout: #{stdout}"
            env.logger.debug "stderr: #{stderr}"
            try
              returnJson = JSON.parse(stdout)
              if returnJson.current_pos?
                _position = Number returnJson.current_pos
              else if returnJson.position?
                _position = Number returnJson.position
            catch e
              env.logger.error "Return value from shutter unknown, " + e
              _position = 0

            @position = _position
            env.logger.debug "Received position: " + @position
        )
        env.logger.debug "Shutter moved from #{@position} to #{value}"
      else
        env.logger.debug "No position command set in config, shutter not moved"



    updatePosition: (newPosition) =>
      unless newPosition is @state.openPercent
        env.logger.debug "Update position to " + newPosition
        @state.openPercent = newPosition
        @position = newPosition
        @UpdateState(@id, @state)

    getType: () ->
      return "blinds"

    getState: () ->
      return @state

    destroy: ->
      @state.online = false;
      @system.updateState(@state)
      @device.removeListener "position", devicePositionHandler
