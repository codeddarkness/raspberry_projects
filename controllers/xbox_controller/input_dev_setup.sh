#!/usr/bin/env bash
# To use a PlayStation 3 controller in Python, you need the evdev library for handling input events. You can install it using:

if [[ "$(pip list 2>/dev/null | grep -q evdev ; echo $?)" -ne 0 ]] ; then
	pip install evdev
else
	echo " - already installed pip evdev"
fi

#Additionally, if you're running this on a Raspberry Pi, make sure the necessary Linux dependencies are installed:
#sudo apt install python3-pip python3-evdev joystick
update=0
for  app in python3-pip python3-evdev joystick; do
	if [[ $(dpkg --list | grep "${app}" | grep -q '^ii' >/dev/null ; echo $?) -ne 0 ]] ; then
		if [[ $update -eq 0 ]] ; then
			sudo apt update && update=1
		fi
		sudo apt install -fy ${app} 
	else
		echo " - already installed : $app"
	fi
done
echo 

controller=0

#To check if your PS3 controller is detected, run:
#ls /dev/input/
playstation_controller=$(ls /dev/input/* 2>/dev/null | grep PLAYSTATION)
xbox_controller=$(ls /dev/input/* 2>/dev/null | grep -i xbox)
if [[ -n "${playstation_controller}" ]]; then
	echo -e " - PLAYSTATION CONTROLLER DETECTED"
	controller=$((controller+1))
fi
if [[ -n "${xbox_controller}" ]]; then
	echo -e " - XBOX CONTROLLER DETECTED"
	controller=$((controller+1))
fi
if [[ "$controller" -eq 0 ]] ; then
	echo -e " - NO GAME CONTROLLERS DETECTED"
	exit 
fi

#Or list all connected input devices:
echo " - Starting python -m evdev.evtest"
sleep 5
python -m evdev.evtest
#Let me know if you need help setting it up!
