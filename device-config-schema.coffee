module.exports = {
  title: "pimatic-assistant device config schemas"
  AssistantDevice: {
    title: "Assistant config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      devices:
        description: "list of  devices connected to Google Assistant"
        format: "table"
        type: "array"
        default: []
        required: ["name", "pimatic_device_id"]
        items:
          type: "object"
          properties:
            name:
              descpription: "The device name used in Google Assistant"
              type: "string"
            roomHint:
              description: "The roomHint used for grouping devices to a room in Google Assistant"
              type: "string"
            pimatic_device_id:
              descpription: "The pimatic device ID"
              type: "string"
            pimatic_subdevice_id:
              description: " The ID of the subdevice like a button name"
              type: "string"
            auxiliary:
              description: "Adapter specific field to add functionality"
              type: "string"
            auxiliary2:
              description: "Adapter specific field to add 2nd functionality"
              type: "string"
            twofa:
              description: "Two-step confirmation. When ack or pin Google Assistant will ask for confirmation"
              enum: ["none", "ack", "pin"]
            pin:
              description: "The pin for Two-step pin confirmation. Google Assistant will ask for confirmation"
              type: "string"
              default: "0000"
  }
  AssistantThermostat: {
    title: "AssistantThermostat config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      minThresholdCelsius:
        description: "supported minimum temperature range for this device (in degrees Celsius)"
        type: "number"
        default: 5
      maxThresholdCelsius:
        description: "supported maximum temperature range for this device (in degrees Celsius)"
        type: "number"
        default: 30
      thermostatTemperatureUnit:
        description: "The unit the device is set to by default"
        enum: ["C","F"]
        default: "C"
      bufferRangeCelsius:
        description: "Specifies the minimum offset between heat-cool setpoints in Celsius, if heatcool mode is supported"
        type: "number"
        default: 2
      temperatureDevice:
        description: "The Pimatic device.temperature id for the thermostat room temperature"
        type: "string"
      humidityDevice:
        description: "The Pimatic device.humidity id for the thermostat room humidity"
        type: "string"
      pid:
        description: "Enable the PID controller for heater and cooler"
        type: "boolean"
        default: false
  }
}
