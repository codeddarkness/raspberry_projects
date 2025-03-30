#!/bin/bash

# Log file location
LOG_FILE="/home/pi/servo_project/controller/webui/server.log"

# PCA9685 check
echo "Checking PCA9685 status..."
if i2cdetect -y 1 | grep -q "40"; then
  echo "PCA9685: CONNECTED"
else
  echo "PCA9685: NOT FOUND"
fi

# MPU6050 check
echo "Checking MPU6050 status..."
if i2cdetect -y 1 | grep -q "68"; then
  echo "MPU6050: CONNECTED"
else
  echo "MPU6050: NOT FOUND"
fi

# Xbox Controller check
echo "Checking Xbox controller status..."
if lsusb | grep -iq "Xbox"; then
  echo "Xbox Controller: CONNECTED"
else
  echo "Xbox Controller: NOT FOUND"
fi

# Check WebSocket Server
echo "Checking WebSocket server status..."
if netstat -tuln | grep -q ":8765"; then
  echo "WebSocket server is running on port 8765"
else
  echo "WebSocket server is NOT running on port 8765"
fi

# Check for HTTP server on port 5000
echo "Checking HTTP server status..."
if netstat -tuln | grep -q ":5000"; then
  echo "HTTP server is running on port 5000"
else
  echo "HTTP server is NOT running on port 5000"
fi

# Check for 404 or 400 errors in the log file
echo "Checking for 404 and 400 errors in the server log..."
if grep -q "404" "$LOG_FILE"; then
  echo "404 ERROR: Found 404 errors in the server log"
else
  echo "404 ERROR: No 404 errors found in the log"
fi

if grep -q "400" "$LOG_FILE"; then
  echo "400 ERROR: Found 400 errors in the server log"
else
  echo "400 ERROR: No 400 errors found in the log"
fi

# Checking if the last HTTP request in the log is malformed
echo "Checking for malformed HTTP requests in the server log..."
if grep -E "Bad request version|Malformed" "$LOG_FILE"; then
  echo "Malformed HTTP request detected"
else
  echo "No malformed HTTP requests found"
fi

echo "All checks completed."

