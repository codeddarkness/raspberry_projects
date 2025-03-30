#!/usr/bin/env python3

import csv
import evdev
import signal
import sys
import time
import argparse
import os
import subprocess
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
connection_type = "Unknown"
pwm = None
sixaxis_values = {"tilt_x": 0, "tilt_y": 0, "tilt_z": 0, "accel_x": 0, "accel_y": 0, "accel_z": 0}
last_activity = time.time()

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

def accelerometer_to_pwm(value, center=0, range=512):
    """Convert accelerometer value to PWM pulse and angle"""
    # Normalize accelerometer values to 0-180 degrees
    normalized = max(0, min(SERVO_RANGE, ((value - center + range/2) / range) * SERVO_RANGE))
    angle = int(normalized)
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    return pwm_value, angle

def move_servo(channel, value):
    """Move a servo to the position based on joystick value"""
    global last_activity
    if lock_state or hold_state[channel]:
        return  # Don't move if locked or held
    
    pwm_value, angle = joystick_to_pwm(value)
    if PWM_AVAILABLE and pwm:
        pwm.set_pwm(channel, 0, pwm_value)
    servo_positions[channel] = angle
    last_activity = time.time()
    display_status()

def move_servo_accel(channel, value, center=0, range=512):
    """Move a servo based on accelerometer/gyro value"""
    global last_activity
    if lock_state or hold_state[channel]:
        return  # Don't move if locked or held
    
    pwm_value, angle = accelerometer_to_pwm(value, center, range)
    if PWM_AVAILABLE and pwm:
        pwm.set_pwm(channel, 0, pwm_value)
    servo_positions[channel] = angle
    last_activity = time.time()
    display_status()

def move_all_servos(angle):
    """Move all servos to a specified angle"""
    global last_activity
    if lock_state:
        return  # Don't move if locked
        
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    for channel in SERVO_CHANNELS:
        if PWM_AVAILABLE and pwm:
            pwm.set_pwm(channel, 0, pwm_value)
        servo_positions[channel] = angle
    last_activity = time.time()
    display_status()

def detect_connection_type(device_path):
    """Determine if the controller is connected via USB, Bluetooth or SixAxis"""
    if 'event' in device_path:
        # Check if it's a USB connection
        if os.path.exists("/sys/class/input/" + device_path.split('/')[-1] + "/device/driver/module"):
            module = os.readlink("/sys/class/input/" + device_path.split('/')[-1] + "/device/driver/module")
            if "hid" in module:
                return "USB"
        
        # Check if it's a Bluetooth connection
        try:
            bluetooth_devices = subprocess.check_output(["hcitool", "con"], universal_newlines=True)
            if bluetooth_devices and len(bluetooth_devices.strip().split('\n')) > 1:
                return "Bluetooth"
        except:
            pass
        
        # Check if sixad is running
        try:
            ps_output = subprocess.check_output(["ps", "-ef"], universal_newlines=True)
            if "sixad" in ps_output:
                return "SixAxis"
        except:
            pass
    
    return "Unknown"

def display_status():
    """Display status of joysticks, angles, and hold buttons matching original format"""
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

    # Get hold status for each button (matching original format)
    hold_status = {ch: "ON" if hold_state[ch] else "OFF" for ch in hold_state}
    lock_indicator = "LOCKED" if lock_state else "UNLOCKED"
    
    # Print status line
    status_line = f"\rLX:{lx} {servo_positions[0]:3}° LY:{ly} {servo_positions[1]:3}° RY:{ry} {servo_positions[2]:3}° RX:{rx} {servo_positions[3]:3}° | "
    
    # Add controller-specific status
    if controller_type == "PS3":
        status_line += f"Hold - ✕:{hold_status[0]} ○:{hold_status[1]} □:{hold_status[2]} △:{hold_status[3]} "
        # Add SixAxis info if available
        status_line += f"| Tilt:{sixaxis_values['tilt_x']:4},{sixaxis_values['tilt_y']:4},{sixaxis_values['tilt_z']:4} "
    else:  # Xbox or Generic
        status_line += f"Hold - A:{hold_status[0]} B:{hold_status[1]} X:{hold_status[2]} Y:{hold_status[3]} "
    
    # Add lock status, speed and connection type
    status_line += f"| {lock_indicator} Spd:{servo_speed:.1f}x [{connection_type}]"
    
    print(status_line, end="")

def find_controller(device_path=None):
    """Find and return a PlayStation or Xbox controller device"""
    if device_path:
        try:
            device = InputDevice(device_path)
            # Detect controller type from name
            if 'PLAYSTATION' in device.name or 'PlayStation' in device.name:
                return device, 'PS3' if '3' in device.name else 'PS'
            elif 'Xbox' in device.name:
                return device, 'Xbox'
            else:
                return device, 'Generic'
        except (FileNotFoundError, PermissionError):
            print(f"Could not access device at {device_path}")
            return None, None
    
    # No specific path, try to auto-detect
    devices = [InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if 'PLAYSTATION(R)3' in device.name or 'PlayStation 3' in device.name:
            return device, 'PS3'
        elif 'PLAYSTATION' in device.name or 'PlayStation' in device.name:
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
    global controller_type, lock_state, servo_speed, connection_type, sixaxis_values
    
    try:
        # Try to use specified device path or auto-detect controller
        gamepad, controller_type = find_controller(device_path)
        if not gamepad:
            print("No PlayStation or Xbox controller found. Available devices:")
            for path in evdev.list_devices():
                try:
                    dev = evdev.InputDevice(path)
                    print(f"  {path}: {dev.name}")
                except:
                    pass
            return
        
        # Determine connection type
        connection_type = detect_connection_type(gamepad.path)
        
        print(f"Using {gamepad.name} ({controller_type}) at {gamepad.path}")
        print(f"Connection type: {connection_type}")
        print("Use joysticks to control servos. Press buttons to toggle hold. Press Ctrl+C to exit.")
        
        # Get capabilities to check for SixAxis support
        caps = gamepad.capabilities()
        has_sixaxis = ecodes.EV_ABS in caps and (
            ecodes.ABS_RZ in caps[ecodes.EV_ABS] or 
            ecodes.ABS_Z in caps[ecodes.EV_ABS] or
            ecodes.ABS_TILT_X in caps.get(ecodes.EV_ABS, []) or
            ecodes.ABS_TILT_Y in caps.get(ecodes.EV_ABS, [])
        )
        
        if controller_type == 'PS3' and has_sixaxis:
            print("SixAxis motion detection enabled!")
        
        # Show capabilities for debugging
        print("Controller capabilities:", end=" ")
        if ecodes.EV_ABS in caps:
            abs_caps = caps[ecodes.EV_ABS]
            print(f"Analog axes: {len(abs_caps)}", end=" ")
            
        if ecodes.EV_KEY in caps:
            key_caps = caps[ecodes.EV_KEY]
            print(f"Buttons: {len(key_caps)}", end=" ")
        
        print("") # End the line
        
        # Main event loop
        for event in gamepad.read_loop():
            # Map PS3 buttons to standard buttons if needed
            if controller_type == 'PS3' and event.type == ecodes.EV_KEY:
                if event.code in ps3_button_map:
                    event.code = ps3_button_map[event.code]
            
            # Handle PS3 D-pad (which uses ABS events instead of KEY)
            if controller_type == 'PS3' and event.type == ecodes.EV_ABS and event.code == 16:  # Hat0X
                if event.value == -1:  # D-pad left
                    move_all_servos(0)
                elif event.value == 1:  # D-pad right
                    move_all_servos(180)
            
            if controller_type == 'PS3' and event.type == ecodes.EV_ABS and event.code == 17:  # Hat0Y
                if event.value == -1:  # D-pad up
                    move_all_servos(90)
                elif event.value == 1:  # D-pad down
                    lock_state = not lock_state
                    status = "locked" if lock_state else "unlocked"
                    print(f"\nServos are now {status}.")
                    display_status()
            
            # Handle joystick movements
            if event.type == ecodes.EV_ABS:
                if event.code == ecodes.ABS_X:  # Left Stick X → Servo 0
                    move_servo(0, event.value)
                elif event.code == ecodes.ABS_Y:  # Left Stick Y → Servo 1
                    move_servo(1, event.value)
                
                # Handle different controller mappings for right stick
                if controller_type == 'PS3':
                    if event.code == 3:  # Right Stick X → Servo 2
                        move_servo(2, event.value)
                    elif event.code == 4:  # Right Stick Y → Servo 3
                        move_servo(3, event.value)
                else:  # Xbox
                    if event.code == ecodes.ABS_RY:  # Right Stick Y → Servo 2
                        move_servo(2, event.value)
                    elif event.code == ecodes.ABS_RX:  # Right Stick X → Servo 3
                        move_servo(3, event.value)
                
                # Handle SixAxis motions for PS3 controllers
                if controller_type == 'PS3':
                    # Map sensor inputs to the sixaxis_values dictionary based on observed event codes
                    if event.code == 18:  # Accelerometer X
                        sixaxis_values['accel_x'] = event.value
                        if time.time() - last_activity > 1:  # Only use motion if no joystick activity
                            move_servo_accel(0, event.value, 128, 128)
                    elif event.code == 19:  # Accelerometer Y
                        sixaxis_values['accel_y'] = event.value
                        if time.time() - last_activity > 1:
                            move_servo_accel(1, event.value, 128, 128)
                    elif event.code == 20:  # Accelerometer Z
                        sixaxis_values['accel_z'] = event.value
                    elif event.code == 23:  # Gyro/Tilt X
                        sixaxis_values['tilt_x'] = event.value
                        if time.time() - last_activity > 1:
                            move_servo_accel(2, event.value, 128, 128)
                    elif event.code == 24:  # Gyro/Tilt Y
                        sixaxis_values['tilt_y'] = event.value
                        if time.time() - last_activity > 1:
                            move_servo_accel(3, event.value, 128, 128)
                    elif event.code == 25:  # Gyro/Tilt Z
                        sixaxis_values['tilt_z'] = event.value
                    
                    if has_sixaxis:
                        display_status()  # Update display to show motion sensor values
            
            # Handle button presses for Xbox controllers (PS3 controllers are handled in a PS3-specific section above)
            elif event.type == ecodes.EV_KEY and event.value == 1 and controller_type != 'PS3':  # Button down
                if event.code == ecodes.BTN_SOUTH:  # A button → Hold Servo 0
                    hold_state[0] = not hold_state[0]
                    display_status()
                elif event.code == ecodes.BTN_EAST:  # B button → Hold Servo 1
                    hold_state[1] = not hold_state[1]
                    display_status()
                elif event.code == ecodes.BTN_WEST:  # X button → Hold Servo 2
                    hold_state[2] = not hold_state[2]
                    display_status()
                elif event.code == ecodes.BTN_NORTH:  # Y button → Hold Servo 3
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
                
                # Handle D-pad for Xbox and generic controllers
                # (PS3 D-pad is handled above in the EV_ABS section)
                if event.code == ecodes.BTN_DPAD_RIGHT:  # Right D-pad → 180°
                    move_all_servos(180)
                elif event.code == ecodes.BTN_DPAD_LEFT:  # Left D-pad → 0°
                    move_all_servos(0)
                elif event.code == ecodes.BTN_DPAD_UP:  # Up D-pad → 90°
                    move_all_servos(90)
                elif event.code == ecodes.BTN_DPAD_DOWN:  # Down D-pad → Toggle lock
                    lock_state = not lock_state
                    status = "locked" if lock_state else "unlocked"
                    print(f"\nServos are now {status}.")
                    display_status()
    
    except FileNotFoundError:
        print(f"Error: Could not find controller. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running with sudo.")
    except Exception as e:
        import traceback
        print(f"Error: {e}")
        traceback.print_exc()

def main():
    parser = argparse.ArgumentParser(description='Unified Controller for PlayStation and Xbox controllers')
    parser.add_argument('--device', help='Path to input device (e.g., /dev/input/event3)')
    parser.add_argument('--csv', help='Path to CSV file with servo angles')
    parser.add_argument('--debug', action='store_true', help='Run in debug mode without servo control')
    parser.add_argument('--list', action='store_true', help='List available input devices')
    args = parser.parse_args()

    # Register signal handler for Ctrl+C
    signal.signal(signal.SIGINT, exit_handler)
    
    # List available devices if requested
    if args.list:
        print("Available input devices:")
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
                print(f"  {path}: {dev.name}")
            except:
                pass
        return
    
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

