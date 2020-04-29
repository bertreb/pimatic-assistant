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
              descpription: "the assistant device name, and command used in GoogleAssistant"
              type: "string"
              required: true
            roomHint:
              description: "The roomHint used for grouping devices to a room"
              type: "string"
              required: false
            pimatic_device_id:
              descpription: "the pimatic device ID"
              type: "string"
              required: true
            pimatic_subdevice_id:
              description: " the ID of the subdevice like a button name"
              type: "string"
              required: false
            auxiliary:
              description: "adapter specific field to add functionality to the bridge"
              type: "string"
              required: false
            auxiliary2:
              description: "adapter specific field to add 2nd functionality to the bridge"
              type: "string"
              required: false
            twofa:
              description: "Two-step confirmation. Google Assistant will ask for confirmation"
              enum: ["none", "ack"]
  }
}
