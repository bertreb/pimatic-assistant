$(document).on 'templateinit', (event) ->

  class AssistantThermostatItem extends pimatic.DeviceItem

    constructor: (templData, @device) ->
      super(templData, @device)

      # The value in the input
      @inputValue = ko.observable()
      @inputValue2 = ko.observable()
      @inputValue3 = ko.observable()

      # temperatureSetpoint changes -> update input + also update buttons if needed
      @stAttr = @getAttribute('temperatureSetpoint')
      @stAttr2 = @getAttribute('temperatureSetpointLow')
      @stAttr3 = @getAttribute('temperatureSetpointHigh')
      @inputValue(@stAttr.value())
      @inputValue2(@stAttr2.value())
      @inputValue3(@stAttr3.value())

      attrValue = @stAttr.value()
      @stAttr.value.subscribe( (value) =>
        @inputValue(value)
        attrValue = value
      )

      attrValue2 = @stAttr2.value()
      @stAttr2.value.subscribe( (value) =>
        @inputValue2(value)
        attrValue2 = value
      )

      attrValue3 = @stAttr3.value()
      @stAttr3.value.subscribe( (value) =>
        @inputValue3(value)
        attrValue3 = value
      )

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue = @inputValue()
        if textValue? and attrValue? and parseFloat(attrValue) isnt parseFloat(textValue)
          @changeTemperatureTo(parseFloat(textValue))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue2 = @inputValue2()
        if textValue2? and attrValue2? and parseFloat(attrValue2) isnt parseFloat(textValue2)
          @changeTemperatureLowTo(parseFloat(textValue2))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue3 = @inputValue3()
        if textValue3? and attrValue3? and parseFloat(attrValue3) isnt parseFloat(textValue3)
          @changeTemperatureHighTo(parseFloat(textValue3))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      @synced = @getAttribute('synced').value

    afterRender: (elements) ->
      super(elements)

      # find the buttons
      @heatButton = $(elements).find('[name=heatButton]')
      @heatcoolButton = $(elements).find('[name=heatcoolButton]')
      @coolButton = $(elements).find('[name=coolButton]')
      @offButton = $(elements).find('[name=offButton]')
      @ecoButton = $(elements).find('[name=ecoButton]')
      @onButton = $(elements).find('[name=onButton]')
      @manualButton = $(elements).find('[name=manualButton]')
      @autoButton = $(elements).find('[name=autoButton]')
      @input = $(elements).find('[name=spin]')
      @input.spinbox()
      @input2 = $(elements).find('[name=spin2]')
      @input2.spinbox()
      @input3 = $(elements).find('[name=spin3]')
      @input3.spinbox()

      @updatePowerButtons()
      @updateEcoButton()
      @updateModeButtons()
      @updateProgramButtons()
      @updatePreTemperature()

      @getAttribute('mode')?.value.subscribe( => @updateModeButtons() )
      @getAttribute('power')?.value.subscribe( => @updatePowerButtons() )
      @getAttribute('program')?.value.subscribe( => @updateProgramButtons() )
      @getAttribute('eco')?.value.subscribe( => @updateEcoButton() )
      @stAttr.value.subscribe( => @updatePreTemperature() )
      #@stAttrLow.value.subscribe( => @updatePreTemperature() )
      #@stAttrHigh.value.subscribe( => @updatePreTemperature() )
      return

    # define the available actions for the template
    modeHeat: -> @changeModeTo "heat"
    modeHeatCool: -> @changeModeTo "heatcool"
    modeCool: -> @changeModeTo "cool"
    modeOff: -> @changePowerTo false
    #modeEco: -> @changePowerTo "eco"
    modeEcoToggle: -> @toggleEco ""
    modeOn: -> @changePowerTo true
    modeManual: -> @changeProgramTo "manual"
    modeAuto: -> @changeProgramTo "auto"
    setTemp: -> @changeTemperatureTo "#{@inputValue.value()}"
    setTempLow: -> @changeTemperatureLowTo "#{@inputValue2.value()}"
    setTempHigh: -> @changeTemperatureHighTo "#{@inputValue3.value()}"

    updateModeButtons: ->
      modeAttr = @getAttribute('mode')?.value()
      switch modeAttr
        when 'heat'
          @heatButton.addClass('ui-btn-active')
          @heatcoolButton.removeClass('ui-btn-active')
          @coolButton.removeClass('ui-btn-active')
          @input.spinbox('enable')
          @input2.spinbox('disable')
          @input3.spinbox('disable')
        when 'heatcool'
          @heatButton.removeClass('ui-btn-active')
          @heatcoolButton.addClass('ui-btn-active')
          @coolButton.removeClass('ui-btn-active')
          @input.spinbox('disable')
          @input2.spinbox('enable')
          @input3.spinbox('enable')
        when 'cool'
          @heatButton.removeClass('ui-btn-active')
          @heatcoolButton.removeClass('ui-btn-active')
          @coolButton.addClass('ui-btn-active')
          @input.spinbox('enable')
          @input2.spinbox('disable')
          @input3.spinbox('disable')
      return

    updateEcoButton: ->
      ecoAttr = @getAttribute('eco')?.value()
      if ecoAttr is true
        @ecoButton.addClass('ui-btn-active')
      else
        @ecoButton.removeClass('ui-btn-active')
      return

    updateProgramButtons: ->
      programAttr = @getAttribute('program')?.value()
      switch programAttr
        when 'manual'
          @manualButton.addClass('ui-btn-active')
          @autoButton.removeClass('ui-btn-active')
        when 'auto'
          @manualButton.removeClass('ui-btn-active')
          @autoButton.addClass('ui-btn-active')
      return

    updatePowerButtons: ->
      powerAttr = @getAttribute('power')?.value()
      if powerAttr is false
        @offButton.addClass('ui-btn-active')
        @onButton.removeClass('ui-btn-active')
      else
        @offButton.removeClass('ui-btn-active')
        @onButton.addClass('ui-btn-active')
      return

    updatePreTemperature: ->
      return
      if parseFloat(@stAttr.value()) is parseFloat("#{@device.config.ecoTemp}")
        @boostButton.removeClass('ui-btn-active')
        @comfyButton.removeClass('ui-btn-active')
      else if parseFloat(@stAttr.value()) is parseFloat("#{@device.config.comfyTemp}")
        @boostButton.removeClass('ui-btn-active')
        @comfyButton.addClass('ui-btn-active')
      else
        @comfyButton.removeClass('ui-btn-active')
      return

    changeModeTo: (mode) ->
      @device.rest.changeModeTo({mode}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changePowerTo: (power) ->
      @device.rest.changePowerTo({power}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    toggleEco: () ->
      @device.rest.toggleEco({},global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeProgramTo: (program) ->
      @device.rest.changeProgramTo({program}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeTemperatureTo: (temperatureSetpoint) ->
      @input.spinbox('disable')
      @device.rest.changeTemperatureTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input.spinbox('enable') )

    changeTemperatureLowTo: (temperatureSetpoint) ->
      @input2.spinbox('disable')
      @device.rest.changeTemperatureLowTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input2.spinbox('enable') )

    changeTemperatureHighTo: (temperatureSetpoint) ->
      @input3.spinbox('disable')
      @device.rest.changeTemperatureHighTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input3.spinbox('enable') )

  # register the item-class
  pimatic.templateClasses['assistantthermostat'] = AssistantThermostatItem
