# PlayStation Controller Setup for Raspberry Pi

This directory contains scripts for setting up PlayStation controllers (PS3 and PS4) on your Raspberry Pi.

## Scripts

- **ps_controller_setup.sh**: Main script with menu-driven interface for both PS3 and PS4 controllers
- **ps3_controller_setup.sh**: Script specifically for PS3 controllers
- **ps4_controller_setup.sh**: Script specifically for PS4 controllers

## Usage

Run the main script:

```bash
chmod +x ps_controller_setup.sh
./ps_controller_setup.sh
```

Or run the controller-specific scripts:

```bash
# For PS3 controllers
chmod +x ps3_controller_setup.sh
./ps3_controller_setup.sh

# For PS4 controllers
chmod +x ps4_controller_setup.sh
./ps4_controller_setup.sh
```

## Features

- Support for both PS3 and PS4 controllers
- Multiple connection methods (Bluetooth, SIXAD, USB)
- Error handling and package dependency management
- Cleanup options to remove installations

## Version History

- v1.0.0: Initial release
