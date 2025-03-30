#!/bin/bash

# Function to check if the HTTP server (Flask) is running
check_http_server() {
    echo "Checking HTTP server status..."
    if netstat -tuln | grep ':5000' > /dev/null; then
        echo "HTTP server is running on port 5000."
    else
        echo "HTTP server is NOT running on port 5000."
        echo "Attempting to restart the HTTP server..."
        sudo systemctl restart flask_service_name  # Replace with the actual service name if using systemd
        if netstat -tuln | grep ':5000' > /dev/null; then
            echo "HTTP server successfully restarted."
        else
            echo "Failed to restart HTTP server. Check the Flask application for issues."
        fi
    fi
}

# Function to check if the WebSocket server is running
check_websocket_server() {
    echo "Checking WebSocket server status..."
    if netstat -tuln | grep ':8765' > /dev/null; then
        echo "WebSocket server is running on port 8765."
    else
        echo "WebSocket server is NOT running on port 8765."
        echo "Please check the WebSocket server initialization in your code."
    fi
}

# Function to check for 404 and 400 errors in the server log
check_log_errors() {
    echo "Checking for 404 and 400 errors in the server log..."
    if grep -q "404" /home/pi/servo_project/controller/webui/server.log; then
        echo "404 ERROR: Found 404 errors in the server log."
    else
        echo "No 404 errors found."
    fi

    if grep -q "400" /home/pi/servo_project/controller/webui/server.log; then
        echo "400 ERROR: Found 400 errors in the server log."
    else
        echo "No 400 errors found."
    fi
}

# Function to check for malformed HTTP requests in the server log
check_malformed_requests() {
    echo "Checking for malformed HTTP requests in the server log..."
    if grep -a -q "binary file matches" /home/pi/servo_project/controller/webui/server.log; then
        echo "Malformed HTTP request detected."
    else
        echo "No malformed HTTP requests detected."
    fi
}

# Check for running WebSocket and HTTP servers
check_websocket_server
check_http_server

# Check for errors in the server log
check_log_errors

# Check for malformed HTTP requests
check_malformed_requests

echo "All checks completed."

