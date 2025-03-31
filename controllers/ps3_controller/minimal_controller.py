#!/usr/bin/env python3
"""
Simple servo controller for PS3 gamepad with corrected button mappings
"""
import os
import sys
import time
import evdev
from evdev import InputDevice, ecodes

# Global variables
exit_flag = False
controller_type = "PS3"

# PS3 button mappings - corrected based on testing
PS3_BUTTON_MAPPINGS = {
    294: "D-Pad Down",      # Down
    293: "D-Pad Right",     # Unknown (293)
    292: "D-Pad Up",        # PS Button
    295: "D-Pad Left",      # Left Shoulder
    298: "Left Shoulder",   # D-Pad Right
    296: "Left Trigger",    # Left Trigger
    299: "Right Shoulder",  # D-Pad Left
    297: "Right Trigger",   # Right Shoulder
    288: "Select",          # Select
    291: "Start",           # Start
    304: "PS Button",       # Right Trigger
    303: "Square (West)",   # D-Pad Left
    300: "Triangle (North)", # D-Pad Up
    301: "Circle (East)",   # D-Pad Right
    302: "X Button (South)", # X Button (South)
    289: "Left Joystick Button", # Right Joystick Button
    290: "Right Joystick Button" # Left Joystick Button
}

def handle_controller_input(gamepad):
    """Process input from game controller"""
    global exit_flag
    
    print(f"Controller input handler started for: {gamepad.name}")
    
    try:
        for event in gamepad.read_loop():
            if exit_flag:
                break
                
            try:
                # Handle joystick movements
                if event.type == ecodes.EV_ABS:
                    # Left stick
                    if event.code == 0:  # Left Stick X
                        print(f"Left Stick X: {event.value}")
                    elif event.code == 1:  # Left Stick Y
                        print(f"Left Stick Y: {event.value}")
                    # Right stick
                    elif event.code == 2:  # Right Stick X
                        print(f"Right Stick X: {event.value}")
                    elif event.code == 3:  # Right Stick Y
                        print(f"Right Stick Y: {event.value}")
                
                # Handle button presses with error handling for each button
                elif event.type == ecodes.EV_KEY and event.value == 1:  # Button pressed
                    try:
                        btn_name = PS3_BUTTON_MAPPINGS.get(event.code, f"Unknown ({event.code})")
                        print(f"Button pressed: {btn_name}")
                        
                        # Modify the exit condition to check for the PS button (304)
                        if event.code == 304:  # PS Button (was 292)
                            print("PS button pressed. Exiting...")
                            exit_flag = True
                    except Exception as button_error:
                        print(f"Error processing button {event.code}: {button_error}")
                
            except Exception as e:
                print(f"Error processing controller event: {e}")
    
    except KeyboardInterrupt:
        print("\nController input interrupted.")
        exit_flag = True
    except Exception as e:
        print(f"\nController error: {e}")
        exit_flag = True

def main():
    """Main function"""
    print("Starting simplified servo controller...")
    
    # Force controller path
    controller_path = "/dev/input/event3"
    print(f"Using controller at: {controller_path}")
    
    try:
        gamepad = InputDevice(controller_path)
        print(f"Controller detected: {gamepad.name}")
        
        # Start controller input handling
        handle_controller_input(gamepad)
    except Exception as e:
        print(f"Error: {e}")
    
    print("Program exiting.")

if __name__ == "__main__":
    main()

