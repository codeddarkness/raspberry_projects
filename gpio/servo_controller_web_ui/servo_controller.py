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
import random
import select
import fcntl
from datetime import datetime
from functools import partial
import websockets
import asyncio
import logging
import psutil  # Used to check if a process is already running

# Set up logging configuration
logging.basicConfig(
    level=logging.DEBUG,  # Adjust log level to DEBUG
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]  # Logs to console
)

# Try to import hardware libraries, but continue if not available
try:
    import Adafruit_PCA9685
    PCA9685_AVAILABLE = True
except ImportError:
    PCA9685_AVAILABLE = False
    logging.warning("Warning: Adafruit_PCA9685 library not found. Servo control will be simulated.")
    
try:
    import smbus
    import math
    SMBUS_AVAILABLE = True
except ImportError:
    SMBUS_AVAILABLE = False
    logging.warning("Warning: smbus library not found. I2C communication will be simulated.")

# Global variables
DEVICE_PATH = None
CONTROLLER_AVAILABLE = False
HTTP_PORT = 8080
WEB_DIR = os.path.dirname(os.path.abspath(__file__))  # Current directory
SERVO_MIN = 150
SERVO_MAX = 600
SERVO_RANGE = 180
SERVO_CHANNELS = [0, 1, 2, 3]
hold_state = {0: False, 1: False, 2: False, 3: False}
servo_positions = {0: 90, 1: 90, 2: 90, 3: 90}
servo_speed = 1.0
MPU_ADDR = 0x68
MPU_AVAILABLE = False
mpu_data = {
    "accel": {"x": 0, "y": 0, "z": 0},
    "gyro": {"x": 0, "y": 0, "z": 0},
    "temp": 0
}
PCA_ADDR = 0x40
PCA_AVAILABLE = False
PCA_BUS = 1
q_press_count = 0
last_q_time = 0
LOG_FILE = "servo_controller_log.json"
log_data = []

# Initialize devices
def init_devices():
    global pwm, PCA_AVAILABLE, MPU_AVAILABLE, PCA_BUS, DEVICE_PATH, CONTROLLER_AVAILABLE
    logging.info("Initializing devices...")

    # Initialize PCA9685 (Servo Controller)
    if PCA9685_AVAILABLE:
        try:
            pwm = Adafruit_PCA9685.PCA9685(busnum=1)
            pwm.set_pwm_freq(50)
            PCA_AVAILABLE = True
            PCA_BUS = 1
            logging.info("PCA9685 found on I2C bus 1")
        except Exception as e:
            logging.error(f"Failed to initialize PCA9685 on bus 1: {e}")

    # Fallback dummy PWM controller if PCA9685 is not available
    if not PCA_AVAILABLE:
        class DummyPWM:
            def set_pwm(self, channel, on, pulse):
                pass
            def set_all_pwm(self, on, off):
                pass
            def set_pwm_freq(self, freq):
                pass
        pwm = DummyPWM()

    # Initialize MPU6050 (Gyro/Accelerometer)
    if SMBUS_AVAILABLE:
        for bus_num in range(3):
            try:
                bus = smbus.SMBus(bus_num)
                bus.write_byte_data(MPU_ADDR, 0x6B, 0)
                MPU_AVAILABLE = True
                logging.info(f"MPU6050 found on I2C bus {bus_num}")
                break
            except Exception as e:
                logging.error(f"Failed to initialize MPU6050 on bus {bus_num}: {e}")
        if not MPU_AVAILABLE:
            logging.warning("No MPU6050 found on any I2C bus.")

    # Initialize Xbox Controller
    try:
        devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
        for device in devices:
            if "xbox" in device.name.lower() or "microsoft" in device.name.lower():
                DEVICE_PATH = device.path
                CONTROLLER_AVAILABLE = True
                logging.info(f"Xbox controller found: {device.name} at {DEVICE_PATH}")
                break
    except Exception as e:
        logging.error(f"Error detecting controllers: {e}")

# Servo control functions
def joystick_to_pwm(value):
    angle = int(((value + 32767) / 65534) * SERVO_RANGE)
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    return pwm_value, angle

def angle_to_pwm(angle):
    angle = max(0, min(180, angle))
    pwm_value = int(SERVO_MIN + (angle / SERVO_RANGE) * (SERVO_MAX - SERVO_MIN))
    return pwm_value

def move_servo(channel, value, is_joystick=True):
    if not hold_state[channel]:
        if is_joystick:
            if channel == 0 or channel == 3:
                value = -value
            pwm_value, angle = joystick_to_pwm(value)
        else:
            angle = value
            pwm_value = angle_to_pwm(angle)

        current_angle = servo_positions[channel]
        angle_diff = angle - current_angle
        if abs(angle_diff) > 0:
            step = max(1, min(abs(angle_diff), int(abs(angle_diff) * servo_speed)))
            angle = current_angle + step if angle_diff > 0 else current_angle - step
            pwm_value = angle_to_pwm(angle)

        pwm.set_pwm(channel, 0, pwm_value)
        servo_positions[channel] = angle
        log_event("servo_move", {"channel": channel, "angle": angle})
        logging.debug(f"Servo {channel} moved to angle {angle}")

# Event logging
def log_event(event_type, data):
    global log_data
    event = {
        "timestamp": datetime.now().isoformat(),
        "type": event_type,
        "data": data
    }
    log_data.append(event)
    if len(log_data) % 10 == 0:
        try:
            with open(LOG_FILE, 'w') as f:
                json.dump(log_data, f, indent=2)
            logging.debug("Logged events to file.")
        except Exception as e:
            logging.error(f"Error writing to log file: {e}")

# WebSocket server for real-time updates
async def serve_websocket(websocket, path):
    logging.debug(f"New WebSocket connection from {path}")
    try:
        while True:
            data = {
                "servos": [
                    {"position": servo_positions[ch], "hold": hold_state[ch]} for ch in SERVO_CHANNELS
                ],
                "mpu": mpu_data,
                "status": {
                    "pca": PCA_AVAILABLE,
                    "mpu": MPU_AVAILABLE,
                    "controller": CONTROLLER_AVAILABLE,
                    "bus": PCA_BUS,
                    "speed": servo_speed
                }
            }
            logging.debug("Sending WebSocket data: %s", json.dumps(data))  # Debug log
            await websocket.send(json.dumps(data))
            logging.debug("Sent WebSocket data.")
            await asyncio.sleep(0.1)
    except Exception as e:
        logging.error(f"Error in WebSocket connection: {e}")

# WebSocket server start
async def start_websocket_server():
    logging.info("Starting WebSocket server on ws://localhost:8765")
    await websockets.serve(serve_websocket, "localhost", 8765)
    logging.debug("WebSocket server started.")

# Function to kill any running HTTP server on the same port
def kill_existing_http_server(port=HTTP_PORT):
    logging.info(f"Checking for existing HTTP server on port {port}...")
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        if proc.info['cmdline'] and f"python3" in proc.info['cmdline'][0]:
            if f"SimpleHTTPServer" in " ".join(proc.info['cmdline']):
                logging.info(f"Killing process {proc.info['pid']} (already running HTTP server)")
                proc.terminate()  # Terminate the existing process
                proc.wait()  # Wait for it to terminate
                logging.info(f"Terminated existing HTTP server process.")

# Serve the Web UI at HTTP port
def start_http_server():
    kill_existing_http_server()  # Kill any existing HTTP server before starting
    os.chdir(os.path.join(WEB_DIR, 'templates'))  # Change to the templates folder
    handler = http.server.SimpleHTTPRequestHandler
    httpd = socketserver.TCPServer(("", HTTP_PORT), handler)
    logging.info(f"Serving Web UI at http://localhost:{HTTP_PORT}")
    httpd.serve_forever()

# Run the event loop
if __name__ == "__main__":
    init_devices()  # Initialize devices
    threading.Thread(target=start_http_server, daemon=True).start()  # Start HTTP server
    asyncio.run(start_websocket_server())  # Start WebSocket server

    # Keep the program running to serve the web interface
    try:
        while True:
            time.sleep(1)  # Sleep to keep the main thread running
    except KeyboardInterrupt:
        logging.info("Shutting down...")
        sys.exit(0)

