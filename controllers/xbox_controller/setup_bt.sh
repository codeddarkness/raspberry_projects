cat <<SKIP >/dev/null
# Instructions to connect a PS3 controller via Bluetooth
echo "\nTo enable and pair a PS3 controller over Bluetooth, follow these steps:"
echo "1. Install required packages:"
echo "   sudo apt update && sudo apt install bluez sixad"
echo "2. Start the Bluetooth service:"
echo "   sudo systemctl start bluetooth"
echo "3. Enable the sixad service:"
echo "   sudo systemctl enable sixad"
echo "4. Run sixpair to pair the controller via USB:"
echo "   sudo sixpair"
echo "5. Disconnect USB and press the PS button to connect via Bluetooth."
SKIP

sudo apt update
sudo apt install bluetooth pi-bluetooth bluez bluez-tools
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

cat <<EOI
bluetoothctl
power on
agent on
scan on
pair XX:XX:XX:XX:XX:XX
connect XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
exit
hcitool con
EOI

python -m evdev.evtest

