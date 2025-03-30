#!/usr/bin/env python3
import time
import json
import inputs
import board
import busio
from adafruit_pca9685 import PCA9685
from mpu6050 import MPU6050  # Correct import
import threading
from smbus2 import SMBus

# Initialize I2C and PCA9685
i2c = busio.I2C(board.SCL, board.SDA)
pca = PCA9685(i2c)
pca.frequency = 60

# Initialize MPU6050 (use bus 1)
#mpu = MPU6050(1)  # Pass bus number (1) instead of the I2C object



try:
    bus4 = SMBus(4)  # Use bus 4 (GPIO 23 & 24)
    mpu = mpu6050(0x68, bus=bus4)  # Ensure we use bus 4
    print("MPU6050 initialized on bus 4")
except Exception as e:
    print(f"Error initializing MPU6050: {e}")
    mpu = None


# Set up servos
servo_channels = [0, 1, 2, 3]
servo_locked = [False, False, False, False]
servo_angles = [90, 90, 90, 90]  # Initial positions at 90 degrees

# Initialize Xbox controller status
controller_status = "DISCONNECTED"

# Log file for JSON data
log_file = "servo_log.json"

def read_mpu_data():
    """Read data from the MPU6050 and return accelerometer and gyro readings."""
    accel_data = mpu.get_accel_data()
    gyro_data = mpu.get_gyro_data()
    return accel_data, gyro_data

def update_servo_angles(channel, angle):
    """Update the servo angle and lock status."""
    if not servo_locked[channel]:
        angle = max(0, min(180, angle))  # Ensure within 0-180 degrees
        servo_angles[channel] = angle
        pca.channels[channel].duty_cycle = int((angle / 180.0) * 65535)

def handle_controller_input():
    """Handle Xbox controller input for servo control."""
    global controller_status
    while True:
        try:
            events = inputs.get_key()
            for event in events:
                if event.ev_type == 'Key':
                    if event.ev_code == 'BTN_SOUTH':  # A button
                        servo_locked[0] = not servo_locked[0]
                    elif event.ev_code == 'BTN_WEST':  # X button
                        servo_locked[1] = not servo_locked[1]
                    elif event.ev_code == 'BTN_EAST':  # B button
                        servo_locked[2] = not servo_locked[2]
                    elif event.ev_code == 'BTN_NORTH':  # Y button
                        servo_locked[3] = not servo_locked[3]
                    # Joystick inputs
                    if event.ev_code == 'ABS_X':  # Left Joystick X axis
                        update_servo_angles(0, 90 + int(event.ev_value * 90 / 32767))
                    elif event.ev_code == 'ABS_Y':  # Left Joystick Y axis
                        update_servo_angles(1, 90 + int(event.ev_value * 90 / 32767))
                    elif event.ev_code == 'ABS_RX':  # Right Joystick X axis
                        update_servo_angles(2, 90 + int(event.ev_value * 90 / 32767))
                    elif event.ev_code == 'ABS_RY':  # Right Joystick Y axis
                        update_servo_angles(3, 90 + int(event.ev_value * 90 / 32767))

            time.sleep(0.1)

        except Exception as e:
            print(f"Error handling controller input: {e}")
            time.sleep(1)

def check_i2c_devices():
    """Check if MPU6050 and PCA9685 are connected on I2C."""
    try:
        mpu_data = mpu.get_accel_data()
        pca_data = pca.channels[0].duty_cycle
        return "CONNECTED"
    except Exception:
        return "DISCONNECTED"

def save_log():
    """Save the log to a JSON file."""
    log_data = {
        "servo_angles": servo_angles,
        "servo_locked": servo_locked,
        "mpu_data": read_mpu_data(),
        "controller_status": controller_status,
        "i2c_status": check_i2c_devices()
    }
    with open(log_file, "w") as f:
        json.dump(log_data, f)

def main():
    global controller_status
    # Start the controller input handler in a separate thread
    controller_thread = threading.Thread(target=handle_controller_input)
    controller_thread.start()

    try:
        while True:
            # Update servo positions in the console
            print(f"Servo 0: {servo_angles[0]} {'→' if not servo_locked[0] else 'X'}")
            print(f"Servo 1: {servo_angles[1]} {'→' if not servo_locked[1] else 'X'}")
            print(f"Servo 2: {servo_angles[2]} {'→' if not servo_locked[2] else 'X'}")
            print(f"Servo 3: {servo_angles[3]} {'→' if not servo_locked[3] else 'X'}")
            print(f"MPU Data: {read_mpu_data()}")
            print(f"Controller Status: {controller_status}")
            print(f"I2C Status: {check_i2c_devices()}")

            # Save log periodically
            save_log()
            time.sleep(1)
    except KeyboardInterrupt:
        print("Ctrl+C to exit")
        controller_thread.join()

if __name__ == "__main__":
    main()

