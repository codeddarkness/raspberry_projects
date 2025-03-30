#/usr/bin/env python3
import csv
import signal
import sys
from time import sleep
import Adafruit_PCA9685
import evdev
from evdev import InputDevice, ecodes

# Initialize PCA9685
pwm = Adafruit_PCA9685.PCA9685()
pwm.set_pwm_freq(50)  # Set frequency to 50Hz for servos

# Servo configuration
SERVO_MIN = 150  # Min pulse length
SERVO_MAX = 600  # Max pulse length
SERVO_CHANNELS = [0, 1, 2, 3]  # The four servo channels

# Convert joystick value to PWM pulse
def joystick_to_pwm(value):
    angle = int(((value + 32767) / 65534) * 180)  # Normalize -32767 to 32767 -> 0 to 180 degrees
    return int(SERVO_MIN + (angle / 180.0) * (SERVO_MAX - SERVO_MIN))

# Move servos synchronously
def move_servos(angle1, angle2, angle3, angle4):
    angles = [angle1, angle2, angle3, angle4]
    for i, angle in enumerate(angles):
        pwm.set_pwm(SERVO_CHANNELS[i], 0, joystick_to_pwm(angle))
    print(f"Moved servos to angles: {angles}")

# Read angles from CSV file
def read_angles_from_csv(file_path):
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

# Handle exit signals
def exit_handler(signal_received=None, frame=None):
    print("\nExiting program.")
    pwm.set_all_pwm(0, 0)  # Turn off all servos
    sys.exit(0)

signal.signal(signal.SIGINT, exit_handler)  # Handle Ctrl+C

# Detect and use PlayStation 3 controller
def get_ps3_controller():
    devices = [InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if 'PLAYSTATION' in device.name:
            return device
    return None

def control_with_ps3():
    controller = get_ps3_controller()
    if not controller:
        print("No PlayStation 3 controller found.")
        return
    
    print("Using PlayStation 3 controller. Move the joysticks to control servos.")
    for event in controller.read_loop():
        if event.type == ecodes.EV_ABS:
            if event.code == ecodes.ABS_X:
                move_servos(event.value, 0, 0, 0)
            elif event.code == ecodes.ABS_Y:
                move_servos(0, event.value, 0, 0)
            elif event.code == ecodes.ABS_RX:
                move_servos(0, 0, event.value, 0)
            elif event.code == ecodes.ABS_RY:
                move_servos(0, 0, 0, event.value)

# Main execution loop
if __name__ == "__main__":
    choice = input("Choose input method: (1) CSV File, (2) PlayStation Controller: ")
    
    if choice == '1':
        csv_file = "servo_angles.csv"
        angles_list = read_angles_from_csv(csv_file)
        for angles in angles_list:
            move_servos(*angles)
            sleep(1)  # Small delay between movements
    elif choice == '2':
        control_with_ps3()
    else:
        print("Invalid choice. Exiting.")

