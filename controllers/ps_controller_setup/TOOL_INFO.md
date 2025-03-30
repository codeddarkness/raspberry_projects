# PlayStation Controller Setup Tool

## Overview

This tool provides scripts for setting up PlayStation controllers on Raspberry Pi.

## Dependencies

- libusb-dev
- libbluetooth-dev
- joystick
- pkg-config
- python3-dev (for PS4 controller)
- python3-pip (for PS4 controller)

## Installation

All dependencies are automatically installed by the scripts.

## Configuration

The scripts handle all necessary configuration.

## Usage Examples

### PS3 Controller Setup

```bash
# Connect PS3 controller via USB
# Run sixpair to pair with Bluetooth
# Disconnect controller
# Press PS button to connect wirelessly
```

### PS4 Controller Setup

```bash
# Press and hold SHARE + PS buttons until light flashes
# Use bluetoothctl to pair and connect
# Restart Raspberry Pi
# Press PS button to connect
```

## Troubleshooting

- If controller doesn't connect, check Bluetooth is enabled
- For PS3 controller, try running sixpair again
- For PS4 controller, try using DS4DRV if Bluetooth method fails

## Credits

- SIXAD from Retropie: https://github.com/RetroPie/sixad
- DS4DRV: https://github.com/chrippa/ds4drv
