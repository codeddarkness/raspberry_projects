#!/usr/bin/env python3

import evdev
import signal
import sys
import Adafruit_PCA9685

# Path to the Xbox controller device
DEVICE_PATH = "/dev/input/event3"

# Initialize PCA9685
pwm = Adafruit_PCA9685.PCA9685(busnum=1)  # Explicitly setting I2C bus
pwm.set_pwm_freq(50)  # Set frequency to 50Hz for servos

# Servo configuration
SERVO_MIN = 150  # Minimum pulse length
SERVO_MAX = 600  # Maximum pulse length
SERVO_CHANNELS = [0, 1, 2, 3]  # Four servo channels

# Custom center positions for servos
CENTER_POSITIONS = {0: 47, 1: 75, 2: 49, 3: 90}

# Hold toggle states for servos
hold_state = {0: False, 1: False, 2: False, 3: False}

# Store current servo positions (default to new centers)
servo_positions = CENTER_POSITIONS.copy()

# Convert joystick value (-32767 to 32767) to PWM pulse and angle
def joystick_to_pwm(value, center):
    angle = int(((value + 32767) / 65534) * 180)  # Normalize -32767 to 32767 → 0 to 180 degrees
    pwm_value = int(SERVO_MIN + (angle / 180.0) * (SERVO_MAX - SERVO_MIN))
    return pwm_value, angle

# Move servos based on joystick input, unless hold is active
def move_servo(channel, value):
    if not hold_state[channel]:  # Only move if hold is not active
        pwm_value, angle = joystick_to_pwm(value, CENTER_POSITIONS[channel])
        pwm.set_pwm(channel, 0, pwm_value)
        servo_positions[channel] = angle  # Store angle for display
        display_status()

# Handle program exit on Ctrl+C
def exit_handler(signal_received=None, frame=None):
    print("\nExiting program.")
    pwm.set_all_pwm(0, 0)  # Turn off all servos
    sys.exit(0)

signal.signal(signal.SIGINT, exit_handler)

# Display status of joysticks, angles, and hold buttons
def display_status():
    arrows = {
        "left": "←", "right": "→",
        "up": "↑", "down": "↓",
        "neutral": "·"
    }

    lx = arrows["left"] if servo_positions[0] < CENTER_POSITIONS[0] else arrows["right"] if servo_positions[0] > CENTER_POSITIONS[0] else arrows["neutral"]
    ly = arrows["up"] if servo_positions[1] < CENTER_POSITIONS[1] else arrows["down"] if servo_positions[1] > CENTER_POSITIONS[1] else arrows["neutral"]
    ry = arrows["up"] if servo_positions[2] < CENTER_POSITIONS[2] else arrows["down"] if servo_positions[2] > CENTER_POSITIONS[2] else arrows["neutral"]
    rx = arrows["left"] if servo_positions[3] < CENTER_POSITIONS[3] else arrows["right"] if servo_positions[3] > CENTER_POSITIONS[3] else arrows["neutral"]

    hold_status = {ch: "ON" if hold_state[ch] else "OFF" for ch in hold_state}

    print(f"\rLX: {lx} [{servo_positions[0]:3}°]  LY: {ly} [{servo_positions[1]:3}°]  "
          f"RY: {ry} [{servo_positions[2]:3}°]  RX: {rx} [{servo_positions[3]:3}°]  \n"
          f" B: {hold_status[0]}       A: {hold_status[1]}       X: {hold_status[2]}       Y: {hold_status[3]}  ", end="")

# Read Xbox controller input
def read_xbox_controller():
    try:
        gamepad = evdev.InputDevice(DEVICE_PATH)
        print(f"Listening for input from {gamepad.name} ({DEVICE_PATH})")
        print("Use the left and right sticks to control servos. Press 'Ctrl+C' to exit.")

        for event in gamepad.read_loop():
            if event.type == evdev.ecodes.EV_ABS:
                if event.code == evdev.ecodes.ABS_X:  # Left Stick X → Servo 0
                    move_servo(0, event.value)
                elif event.code == evdev.ecodes.ABS_Y:  # Left Stick Y → Servo 1
                    move_servo(1, event.value)
                elif event.code == evdev.ecodes.ABS_RY:  # Right Stick Y → Servo 2
                    move_servo(2, event.value)
                elif event.code == evdev.ecodes.ABS_RX:  # Right Stick X → Servo 3
                    move_servo(3, event.value)

            elif event.type == evdev.ecodes.EV_KEY:
                if event.code == evdev.ecodes.BTN_SOUTH and event.value == 1:  # A button → Hold Servo 1
                    hold_state[1] = not hold_state[1]
                    display_status()
                elif event.code == evdev.ecodes.BTN_EAST and event.value == 1:  # B button → Hold Servo 0
                    hold_state[0] = not hold_state[0]
                    display_status()
                elif event.code == evdev.ecodes.BTN_NORTH and event.value == 1:  # Y button → Hold Servo 3
                    hold_state[3] = not hold_state[3]
                    display_status()
                elif event.code == evdev.ecodes.BTN_WEST and event.value == 1:  # X button → Hold Servo 2
                    hold_state[2] = not hold_state[2]
                    display_status()

    except FileNotFoundError:
        print(f"Error: Could not find controller at {DEVICE_PATH}. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running the script with 'sudo'.")

if __name__ == "__main__":
    read_xbox_controller()

