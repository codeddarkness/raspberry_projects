#!/usr/bin/env bash

function end_break(){
echo -e "#######################################\n"
}

# servo_controller.py
# templates/servo_controller.html
echo -e "TESTING curl -X POST http://127.0.0.1:5000/update_servo -H "Content-Type: application/json" -d '{"servo": 0, "angle": 90}'"
curl -X POST http://127.0.0.1:5000/update_servo -H "Content-Type: application/json" -d '{"servo": 0, "angle": 90}' && end_break
echo -e "\nTESTING curl -sq localhost:8080"
(curl -sq localhost:8080 || echo "error" ) | html2text && end_break
echo -e "\nTESTING curl -sq localhost:5000"
(curl -sq  localhost:5000 || echo "error" ) | html2text && end_break
