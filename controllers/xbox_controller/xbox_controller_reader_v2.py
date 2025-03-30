#!/usr/bin/env python3

import evdev
import signal
import sys

# Path to the Xbox controller device
DEVICE_PATH = "/dev/input/event3"

def exit_handler(signal_received=None, frame=None):
    """Handle program exit on Ctrl+C"""
    print("\nExiting program.")
    sys.exit(0)

# Register signal handler for Ctrl+C
signal.signal(signal.SIGINT, exit_handler)

def read_xbox_controller():
    try:
        gamepad = evdev.InputDevice(DEVICE_PATH)
        print(f"Listening for input from {gamepad.name} ({DEVICE_PATH})")
        print("Press any button on the Xbox controller. Press 'q' on the keyboard to exit.")

        for event in gamepad.read_loop():
            if event.type == evdev.ecodes.EV_KEY:
                key_name = evdev.ecodes.KEY[event.code] if event.code in evdev.ecodes.KEY else f"Button {event.code}"
                if event.value == 1:  # Button pressed
                    print(f"Button pressed: {key_name}")

            if event.type == evdev.ecodes.EV_ABS:
                axis_name = evdev.ecodes.ABS[event.code] if event.code in evdev.ecodes.ABS else f"Axis {event.code}"
                print(f"Joystick moved: {axis_name}, Value: {event.value}")

            # Instead of checking for KEY_Q, check keyboard input separately
            if event.type == evdev.ecodes.EV_KEY and event.code == evdev.ecodes.KEY_Q:
                print("Ignoring Q input from controller.")

    except FileNotFoundError:
        print(f"Error: Could not find controller at {DEVICE_PATH}. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running the script with 'sudo'.")

if __name__ == "__main__":
    read_xbox_controller()

