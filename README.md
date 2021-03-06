# pimatic-assistant
Plugin for connecting a Pimatic system via Nora to Google Assistant

Background
-------
The Assistant plugin lets you connect a Pimatic home automation system to a Google assistant via Nora.


Nora is a **NO**de-**R**ed home **A**utomation solution for connecting Node-red to Google Home/Assistant. Nora is build by [Andrei Tatar](https://github.com/andrei-tatar). Nora consists of a plugin for Node-red and the Nora backend server that acts as a gateway between Node-red and Google Assistant.
For this plugin I'm not using node-red but use the Nora backend server directly.
This plugin is also based on the work done for the Pimatic-gBridge plugin. Because the gBridge service is stopped, this plugin will be a good replacement.

The Assistant Device interfaces with Google Assistant via Nora. Pimatic devices are added in the config. The mapping of states and actions from Pimatic from/to Google Assistant is done as best as possible.

Preparation
---------
Before you can configure the plugin you need to get a Nora service token. The steps are:

- Go to the [NORA homepage](https://node-red-google-home.herokuapp.com/)
- Login with your Google or Github account
- Copy the generated token in your clipboard, to be used later in the device config of the plugin.

Link Nora to your Google Home via the Google Home app (these steps need to happen only once).
The steps are:
- Open your Google Home app and click Add
- In the Add and manage screen, select Set up device
- Select 'Have something already set up?'
- Search and select 'NORA' and login again with the Google/Github account you used when logging in to the NORA homepage.

Done! Nora and Google Home are linked and you can install the plugin and add an Assistant device.
Pimatic devices are not exposed automatically to Nora and Google Assistant. You have to add or remove them individually in the device config.


Installation
------------
To enable the Assistant plugin add this to the plugins section via the GUI or add it in the config.json file.

```
{
  plugin: "assistant"
  token:  "The token from Nora"
  debug:  "Debug mode. Writes debug messages to the pimatic log."
}
```

After the plugin is installed an Assistant device or an Assistant Thermostat device can be added.

Assistant device
-----------------
The Assistant device is the main device for adding Pimatic devices to Google Assistant. When you add/remove a supported Pimatic device to the Assistant devicelist, the device is automatically added/removed in Nora and Google Assistant.

Below the settings with the default values. In the devices your configure which Pimatic devices will be controlled by Google Assistant and what name they get. The name is visible in the Google Assistant and is the name you use in voice commands.
In this release the SwitchActuator, DimmerActuator, ButtonsDevice, ShutterController, Milight (RGBWZone and FullColorZone) and HeatingThermostat based Pimatic devices are supported.
When there's at least 1 device added, the connection to Nora is made. When connected the dot will go to present.

Some specific configurations:
#### Button
For the Buttons device the auxiliary field is used to identify the button. The id of the button can not contain a hyphen ('-'). You can use an underscore to make the id readable.

#### Shutter
For the Shutter device the auxiliary field is used to control a shutter via a shell script. The position of the shutter (the value) is added at the end of the script (with a space) before executing the script. A return value is used as actual shutter position.

#### Thermostat
For the HeatingThermostat you can add a temperature/humidity sensor. In the auxiliary field, add the device-id of the temperature/humidity sensor. The sensor needs to have 'temperature' and 'humidity' named attributes. If the attribute names are different, you can put a variables devices 'in between' (which converts the attribute names to 'temperature' and 'humidity').
The heating device is only using the temperature setting of the device.
The following modes are supported: off and heat.

Starting from version 0.2.11 you can use the DummyThermostat. This is an extended Thermostat that uses all the functionality of Google Assistant. DummyThermostat is part of the pimatic-dummis plugin.

#### Temperature
The temperature/humidity sensor is not supported directly by Nora and Google Assistant. This temperature/humidity sensor via implemented via a DummyThermostat.
The configuration is as follows:
- pimatic_device_id: the Temp/Hum device-id of the Pimatic Sensor
- auxiliary: the attribute name of the temperature attribute of the Pimatic sensor. Can be 'temperature' or 'TEMP' or whatever the teperature device is using.
- auxiliary2: if available the attribute name of the humidity attribute of the Pimatic sensor (the name of the humidity attribute the device is using).

In the Google Assistant (or Home app) you hear/see a thermostat device with the same ambiant(room) and setpoint temperature. This value is the temperature value of your Pimatic sensor.


Device configuration
-----------------

```
{
  id:     "<assistant-device-id>"
  class:  "AssistantDevice"
    group:    "name for grouping the devices of this assistant device (default = 'pimatic')"
    devices:  "list of devices connected to Google Assistant"
      name:                 "the device name, and command used in Google Assistant"
      roomHint:             "the optional roomname used in Google Assistant"
      pimatic_device_id:    "the ID of the pimatic device"
      pimatic_subdevice_id: "the ID of a pimatic subdevice, only needed for a button id"
      auxiliary:            "adapter specific field to add functionality"
      auxiliary2:            "2nd adapter specific field to add functionality"
      twofa:                 "Two-step confirmation. Google Assistant will ask for confirmation"
                              ["none", "ack", "pin"] default: "none"
      pin:                  "when twofa "pin" is used, the pin string (default: '0000')"
}
```

#### Group
You can have 3 simultaneous connections with the nora-backend. So 3 different sources can provide the devices towards Google home. A group name is linked to one connection. The token is the same for all connections. 
#### Two-step confirmation
2-step confirmation (twofa) is supported. When you enable twofa you can use "ack", the assistant will ask if you are sure you what to execute the action. When you enable "pin", Google Assistant will ask for the pin to confirm the action. You need to enter the pin via the 'keyboard'.

#### Deleting an Assistant device
Before you delete an Assistant device, please remove first all devices in the Assistant device config and save the config. After that you can delete the Assistant device.


-----------------

The minimum node requirement for this plugin is Node v8. You could backup Pimatic before you are using this plugin!
