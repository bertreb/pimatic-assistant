# pimatic-assistant
Plugin for connecting a Pimatic system via Nora to Google Assistant

Background
-------
The Assistant plugin lets you connect a Pimatic home automation system with a Google assistant via Nora.


Nora is a **NO**de-**R**ed home **A**utomation solution for connecting Node-red to Google Home/Assistant. Nora is build by [Andrei Tatar](https://github.com/andrei-tatar). Nora consists of a plugin for Node-red and the Nora backend server that acts as a gateway between Node-red and Google Assistant.
For this plugin I'm not using node-red but use the Nora backend server directly.
This plugin is also based on the work done for the Pimatic-gBridge plugin. Because the gBridge service is stopped, this plugin will be a good replacement.

------

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
#### Shutter
For the Shutter device the auxiliary field is used to control a shutter via a shell script. The position of the shutter (the value) is added at the end of the script (with a space) before executing the script. A return value is used as actual shutter position.

#### Thermostat
For the HeatingThermostat you can add a temperature/humidity sensor. In the auxiliary field, add the device-id of the temperature/humidity sensor. The sensor needs to have 'temperature' and 'humidity' named attributes. If the attribute names are different, you can put a variables devices 'in between' (which converts the attribute names to 'temperature' and 'humidity').
The heating device is only using the temperature setting of the device.
The following modes are supported: off and heat.


Device configuration
-----------------

```
{
  "id": "<assistant-device-id>",
  "class": "AssistantDevice",
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
#### Two-step confirmation
2-step confirmation (twofa) is supported. When you enable twofa you can use "ack", the assistant will ask if you are sure you what to execute the action. When you enable "pin", Google Assistant will ask for the pin to confirm the action. You need to enter the pin via the 'keyboard'.

#### Deleting an Assistant device
Before you delete an Assistant device, please remove first all devices in the Assistant device config and save the config. After that you can delete the Assistant device.

Assistant Thermostat device
-----------------

The Assistant Thermostat device is a 'Dummy' device and supports several modes like 'heat, 'heatcool', 'cool' and 'eco'. With this device you can interface between Pimatic and Google Assistant for a maximum Thermostat experience. The Assistant Thermostat exposes several attributes and actions to be used in Pimatic.
The device interfaces with a room temperature and humidity device and sets status for switching heater or cooler on.




-----------------

The minumum node requiredment for this plugin is Node v8. You could backup Pimatic before you are using this plugin!
