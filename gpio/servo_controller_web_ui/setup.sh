#!/bin/bash

# Update and upgrade system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install required system packages
echo "Installing necessary packages..."
sudo apt install -y python3-pip python3-venv joystick bluetooth bluez bluez-tools

# Enable I2C
echo "Enabling I2C..."
sudo raspi-config nonint do_i2c 0

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install flask smbus pygame adafruit-circuitpython-pca9685 mpu6050-raspberrypi

# Configure permissions for Xbox controller support
echo "Configuring Xbox controller support..."
sudo modprobe uinput
sudo chmod 666 /dev/uinput

# Check for I2C devices
echo "Checking I2C devices..."
sudo i2cdetect -y 1

# Display completion message
echo "Setup complete. You can now run python3 servo_controller.py"

