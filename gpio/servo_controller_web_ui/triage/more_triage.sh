#!/bin/bash

# Check if the WebSocket server is running on the expected port (8765)
echo "Checking WebSocket server status on ws://localhost:8765..."
ws_status=$(netstat -tuln | grep ':8765')
if [ -n "$ws_status" ]; then
    echo "WebSocket server is running on port 8765."
else
    echo "Error: WebSocket server is not running on port 8765. Please start the server."
fi

# Check if HTTP server is running on port 8080
echo "Checking HTTP server status on http://localhost:8080..."
http_status=$(netstat -tuln | grep ':8080')
if [ -n "$http_status" ]; then
    echo "HTTP server is running on port 8080."
else
    echo "Error: HTTP server is not running on port 8080. Please start the server."
fi

# Check for HTTPS request issues by making a request via curl
echo "Testing if HTTP (not HTTPS) is working correctly..."
http_test=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
if [ "$http_test" -eq 200 ]; then
    echo "HTTP request successful on http://localhost:8080."
else
    echo "Error: HTTP request failed with status code $http_test. Ensure you're not using HTTPS incorrectly."
fi

# Check for any CORS issues by using curl to test the WebSocket endpoint
echo "Checking WebSocket connection (using curl)..."
ws_test=$(curl -s -I -X GET http://localhost:8080)
if [[ "$ws_test" == *"200 OK"* ]]; then
    echo "CORS should not be an issue if HTTP server is responding fine."
else
    echo "Warning: Potential CORS issues with WebSocket connection or HTTP server. Check your server's CORS configuration."
fi

# Test WebSocket connection using websocat
echo "Testing WebSocket connection using websocat..."
if command -v websocat > /dev/null; then
    websocat ws://localhost:8765
else
    echo "Error: websocat is not installed. Please install websocat to test WebSocket connections."
fi

# Optional: Check if the front-end (browser) is sending WebSocket requests correctly
# This can be done manually in the browser console. We won't automate this via bash directly.
echo "To check WebSocket interaction in the browser, open your browser console (F12) and check for errors or logs from the WebSocket connection."

# End of script
echo "Diagnostics complete."

