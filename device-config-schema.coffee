module.exports = {
  title: "pimatic-assistant device config schemas"
  AssistantDevice: {
    title: "Assistant config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      token:
        description: "the NORA token"
        type: "string"
      devices:
        description: "list of devices connected to Google Assistant"
        format: "table"
        type: "array"
        default: []
        items:
          type: "object"
          properties:
            name:
              descpription: "The device name used in Google Assistant"
              type: "string"
              required: true
            roomHint:
              description: "The roomHint used for grouping devices to a room in Google Assistant"
              type: "string"
              required: false
            pimatic_device_id:
              descpription: "The pimatic device ID"
              type: "string"
              required: true
            pimatic_subdevice_id:
              description: " The ID of the subdevice like a button name"
              type: "string"
              required: false
            auxiliary:
              description: "Adapter specific field to add functionality"
              type: "string"
              required: false
            auxiliary2:
              description: "Adapter specific field to add 2nd functionality"
              type: "string"
              required: false
            twofa:
              description: "Two-step confirmation. Google Assistant will ask for confirmation"
              enum: ["none", "ack"]
  }
}
