#!/usr/bin/env python3

import csv
import evdev
import signal
import sys
import time
import argparse
from evdev import InputDevice, ecodes

# Try to import Adafruit_PCA9685, but allow the script to run in debug mode without it
try:
    import Adafruit_PCA9685
    PWM_AVAILABLE = True
except ImportError:
    print("Warning: Adafruit_PCA9685 not found. Running in debug mode (no servo control).")
    PWM_AVAILABLE = False

# Configuration
SERVO_MIN = 150  # Minimum pulse length
SERVO_MAX = 600  # Maximum pulse length
SERVO_RANGE = 180  # Servo range in degrees
SERVO_CHANNELS = [0, 1, 2, 3]  # Four servo channels

# Initialize global variables
hold_state = {0: False, 1: False, 2: False, 3: False}
lock_state = False
servo_positions = {0: 90, 1: 90, 2: 90, 3: 90}
servo_speed = 1.0
controller_type = None
pwm = None

def initialize_hardware():
    """Initialize the PCA9685 hardware if available"""
    global pwm
    if PWM_AVAILABLE:
        pwm = Adafruit_PCA9685.PCA9685(busnum=1)  # Explicitly setting I2C bus
        pwm.set_pwm_freq(50)  # Set frequency to 50Hz for servos
        return True
    return False

def exit_handler(signal_received=None, frame=None):
    """Handle program exit gracefully"""
    print("\nExiting program.")
    if PWM_AVAILABLE and pwm:
        pwm.set_all_pwm(0, 0)  # Turn off all servos
    sys.exit(0)

def joystick_to_pwm(value):
    """Convert joystick value (-32767 to 32767) to PWM pulse and angle"""
    angle = int(((value + 32767) / 65534) * SERVO_RANGE)  # Normalize to 0-180 degrees
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    return pwm_value, angle

def move_servo(channel, value):
    """Move a servo to the position based on joystick value"""
    if lock_state or hold_state[channel]:
        return  # Don't move if locked or held
    
    pwm_value, angle = joystick_to_pwm(value)
    if PWM_AVAILABLE and pwm:
        pwm.set_pwm(channel, 0, pwm_value)
    servo_positions[channel] = angle
    display_status()

def move_all_servos(angle):
    """Move all servos to a specified angle"""
    if lock_state:
        return  # Don't move if locked
        
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    for channel in SERVO_CHANNELS:
        if PWM_AVAILABLE and pwm:
            pwm.set_pwm(channel, 0, pwm_value)
        servo_positions[channel] = angle
    display_status()

def display_status():
    """Display status of joysticks, angles, and hold buttons in a compact single line"""
    arrows = {
        "left": "←", "right": "→",
        "up": "↑", "down": "↓",
        "neutral": "·"
    }

    # Determine direction arrows based on servo positions
    lx = arrows["left"] if servo_positions[0] < 90 else arrows["right"] if servo_positions[0] > 90 else arrows["neutral"]
    ly = arrows["up"] if servo_positions[1] < 90 else arrows["down"] if servo_positions[1] > 90 else arrows["neutral"]
    ry = arrows["up"] if servo_positions[2] < 90 else arrows["down"] if servo_positions[2] > 90 else arrows["neutral"]
    rx = arrows["left"] if servo_positions[3] < 90 else arrows["right"] if servo_positions[3] > 90 else arrows["neutral"]

    # Get hold status
    hold_indicators = "".join(["H" if hold_state[ch] else "." for ch in range(4)])
    lock_indicator = "L" if lock_state else "."
    
    # Print compact status line
    print(f"\rLX:{lx}{servo_positions[0]:3}° LY:{ly}{servo_positions[1]:3}° RY:{ry}{servo_positions[2]:3}° RX:{rx}{servo_positions[3]:3}° | Hold:{hold_indicators} Lock:{lock_indicator} Spd:{servo_speed:.1f}x", end="")

def find_controller():
    """Find and return a PlayStation or Xbox controller device"""
    devices = [InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if 'PLAYSTATION' in device.name or 'PlayStation' in device.name:
            return device, 'PS'
        elif 'Xbox' in device.name:
            return device, 'Xbox'
    return None, None

def read_angles_from_csv(file_path):
    """Read servo angles from a CSV file"""
    angles = []
    try:
        with open(file_path, 'r') as file:
            reader = csv.reader(file)
            for row in reader:
                if len(row) == 4:
                    angles.append([int(value) for value in row])
    except Exception as e:
        print(f"Error reading CSV: {e}")
    return angles

def run_csv_mode(csv_file="servo_angles.csv"):
    """Run using angles from a CSV file"""
    print(f"Reading servo angles from {csv_file}")
    angles_list = read_angles_from_csv(csv_file)
    
    if not angles_list:
        print("No valid angles found in CSV file.")
        return
        
    for angles in angles_list:
        print(f"Moving servos to angles: {angles}")
        if PWM_AVAILABLE and pwm:
            for i, angle in enumerate(angles):
                if i < len(SERVO_CHANNELS):
                    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
                    pwm.set_pwm(SERVO_CHANNELS[i], 0, pwm_value)
        time.sleep(1)  # Small delay between movements

def run_controller_mode(device_path=None):
    """Run using a PlayStation or Xbox controller"""
    global controller_type, lock_state, servo_speed
    
    try:
        # Try to use specified device path if provided
        if device_path:
            gamepad = evdev.InputDevice(device_path)
            # Detect controller type from name
            if 'PLAYSTATION' in gamepad.name or 'PlayStation' in gamepad.name:
                controller_type = 'PS'
            elif 'Xbox' in gamepad.name:
                controller_type = 'Xbox'
            else:
                controller_type = 'Generic'
        else:
            # Auto-detect controller
            gamepad, controller_type = find_controller()
            if not gamepad:
                print("No PlayStation or Xbox controller found. Available devices:")
                for path in evdev.list_devices():
                    dev = evdev.InputDevice(path)
                    print(f"  {path}: {dev.name}")
                return
        
        print(f"Using {gamepad.name} ({controller_type}) at {gamepad.path}")
        print("Use joysticks to control servos. ABXY buttons toggle hold. Press Ctrl+C to exit.")
        
        # Main event loop
        for event in gamepad.read_loop():
            # Handle joystick movements
            if event.type == ecodes.EV_ABS:
                if event.code == ecodes.ABS_X:  # Left Stick X → Servo 0
                    move_servo(0, event.value)
                elif event.code == ecodes.ABS_Y:  # Left Stick Y → Servo 1
                    move_servo(1, event.value)
                elif event.code == ecodes.ABS_RY:  # Right Stick Y → Servo 2
                    move_servo(2, event.value)
                elif event.code == ecodes.ABS_RX:  # Right Stick X → Servo 3
                    move_servo(3, event.value)
            
            # Handle button presses
            elif event.type == ecodes.EV_KEY and event.value == 1:  # Button down
                # Handle different button codes for PlayStation and Xbox
                if event.code == ecodes.BTN_SOUTH:  # A/Cross button → Hold Servo 1
                    hold_state[1] = not hold_state[1]
                    display_status()
                elif event.code == ecodes.BTN_EAST:  # B/Circle button → Hold Servo 0
                    hold_state[0] = not hold_state[0]
                    display_status()
                elif event.code == ecodes.BTN_NORTH:  # Y/Triangle button → Hold Servo 2
                    hold_state[2] = not hold_state[2]
                    display_status()
                elif event.code == ecodes.BTN_WEST:  # X/Square button → Hold Servo 3
                    hold_state[3] = not hold_state[3]
                    display_status()
                elif event.code == ecodes.BTN_SELECT:  # Select/Share button → Calibration
                    print("\nCalibrating servos...")
                    move_all_servos(0)  # Move all to 0°
                    time.sleep(1)
                    move_all_servos(180)  # Move all to 180°
                    time.sleep(1)
                    move_all_servos(90)  # Move all to 90° (center)
                    display_status()
                elif event.code == ecodes.BTN_TR:  # Right trigger → Increase speed
                    servo_speed = min(servo_speed + 0.1, 2.0)
                    print(f"\nSpeed increased to {servo_speed:.1f}x")
                    display_status()
                elif event.code == ecodes.BTN_TL:  # Left trigger → Decrease speed
                    servo_speed = max(servo_speed - 0.1, 0.1)
                    print(f"\nSpeed decreased to {servo_speed:.1f}x")
                    display_status()
                elif event.code in (ecodes.BTN_DPAD_RIGHT, ecodes.KEY_RIGHT):  # Right D-pad → 180°
                    move_all_servos(180)
                elif event.code in (ecodes.BTN_DPAD_LEFT, ecodes.KEY_LEFT):  # Left D-pad → 0°
                    move_all_servos(0)
                elif event.code in (ecodes.BTN_DPAD_UP, ecodes.KEY_UP):  # Up D-pad → 90°
                    move_all_servos(90)
                elif event.code in (ecodes.BTN_DPAD_DOWN, ecodes.KEY_DOWN):  # Down D-pad → Toggle lock
                    lock_state = not lock_state
                    status = "locked" if lock_state else "unlocked"
                    print(f"\nServos are now {status}.")
                    display_status()
    
    except FileNotFoundError:
        print(f"Error: Could not find controller. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running with sudo.")
    except Exception as e:
        print(f"Error: {e}")

def main():
    parser = argparse.ArgumentParser(description='Unified Controller for PlayStation and Xbox controllers')
    parser.add_argument('--device', help='Path to input device (e.g., /dev/input/event3)')
    parser.add_argument('--csv', help='Path to CSV file with servo angles')
    parser.add_argument('--debug', action='store_true', help='Run in debug mode without servo control')
    args = parser.parse_args()

    # Register signal handler for Ctrl+C
    signal.signal(signal.SIGINT, exit_handler)
    
    # Initialize hardware unless in debug mode
    if not args.debug and not initialize_hardware():
        print("Hardware initialization failed. Running in debug mode.")
    
    # Main mode selection
    if args.csv:
        run_csv_mode(args.csv)
    else:
        run_controller_mode(args.device)

if __name__ == "__main__":
    main()
