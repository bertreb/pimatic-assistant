# pimatic-assistant
Plugin for connecting a Pimatic system via Nora to Google Assistant

Background
-------
The Assistant plugin lets you connect a Pimatic home automation system with a Google assistant via Nora.
Nora is a **NO**de-**R**ed home **A**utomation solution build by [Andrei Tatar](https://github.com/andrei-tatar). Nora consists of a plugin for Node-red and the Nora server that acts as a gateway between Node-red and Google Assistant.
For this plugin I'm not using node-red but use the Nora server directly.
This plugin is also based on the work done for the Pimatic-gBridge plugin. Because the gBridge service is stopped, this plugin will be a good replacement.

------

Before you can configure the plugin you need to get a Nora service token. The steps are:

- Go to the [NORA homepage](https://node-red-google-home.herokuapp.com/)
- Login with your Google or Github account
- Copy the generated token in your clipboard, to be used later in the plugin



Link Nora to Google Home in the the Google Home app. (These steps need to happen only once)


Devices are not exposed automatically to Nora and Google Assistant. You have to add them individually in the config.


Installation
------------
To enable the Assistant plugin add this to the plugins section via the GUI or add it in the config.json file.

```
{
  plugin: "assistant"
  debug: "Debug mode. Writes debug messages to the pimatic log."
}
```

Assistant device
-----------------
After the plugin is installed an Assistant device can be added. When you add/remove a supported Pimatic device to the Assistant devicelist, the device is automatically added/removed in Nora and Google Assistant.

Below the settings with the default values. In the devices your configure which Pimatic devices will be controlled by Google Assistant and what name they get. The name is visible in the Google Assistant and is the name you use in voice commands.
In this release the SwitchActuator, DimmerActuator, ButtonsDevice, ShutterController, Milight (RGBWZone and FullColorZone) and HeatingThermostat based Pimatic devices are supported.
When there's at least 1 device in the config, the dot will go present after a connection to Nora is made.

Some specific configurations:
#### Shutter
For the Shutter device the auxiliary field is used to control a shutter via a shell script. The position of the shutter (the value) is added at the end of the script (with a space) before executing the script. A return value is used as actual shutter position.

#### Milight / Light
For the Milight devices automatic configuration is not implemented. You need to configure the milight device in gBridge (with the traits 'OnOff', 'Brightness' and 'colorsettingrgb') and after that configure(add) the milight device in config of the gBridge device in Pimatic. The name you used for the Milight device in gBridge must by exactly the same as the name in pimatic gBridge! When you want to change the name of a Milight device you have to reinstall it in gBridge (because automatic configuration isn't supported)

#### Thermostat
For the HeatingThermostat you can add a temperature/humidity sensor. In the auxiliary field, add the device-id of the temperature/humidity sensor. The sensor needs to have 'temperature' and 'humidity' named attributes. If the attribute names are different, you can put a variables devices 'in between' (which converts the attribute names to 'temperature' and 'humidity').
The heating device is only using the temperature setting of the device.
The following modes are supported: off, heat and eco.


Device configuration
-----------------

```
{
  "id": "<assistant-device-id>",
  "class": "AssistantDevice",
  	token:    "The token from Nora"
    devices:  "list of devices connected to Google Assistant"
      name:                 "the gBridge device name, and command used in Google Assistant"
      roomHint:				"the optional roomname used in Google Assistant"
      pimatic_device_id:    "the ID of the pimatic device"
      pimatic_subdevice_id: "the ID of a pimatic subdevice, only needed for a button id"
      auxiliary:            "adapter specific field to add functionality"
      auxiliary2:            "2nd adapter specific field to add functionality"
      twofa:                 "Two-step confirmation. Google Assistant will ask for confirmation"
                              ["none", "ack"] default: "none"
}
```

#### Deleting an Assistant device
Before you delete an Assistant device, please remove first all devices in the config and save the config. After that you can delete the Assistant device.

-----------------

The minumum node requiredment for this plugin is Node v8. You could backup Pimatic before you are using this plugin!
