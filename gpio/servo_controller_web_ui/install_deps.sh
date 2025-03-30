#!/bin/bash

# Update and install basic dependencies
echo "Updating system..."
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y python3-pip python3-dev python3-venv

# Install Python libraries
echo "Installing required Python libraries..."

# Install libraries needed for the project
pip3 install adafruit-pca9685 mpu6050 inputs

# If you're using the Raspberry Pi, ensure you have I2C enabled
echo "Enabling I2C on Raspberry Pi..."

sudo raspi-config nonint do_i2c 0

# Install other system dependencies (if needed)
echo "Installing additional system dependencies..."
sudo apt-get install -y i2c-tools

# Verify the installation of I2C devices
echo "Verifying I2C devices..."
i2cdetect -y 1

echo "Installation complete!"

