#!/usr/bin/env python3

import evdev
import signal
import sys
import json
import os
import time
import threading
import http.server
import socketserver
import random  # Added import for random module
import select
import fcntl
from datetime import datetime
from functools import partial

# Try to import hardware libraries, but continue if not available
try:
    import Adafruit_PCA9685
    PCA9685_AVAILABLE = True
except ImportError:
    PCA9685_AVAILABLE = False
    print("Warning: Adafruit_PCA9685 library not found. Servo control will be simulated.")

try:
    import smbus
    import math
    SMBUS_AVAILABLE = True
except ImportError:
    SMBUS_AVAILABLE = False
    print("Warning: smbus library not found. I2C communication will be simulated.")

# Global variables
# Path to the Xbox controller device (will be detected)
DEVICE_PATH = None
CONTROLLER_AVAILABLE = False

# Web server settings
HTTP_PORT = 8080
WEB_DIR = os.path.dirname(os.path.abspath(__file__))

# Servo configuration
SERVO_MIN = 150  # Minimum pulse length
SERVO_MAX = 600  # Maximum pulse length
SERVO_RANGE = 180  # Servo range in degrees
SERVO_CHANNELS = [0, 1, 2, 3]  # Four servo channels

# Hold toggle states for servos
hold_state = {0: False, 1: False, 2: False, 3: False}

# Store current servo positions (default resting positions)
servo_positions = {0: 90, 1: 90, 2: 90, 3: 90}

# Servo speed (default to 1.0)
servo_speed = 1.0

# MPU6050 variables
MPU_ADDR = 0x68
MPU_AVAILABLE = False
mpu_data = {
    "accel": {"x": 0, "y": 0, "z": 0},
    "gyro": {"x": 0, "y": 0, "z": 0},
    "temp": 0
}

# PCA9685 variables
PCA_ADDR = 0x40
PCA_AVAILABLE = False
PCA_BUS = 1

# For detecting 'q' key presses
q_press_count = 0
last_q_time = 0

# Log file
LOG_FILE = "servo_controller_log.json"
log_data = []

# Initialize devices
def init_devices():
    global pwm, PCA_AVAILABLE, MPU_AVAILABLE, PCA_BUS, DEVICE_PATH, CONTROLLER_AVAILABLE
    
    # Try to initialize PCA9685 (servo controller)
    if PCA9685_AVAILABLE:
        try:
            # Try bus 1 first as it's the most common
            pwm = Adafruit_PCA9685.PCA9685(busnum=1)
            pwm.set_pwm_freq(50)  # Set frequency to 50Hz for servos
            PCA_AVAILABLE = True
            PCA_BUS = 1
            print(f"PCA9685 found on I2C bus 1")
        except Exception as e:
            print(f"Failed to initialize PCA9685 on bus 1: {e}")
            
            # If bus 1 fails, try buses 0 and 2
            for bus_num in [0, 2]:
                try:
                    pwm = Adafruit_PCA9685.PCA9685(busnum=bus_num)
                    pwm.set_pwm_freq(50)  # Set frequency to 50Hz for servos
                    PCA_AVAILABLE = True
                    PCA_BUS = bus_num
                    print(f"PCA9685 found on I2C bus {bus_num}")
                    break
                except Exception as e:
                    print(f"Failed to initialize PCA9685 on bus {bus_num}: {e}")
    
    if not PCA_AVAILABLE:
        print("No PCA9685 found on any I2C bus. Servo control will be simulated.")
        # Create a dummy PWM object for simulation
        class DummyPWM:
            def set_pwm(self, channel, on, pulse):
                pass
            def set_all_pwm(self, on, off):
                pass
            def set_pwm_freq(self, freq):
                pass
        pwm = DummyPWM()
    
    # Try to initialize MPU6050 (gyro/accelerometer)
    if SMBUS_AVAILABLE:
        for bus_num in range(3):  # Try bus 0, 1, 2
            try:
                bus = smbus.SMBus(bus_num)
                bus.write_byte_data(MPU_ADDR, 0x6B, 0)  # Wake up MPU6050
                MPU_AVAILABLE = True
                print(f"MPU6050 found on I2C bus {bus_num}")
                break
            except Exception as e:
                print(f"Failed to initialize MPU6050 on bus {bus_num}: {e}")
    
    if not MPU_AVAILABLE:
        print("No MPU6050 found on any I2C bus. Gyro/accelerometer data will be simulated.")
    
    # Try to find Xbox controller
    try:
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for device in devices:
            if "xbox" in device.name.lower() or "microsoft" in device.name.lower():
                DEVICE_PATH = device.path
                CONTROLLER_AVAILABLE = True
                print(f"Xbox controller found: {device.name} at {DEVICE_PATH}")
                break
        
        if not CONTROLLER_AVAILABLE:
            print("No Xbox controller found. Web UI can be used for control.")
    except Exception as e:
        print(f"Error detecting controllers: {e}")

# MPU6050 functions
def read_word(bus, addr, reg):
    high = bus.read_byte_data(addr, reg)
    low = bus.read_byte_data(addr, reg + 1)
    value = (high << 8) + low
    return value

def read_word_2c(bus, addr, reg):
    val = read_word(bus, addr, reg)
    if val >= 0x8000:
        return -((65535 - val) + 1)
    else:
        return val

def get_mpu_data():
    global mpu_data
    
    if not MPU_AVAILABLE or not SMBUS_AVAILABLE:
        # Simulate some slight movement when no actual MPU is available
        mpu_data["accel"]["x"] += (random.random() - 0.5) * 0.2
        mpu_data["accel"]["y"] += (random.random() - 0.5) * 0.2
        mpu_data["accel"]["z"] = 9.8 + (random.random() - 0.5) * 0.2
        mpu_data["gyro"]["x"] += (random.random() - 0.5) * 0.1
        mpu_data["gyro"]["y"] += (random.random() - 0.5) * 0.1
        mpu_data["gyro"]["z"] += (random.random() - 0.5) * 0.1
        mpu_data["temp"] = 25 + (random.random() - 0.5)
        return
    
    try:
        bus = smbus.SMBus(PCA_BUS)  # Use the same bus as PCA9685
        
        # Read accelerometer data
        accel_x = read_word_2c(bus, MPU_ADDR, 0x3B) / 16384.0
        accel_y = read_word_2c(bus, MPU_ADDR, 0x3D) / 16384.0
        accel_z = read_word_2c(bus, MPU_ADDR, 0x3F) / 16384.0
        
        # Read gyroscope data
        gyro_x = read_word_2c(bus, MPU_ADDR, 0x43) / 131.0
        gyro_y = read_word_2c(bus, MPU_ADDR, 0x45) / 131.0
        gyro_z = read_word_2c(bus, MPU_ADDR, 0x47) / 131.0
        
        # Read temperature
        temp = read_word_2c(bus, MPU_ADDR, 0x41) / 340.0 + 36.53
        
        mpu_data = {
            "accel": {"x": accel_x, "y": accel_y, "z": accel_z},
            "gyro": {"x": gyro_x, "y": gyro_y, "z": gyro_z},
            "temp": temp
        }
    except Exception as e:
        print(f"Error reading MPU6050 data: {e}")

# Servo control functions
def joystick_to_pwm(value):
    """Convert joystick value (-32767 to 32767) to PWM pulse (150 to 600) and angle (0° to 180°)"""
    angle = int(((value + 32767) / 65534) * SERVO_RANGE)  # Normalize -32767 to 32767 → 0 to 180 degrees
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    return pwm_value, angle

def angle_to_pwm(angle):
    """Convert angle (0-180) to PWM pulse (150 to 600)"""
    angle = max(0, min(180, angle))  # Clamp between 0-180
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    return pwm_value

def move_servo(channel, value, is_joystick=True):
    """Move servo based on input (joystick or direct angle)"""
    if not hold_state[channel]:  # Only move if hold is not active
        if is_joystick:
            if channel == 0 or channel == 3:  # Reverse direction for Left Stick X and Right Stick X
                value = -value
            pwm_value, angle = joystick_to_pwm(value)
        else:
            # Value is a direct angle (0-180)
            angle = value
            pwm_value = angle_to_pwm(angle)
        
        # Apply servo speed to smooth movement
        current_angle = servo_positions[channel]
        angle_diff = angle - current_angle
        if abs(angle_diff) > 0:
            # Apply speed factor - larger values of servo_speed mean faster movement
            step = max(1, min(abs(angle_diff), int(abs(angle_diff) * servo_speed)))
            if angle_diff > 0:
                angle = current_angle + step
            else:
                angle = current_angle - step
            pwm_value = angle_to_pwm(angle)
        
        pwm.set_pwm(channel, 0, pwm_value)
        servo_positions[channel] = angle
        log_event("servo_move", {"channel": channel, "angle": angle})

def move_all_servos(angle):
    """Move all servos to a specified angle"""
    pwm_value = angle_to_pwm(angle)
    for channel in SERVO_CHANNELS:
        if not hold_state[channel]:  # Only move if hold is not active
            pwm.set_pwm(channel, 0, pwm_value)
            servo_positions[channel] = angle
    log_event("all_servos_move", {"angle": angle})

def log_event(event_type, data):
    """Log events to JSON file"""
    global log_data
    event = {
        "timestamp": datetime.now().isoformat(),
        "type": event_type,
        "data": data
    }
    log_data.append(event)
    
    # Periodically write to disk
    if len(log_data) % 10 == 0:
        try:
            with open(LOG_FILE, 'w') as f:
                json.dump(log_data, f, indent=2)
        except Exception as e:
            print(f"Error writing to log file: {e}")

# Handle program exit
def exit_handler(signal_received=None, frame=None):
    print("\nExiting program.")
    if PCA_AVAILABLE:
        pwm.set_all_pwm(0, 0)  # Turn off all servos
    try:
        with open(LOG_FILE, 'w') as f:
            json.dump(log_data, f, indent=2)
    except Exception as e:
        print(f"Error writing final log: {e}")
    sys.exit(0)

signal.signal(signal.SIGINT, exit_handler)

# Display status indicators
def get_direction_arrow(value, neutral=90):
    """Return direction arrow based on value"""
    threshold = 5  # Threshold for considering movement
    if abs(value - neutral) < threshold:
        return "○"  # Stationary
    elif value < neutral:
        return "←" if value < neutral - threshold else "○"
    else:
        return "→" if value > neutral + threshold else "○"

def get_ud_direction_arrow(value, neutral=90):
    """Return up/down direction arrow based on value"""
    threshold = 5  # Threshold for considering movement
    if abs(value - neutral) < threshold:
        return "○"  # Stationary
    elif value < neutral:
        return "↑" if value < neutral - threshold else "○"
    else:
        return "↓" if value > neutral + threshold else "○"

def get_mpu_arrow(value, threshold=0.1):
    """Return direction arrow for MPU data"""
    if abs(value) < threshold:
        return "○"  # Stationary
    elif value < 0:
        return "←" if value < -threshold else "○"
    else:
        return "→" if value > threshold else "○"

def get_mpu_ud_arrow(value, threshold=0.1):
    """Return up/down direction arrow for MPU data"""
    if abs(value) < threshold:
        return "○"  # Stationary
    elif value < 0:
        return "↑" if value < -threshold else "○"
    else:
        return "↓" if value > threshold else "○"

def display_status():
    """Display status in console"""
    # Clear screen (platform independent)
    os.system('cls' if os.name == 'nt' else 'clear')
    
    # Device status
    pca_status = "CONNECTED" if PCA_AVAILABLE else "DISCONNECTED"
    mpu_status = "CONNECTED" if MPU_AVAILABLE else "DISCONNECTED"
    controller_status = "CONNECTED" if CONTROLLER_AVAILABLE else "DISCONNECTED"
    
    print(f"Device Status:")
    print(f"PCA9685: {pca_status} (I2C Bus: {PCA_BUS})")
    print(f"MPU6050: {mpu_status}")
    print(f"Xbox Controller: {controller_status}")
    print("-" * 80)
    
    # Servo status
    print("Servo Status:")
    for channel in SERVO_CHANNELS:
        arrow = get_direction_arrow(servo_positions[channel]) if channel in [0, 3] else get_ud_direction_arrow(servo_positions[channel])
        hold = "LOCKED" if hold_state[channel] else "FREE"
        ch_name = "LX" if channel == 0 else "LY" if channel == 1 else "RY" if channel == 2 else "RX"
        print(f"Channel {channel} ({ch_name}): {arrow} [{servo_positions[channel]:3}°] - {hold}")
    print(f"Servo Speed: {servo_speed:.2f}")
    print("-" * 80)
    
    # MPU6050 data
    print("MPU6050 Data:")
    ax_arrow = get_mpu_arrow(mpu_data["accel"]["x"])
    ay_arrow = get_mpu_ud_arrow(mpu_data["accel"]["y"])
    az_arrow = get_mpu_ud_arrow(mpu_data["accel"]["z"])
    gx_arrow = get_mpu_arrow(mpu_data["gyro"]["x"])
    gy_arrow = get_mpu_ud_arrow(mpu_data["gyro"]["y"])
    gz_arrow = get_mpu_arrow(mpu_data["gyro"]["z"])
    
    print(f"Accelerometer: X: {ax_arrow} [{mpu_data['accel']['x']:.2f}g]  Y: {ay_arrow} [{mpu_data['accel']['y']:.2f}g]  Z: {az_arrow} [{mpu_data['accel']['z']:.2f}g]")
    print(f"Gyroscope:     X: {gx_arrow} [{mpu_data['gyro']['x']:.2f}°/s]  Y: {gy_arrow} [{mpu_data['gyro']['y']:.2f}°/s]  Z: {gz_arrow} [{mpu_data['gyro']['z']:.2f}°/s]")
    print(f"Temperature:   {mpu_data['temp']:.1f}°C")
    print("-" * 80)
    
    print("Controls:")
    print("Press 'q' twice to exit or Ctrl+C")
    print("Access web UI at: http://localhost:8080")

# Xbox controller handling
def read_xbox_controller():
    """Read input from Xbox controller"""
    global servo_speed, q_press_count, last_q_time
    
    if not CONTROLLER_AVAILABLE:
        print("Xbox controller not available.")
        return
    
    try:
        gamepad = evdev.InputDevice(DEVICE_PATH)
        print(f"Listening for input from {gamepad.name} ({DEVICE_PATH})")
        
        for event in gamepad.read_loop():
            # Check for keyboard input (q key)
            if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
                key = sys.stdin.read(1)
                if key == 'q':
                    current_time = time.time()
                    if current_time - last_q_time < 1.0:  # Double press within 1 second
                        q_press_count += 1
                    else:
                        q_press_count = 1
                    
                    last_q_time = current_time
                    
                    if q_press_count >= 2:
                        exit_handler()
            
            if event.type == evdev.ecodes.EV_ABS:
                if event.code == evdev.ecodes.ABS_X:  # Left Stick X → Servo 0
                    move_servo(0, event.value)
                elif event.code == evdev.ecodes.ABS_Y:  # Left Stick Y → Servo 1
                    move_servo(1, event.value)
                elif event.code == evdev.ecodes.ABS_RY:  # Right Stick Y → Servo 2
                    move_servo(2, event.value)
                elif event.code == evdev.ecodes.ABS_RX:  # Right Stick X → Servo 3
                    move_servo(3, event.value)
                # Left trigger to move servos toward 0
                elif event.code == evdev.ecodes.ABS_Z:
                    value = event.value / 1023.0  # Normalize trigger from 0 to 1
                    angle = int((1.0 - value) * 180)
                    move_all_servos(angle)
                # Right trigger to move servos toward 180
                elif event.code == evdev.ecodes.ABS_RZ:
                    value = event.value / 1023.0  # Normalize trigger from 0 to 1
                    angle = int(value * 180)
                    move_all_servos(angle)
            
            elif event.type == evdev.ecodes.EV_KEY:
                # Button A (south) - Channel 0 hold toggle
                if event.code == evdev.ecodes.BTN_SOUTH and event.value == 1:
                    hold_state[0] = not hold_state[0]
                    log_event("toggle_hold", {"channel": 0, "state": hold_state[0]})
                # Button X (west) - Channel 1 hold toggle
                elif event.code == evdev.ecodes.BTN_WEST and event.value == 1:
                    hold_state[1] = not hold_state[1]
                    log_event("toggle_hold", {"channel": 1, "state": hold_state[1]})
                # Button B (east) - Channel 2 hold toggle
                elif event.code == evdev.ecodes.BTN_EAST and event.value == 1:
                    hold_state[2] = not hold_state[2]
                    log_event("toggle_hold", {"channel": 2, "state": hold_state[2]})
                # Button Y (north) - Channel 3 hold toggle
                elif event.code == evdev.ecodes.BTN_NORTH and event.value == 1:
                    hold_state[3] = not hold_state[3]
                    log_event("toggle_hold", {"channel": 3, "state": hold_state[3]})
                # Left bumper - Decrease speed
                elif event.code == evdev.ecodes.BTN_TL and event.value == 1:
                    servo_speed = max(0.1, servo_speed - 0.1)
                    log_event("speed_change", {"speed": servo_speed})
                # Right bumper - Increase speed
                elif event.code == evdev.ecodes.BTN_TR and event.value == 1:
                    servo_speed = min(2.0, servo_speed + 0.1)
                    log_event("speed_change", {"speed": servo_speed})
            
            display_status()
    
    except FileNotFoundError:
        print(f"Error: Could not find controller at {DEVICE_PATH}. Make sure it's connected.")
    except PermissionError:
        print(f"Permission denied. Try running the script with 'sudo'.")
    except Exception as e:
        print(f"Controller error: {e}")

# Web server for UI interface
class ServoHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)
    
    def log_message(self, format, *args):
        # Suppress log messages to keep console clean
        pass
    
    def do_GET(self):
        if self.path == '/':
            self.path = '/servo_controller.html'
        elif self.path == '/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            data = {
                "servos": {str(ch): {
                    "position": servo_positions[ch],
                    "hold": hold_state[ch]
                } for ch in SERVO_CHANNELS},
                "mpu": mpu_data,
                "status": {
                    "pca": PCA_AVAILABLE,
                    "mpu": MPU_AVAILABLE,
                    "controller": CONTROLLER_AVAILABLE,
                    "bus": PCA_BUS,
                    "speed": servo_speed
                }
            }
            
            self.wfile.write(json.dumps(data).encode())
            return
        elif self.path == '/log':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            try:
                with open(LOG_FILE, 'r') as f:
                    log_content = f.read()
            except Exception:
                log_content = json.dumps(log_data)
            
            self.wfile.write(log_content.encode())
            return
        
        return http.server.SimpleHTTPRequestHandler.do_GET(self)
    
    def do_POST(self):
        if self.path == '/control':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            command = json.loads(post_data.decode())
            
            # Process commands
            if 'servo' in command:
                channel = int(command['servo']['channel'])
                angle = int(command['servo']['angle'])
                move_servo(channel, angle, False)
            
            if 'all' in command:
                angle = int(command['all'])
                move_all_servos(angle)
            
            if 'hold' in command:
                channel = int(command['hold']['channel'])
                state = bool(command['hold']['state'])
                hold_state[channel] = state
                log_event("toggle_hold", {"channel": channel, "state": state})
            
            if 'speed' in command:
                global servo_speed
                servo_speed = float(command['speed'])
                servo_speed = max(0.1, min(2.0, servo_speed))
                log_event("speed_change", {"speed": servo_speed})
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
            return
        
        self.send_response(404)
        self.end_headers()

def start_web_server():
    """Start the web server for UI"""
    handler = partial(ServoHandler)
    httpd = socketserver.ThreadingTCPServer(("", HTTP_PORT), handler)
    print(f"Web server started at http://localhost:{HTTP_PORT}")
    httpd.serve_forever()

def main_loop():
    """Main program loop"""
    global q_press_count, last_q_time
    
    while True:
        try:
            # Update MPU data
            get_mpu_data()
            
            # Display status
            display_status()
            
            # Check for 'q' key press
            if select.select([sys.stdin], [], [], 0)[0]:
                key = sys.stdin.read(1)
                if key == 'q':
                    current_time = time.time()
                    if current_time - last_q_time < 1.0:  # Double press within 1 second
                        q_press_count += 1
                    else:
                        q_press_count = 1
                    
                    last_q_time = current_time
                    
                    if q_press_count >= 2:
                        exit_handler()
            
            time.sleep(0.1)
        
        except KeyboardInterrupt:
            exit_handler()
        except Exception as e:
            print(f"Error in main loop: {e}")
            time.sleep(1)

if __name__ == "__main__":
    # Make stdin non-blocking for keyboard input
    fcntl.fcntl(sys.stdin, fcntl.F_SETFL, os.O_NONBLOCK)
    
    # Initialize devices
    init_devices()
    
    # Start web server thread
    web_thread = threading.Thread(target=start_web_server, daemon=True)
    web_thread.start()
    
    # If controller is available, start controller thread
    if CONTROLLER_AVAILABLE:
        controller_thread = threading.Thread(target=read_xbox_controller, daemon=True)
        controller_thread.start()
    
    # Start main program loop
    main_loop()
