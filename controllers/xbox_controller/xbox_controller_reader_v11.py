#!/usr/bin/env python3

import evdev
import signal
import sys
import time
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

# Hold toggle states for servos
hold_state = {0: False, 1: False, 2: False, 3: False}
lock_state = False  # Lock state for all servos

# Store current servo positions (default resting positions)
servo_positions = {0: 53, 1: 74, 2: 41, 3: 91}

# Servo speed (default to 1.0)
servo_speed = 1.0

# Convert joystick value (-32767 to 32767) to PWM pulse (150 to 600) and angle (0° to 180°)
def joystick_to_pwm(value):
    angle = int(((value + 32767) / 65534) * 180)  # Normalize -32767 to 32767 → 0 to 180 degrees
    pwm_value = int(SERVO_MIN + (angle / 180.0) * (SERVO_MAX - SERVO_MIN))
    return pwm_value, angle

# Smooth the joystick movement to reduce jitter
#def smooth_input(value, prev_value, smoothing_factor=0.1):
#    return int(prev_value + (value - prev_value) * smoothing_factor)

# Move servos based on joystick input, unless hold is active
def move_servo(channel, value):
    if lock_state:
        return  # Do nothing if servos are locked

    # Smooth input to reduce jitter
    global servo_positions
#    value = smooth_input(value, servo_positions[channel])
    
    pwm_value, angle = joystick_to_pwm(value)
    pwm.set_pwm(channel, 0, pwm_value)
    servo_positions[channel] = angle  # Store angle for display
    display_status()

# Move all servos to a specified angle
def move_all_servos(angle):
    if lock_state:
        return  # Do nothing if servos are locked

    pwm_value = int(SERVO_MIN + (angle / 180.0) * (SERVO_MAX - SERVO_MIN))
    for channel in range(4):
        pwm.set_pwm(channel, 0, pwm_value)
        servo_positions[channel] = angle
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

    lx = arrows["left"] if servo_positions[0] < 90 else arrows["right"] if servo_positions[0] > 90 else arrows["neutral"]
    ly = arrows["up"] if servo_positions[1] < 90 else arrows["down"] if servo_positions[1] > 90 else arrows["neutral"]
    ry = arrows["up"] if servo_positions[2] < 90 else arrows["down"] if servo_positions[2] > 90 else arrows["neutral"]
    rx = arrows["left"] if servo_positions[3] < 90 else arrows["right"] if servo_positions[3] > 90 else arrows["neutral"]

    hold_status = {ch: "ON" if hold_state[ch] else "OFF" for ch in hold_state}

    print(f"\rLX: {lx} [{servo_positions[0]:3}°]  "
          f"LY: {ly} [{servo_positions[1]:3}°]  "
          f"RY: {ry} [{servo_positions[2]:3}°]  "
          f"RX: {rx} [{servo_positions[3]:3}°]  |  "
          f"Hold - B: {hold_status[0]} A: {hold_status[1]} Y: {hold_status[2]} X: {hold_status[3]} "
          f"Speed: {servo_speed:.2f}", end="")

# Read Xbox controller input
def read_xbox_controller():
    global servo_speed, lock_state
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
                elif event.code == evdev.ecodes.BTN_NORTH and event.value == 1:  # Y button → Hold Servo 2
                    hold_state[2] = not hold_state[2]
                    display_status()
                elif event.code == evdev.ecodes.BTN_WEST and event.value == 1:  # X button → Hold Servo 3
                    hold_state[3] = not hold_state[3]
                    display_status()

                elif event.code == evdev.ecodes.BTN_SELECT and event.value == 1:  # Select button → Calibration
                    print("\nCalibrating servos...")
                    move_all_servos(0)  # Move all to 0°
                    time.sleep(1)
                    move_all_servos(180)  # Move all to 180°
                    time.sleep(1)
                    move_all_servos(90)  # Move all to 90° (center)
                    display_status()

                elif event.code == evdev.ecodes.BTN_TR and event.value == 1:  # Right shoulder button → Increase speed
                    servo_speed = min(servo_speed + 0.1, 2.0)
                    print(f"\nSpeed increased to {servo_speed:.2f}")
                    display_status()

                elif event.code == evdev.ecodes.BTN_TL and event.value == 1:  # Left shoulder button → Decrease speed
                    servo_speed = max(servo_speed - 0.1, 0.1)
                    print(f"\nSpeed decreased to {servo_speed:.2f}")
                    display_status()

                elif event.code == evdev.ecodes.KEY_RIGHT and event.value == 1:  # Right D-pad → Move all to 180°
                    move_all_servos(180)

                elif event.code == evdev.ecodes.KEY_LEFT and event.value == 1:  # Left D-pad → Move all to 0°
                    move_all_servos(0)

                elif event.code == evdev.ecodes.KEY_UP and event.value == 1:  # Up D-pad → Move all to 90° (center)
                    move_all_servos(90)

                elif event.code == evdev.ecodes.KEY_DOWN and event.value == 1:  # Down D-pad → Toggle lock state
                    lock_state = not lock_state
                    status = "locked" if lock_state else "unlocked"
                    print(f"\nServos are now {status}.")
                    display_status()

    except FileNotFoundError:
        print(f"Error: Could not find controller at {DEVICE_PATH}. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running the script with 'sudo'.")

if __name__ == "__main__":
    read_xbox_controller()

