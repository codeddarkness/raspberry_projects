#!/usr/bin/env python3

import evdev
import signal
import sys
import Adafruit_PCA9685

# Path to the Xbox controller device
DEVICE_PATH = "/dev/input/event3"

# Initialize PCA9685
#pwm = Adafruit_PCA9685.PCA9685()
pwm = Adafruit_PCA9685.PCA9685(busnum=1)

pwm.set_pwm_freq(50)  # Set frequency to 50Hz for servos

# Servo configuration
SERVO_MIN = 150  # Minimum pulse length
SERVO_MAX = 600  # Maximum pulse length
SERVO_CHANNELS = [0, 1, 2, 3]  # Servo channels for joystick axes

# Convert joystick value (-32767 to 32767) to PWM pulse (150 to 600)
def joystick_to_pwm(value):
    angle = int(((value + 32767) / 65534) * 180)  # Normalize range -32767 to 32767 → 0 to 180 degrees
    return int(SERVO_MIN + (angle / 180.0) * (SERVO_MAX - SERVO_MIN))

# Move servos based on joystick input
def move_servo(channel, value):
    pwm.set_pwm(channel, 0, joystick_to_pwm(value))

def exit_handler(signal_received=None, frame=None):
    """Handle program exit on Ctrl+C"""
    print("\nExiting program.")
    pwm.set_all_pwm(0, 0)  # Turn off all servos
    sys.exit(0)

# Register signal handler for Ctrl+C
signal.signal(signal.SIGINT, exit_handler)

def read_xbox_controller():
    try:
        gamepad = evdev.InputDevice(DEVICE_PATH)
        print(f"Listening for input from {gamepad.name} ({DEVICE_PATH})")
        print("Use the left and right sticks to control servos. Press 'Ctrl+C' to exit.")

        for event in gamepad.read_loop():
            if event.type == evdev.ecodes.EV_ABS:
                if event.code == evdev.ecodes.ABS_X:  # Left Stick X
                    move_servo(0, event.value)
                elif event.code == evdev.ecodes.ABS_Y:  # Left Stick Y
                    move_servo(1, event.value)
                elif event.code == evdev.ecodes.ABS_RX:  # Right Stick X
                    move_servo(2, event.value)
                elif event.code == evdev.ecodes.ABS_RY:  # Right Stick Y
                    move_servo(3, event.value)

    except FileNotFoundError:
        print(f"Error: Could not find controller at {DEVICE_PATH}. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running the script with 'sudo'.")

if __name__ == "__main__":
    read_xbox_controller()

