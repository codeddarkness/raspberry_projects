#!/bin/bash

# PCA9685 Servo Test Suite Installer
# This script installs the Servo Test Suite and its dependencies

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}=======================================${NC}"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check I2C setup
check_i2c() {
    print_header "Checking I2C Configuration"
    
    # Check if I2C is enabled in config
    if grep -q "^dtparam=i2c_arm=on" /boot/config.txt; then
        print_success "I2C is enabled in config.txt"
    else
        print_warning "I2C is not enabled in config.txt"
        print_info "Enabling I2C..."
        if ! grep -q "dtparam=i2c_arm" /boot/config.txt; then
            echo "dtparam=i2c_arm=on" >> /boot/config.txt
        else
            sed -i 's/^dtparam=i2c_arm=off/dtparam=i2c_arm=on/' /boot/config.txt
        fi
        print_success "I2C has been enabled in config.txt"
        print_warning "A reboot will be required for changes to take effect"
        REBOOT_REQUIRED=1
    fi
    
    # Check if I2C tools are installed
    if ! dpkg -l | grep -q "i2c-tools"; then
        print_info "Installing I2C tools..."
        apt install -y i2c-tools python3-smbus
        print_success "I2C tools installed"
    else
        print_success "I2C tools are already installed"
    fi
    
    # Check if the I2C module is loaded
    if lsmod | grep -q "i2c_bcm2708\|i2c_bcm2835"; then
        print_success "I2C kernel module is loaded"
        
        # Scan I2C bus for devices
        print_info "Scanning I2C bus for devices..."
        I2C_DEVICES=$(i2cdetect -y 1)
        echo "$I2C_DEVICES"
        
        # Look for PCA9685 (0x40)
        if echo "$I2C_DEVICES" | grep -q "40"; then
            print_success "PCA9685 device found at address 0x40"
            PCA9685_FOUND=1
        else
            print_warning "PCA9685 device not found at address 0x40"
            print_warning "Please check your connections"
            PCA9685_FOUND=0
        fi
    else
        print_error "I2C kernel module is not loaded"
        print_info "Try rebooting the system after this setup"
        REBOOT_REQUIRED=1
        PCA9685_FOUND=0
    fi
}

# Function to install Python dependencies
install_dependencies() {
    print_header "Installing Required Dependencies"
    
    # Install pip if not already installed
    if ! command -v pip3 &> /dev/null; then
        print_info "Installing pip3..."
        apt install -y python3-pip
    fi
    
    # Install required libraries
    print_info "Installing required Python libraries..."
    pip3 install RPi.GPIO adafruit-blinka
    pip3 install adafruit-circuitpython-pca9685
    pip3 install adafruit-circuitpython-motor
    
    print_success "Dependencies installed successfully"
}

# Function to install the Servo Test Suite
install_test_suite() {
    print_header "Installing Servo Test Suite"
    
    # Create directory for script
    mkdir -p /usr/local/bin
    
    # Create the test suite script
    cat > /usr/local/bin/servo_test_suite.py << 'END_OF_SCRIPT'
#!/usr/bin/env python3
"""
PCA9685 Servo Test Suite for Raspberry Pi

This program provides a comprehensive interface for testing servos connected to a PCA9685 controller.
Features:
- Channel selection for testing individual servos or groups
- Smooth movement from 0-180 degrees for all servos
- Smooth movement from 0-180 degrees for each servo individually
- Random movement sequences for selected servos
- Keyboard control of servo positions using arrow keys
"""

import time
import random
import os
import sys
import board
import busio
import curses
from adafruit_pca9685 import PCA9685
from adafruit_motor import servo

# Constants
MIN_PULSE = 600  # Adjust as needed for your servos
MAX_PULSE = 2400  # Adjust as needed for your servos
SERVO_COUNT = 16  # PCA9685 supports 16 channels
INCREMENT = 5     # Degrees to increment by in smooth movements

class ServoController:
    def __init__(self):
        # Initialize I2C bus and PCA9685
        self.i2c = busio.I2C(board.SCL, board.SDA)
        self.pca = PCA9685(self.i2c)
        
        # Set PWM frequency to 50Hz (good for servos)
        self.pca.frequency = 50
        
        # Initialize servo objects
        self.servos = []
        for channel in range(SERVO_COUNT):
            self.servos.append(servo.Servo(self.pca.channels[channel], 
                                           min_pulse=MIN_PULSE, 
                                           max_pulse=MAX_PULSE))
        
        # Initialize selection state
        self.selected_channels = [False] * SERVO_COUNT
        
    def cleanup(self):
        """Release resources and put servos in a safe position before exiting"""
        try:
            # Center all servos
            for channel in range(SERVO_COUNT):
                self.servos[channel].angle = 90
            time.sleep(0.5)
            # Deinit PCA9685
            self.pca.deinit()
        except Exception as e:
            print(f"Error during cleanup: {e}")
    
    def get_selected_channels(self):
        """Return a list of currently selected channel numbers"""
        return [i for i, selected in enumerate(self.selected_channels) if selected]
    
    def set_angle(self, channel, angle):
        """Set a specific channel to a specific angle"""
        try:
            self.servos[channel].angle = angle
        except Exception as e:
            print(f"Error setting angle on channel {channel}: {e}")
    
    def move_smooth(self, channel, start_angle, end_angle, step_time=0.01):
        """Move a servo smoothly from start_angle to end_angle"""
        # Determine step direction
        step = INCREMENT if start_angle < end_angle else -INCREMENT
        
        # Iterate through angles
        for angle in range(int(start_angle), int(end_angle) + (1 if step > 0 else -1), step):
            self.set_angle(channel, angle)
            time.sleep(step_time)
    
    def move_all_smooth(self, start_angle=0, end_angle=180):
        """Move all selected servos smoothly from start_angle to end_angle"""
        selected = self.get_selected_channels()
        if not selected:
            print("No servos selected!")
            return
        
        # Set all servos to start position
        for channel in selected:
            self.set_angle(channel, start_angle)
        time.sleep(0.5)
        
        # Determine step direction
        step = INCREMENT if start_angle < end_angle else -INCREMENT
        
        # Move all servos incrementally
        for angle in range(int(start_angle), int(end_angle) + (1 if step > 0 else -1), step):
            for channel in selected:
                self.set_angle(channel, angle)
            time.sleep(0.02)  # Short delay for smooth movement
    
    def move_each_smooth(self, start_angle=0, end_angle=180):
        """Move each selected servo smoothly from start_angle to end_angle, one at a time"""
        selected = self.get_selected_channels()
        if not selected:
            print("No servos selected!")
            return
            
        for channel in selected:
            print(f"Moving servo {channel}...")
            # Move to start position
            self.set_angle(channel, start_angle)
            time.sleep(0.5)
            # Move smoothly to end position
            self.move_smooth(channel, start_angle, end_angle)
            time.sleep(0.5)
    
    def move_random_sequence(self, duration=10, step_time=0.1):
        """Move selected servos in random positions for a specified duration"""
        selected = self.get_selected_channels()
        if not selected:
            print("No servos selected!")
            return
            
        end_time = time.time() + duration
        
        print(f"Performing random sequence for {duration} seconds...")
        while time.time() < end_time:
            # Choose a random channel from selected ones
            channel = random.choice(selected)
            # Choose a random angle
            angle = random.randint(0, 180)
            # Set the angle
            self.set_angle(channel, angle)
            time.sleep(step_time)
    
    def move_one_random_sequence(self, channel, duration=10, step_time=0.1):
        """Move one servo in a random sequence for a specified duration"""
        if channel < 0 or channel >= SERVO_COUNT:
            print(f"Invalid channel: {channel}")
            return
            
        if not self.selected_channels[channel]:
            print(f"Channel {channel} is not selected!")
            return
            
        end_time = time.time() + duration
        
        print(f"Performing random sequence for servo {channel} for {duration} seconds...")
        while time.time() < end_time:
            # Choose a random angle
            angle = random.randint(0, 180)
            # Set the angle
            self.set_angle(channel, angle)
            time.sleep(step_time)
            
    def keyboard_control(self, stdscr):
        """Control selected servos with arrow keys"""
        selected = self.get_selected_channels()
        if not selected:
            print("No servos selected!")
            return
            
        # Initialize all selected servos to 90 degrees (center)
        current_angles = {}
        for channel in selected:
            current_angles[channel] = 90
            self.set_angle(channel, 90)
        
        # Set up curses
        curses.curs_set(0)  # Hide the cursor
        stdscr.clear()
        stdscr.refresh()
        stdscr.nodelay(True)  # Non-blocking input
        stdscr.timeout(100)   # Update every 100ms
        
        # Display instructions
        stdscr.addstr(0, 0, "Servo Keyboard Control")
        stdscr.addstr(1, 0, "LEFT/RIGHT: Move servos")
        stdscr.addstr(2, 0, "Q: Quit")
        
        # Control loop
        running = True
        while running:
            # Display current angles
            for i, channel in enumerate(selected):
                stdscr.addstr(4 + i, 0, f"Servo {channel}: {current_angles[channel]} degrees ")
            
            # Process key input
            key = stdscr.getch()
            
            if key == ord('q') or key == ord('Q'):
                running = False
            elif key == curses.KEY_LEFT:
                # Decrease angle
                for channel in selected:
                    if current_angles[channel] > 0:
                        current_angles[channel] = max(0, current_angles[channel] - INCREMENT)
                        self.set_angle(channel, current_angles[channel])
            elif key == curses.KEY_RIGHT:
                # Increase angle
                for channel in selected:
                    if current_angles[channel] < 180:
                        current_angles[channel] = min(180, current_angles[channel] + INCREMENT)
                        self.set_angle(channel, current_angles[channel])
            
            stdscr.refresh()


def select_channels(controller):
    """Interactive menu for selecting servo channels"""
    while True:
        os.system('clear')
        print("=== Channel Selection ===")
        print("Current selection:")
        
        # Display all channels with selection status
        for i in range(SERVO_COUNT):
            status = "X" if controller.selected_channels[i] else " "
            print(f"[{status}] {i}")
        
        print("\nOptions:")
        print("0-15: Toggle channel")
        print("a: Select all channels")
        print("n: Clear selection")
        print("d: Done")
        
        choice = input("\nEnter choice: ").strip().lower()
        
        if choice == 'd':
            break
        elif choice == 'a':
            controller.selected_channels = [True] * SERVO_COUNT
        elif choice == 'n':
            controller.selected_channels = [False] * SERVO_COUNT
        elif choice.isdigit():
            channel = int(choice)
            if 0 <= channel < SERVO_COUNT:
                controller.selected_channels[channel] = not controller.selected_channels[channel]
            else:
                print(f"Invalid channel: {channel}")
                time.sleep(1)


def main_menu(controller):
    """Display the main menu and process user input"""
    while True:
        os.system('clear')
        print("=== PCA9685 Servo Test Suite ===")
        
        # Display selected channels
        selected = controller.get_selected_channels()
        if selected:
            print(f"Selected channels: {', '.join(map(str, selected))}")
        else:
            print("No channels selected!")
        
        print("\nOptions:")
        print("1. Select channels")
        print("2. Move all selected servos smoothly from 0-180")
        print("3. Move each selected servo smoothly from 0-180")
        print("4. Move selected servos in random sequence")
        print("5. Move one selected servo in random sequence")
        print("6. Control servos with keyboard arrow keys")
        print("0. Exit")
        
        choice = input("\nEnter choice: ").strip()
        
        if choice == '0':
            break
        elif choice == '1':
            select_channels(controller)
        elif choice == '2':
            controller.move_all_smooth()
        elif choice == '3':
            controller.move_each_smooth()
        elif choice == '4':
            duration = input("Enter duration in seconds [10]: ").strip()
            if not duration:
                duration = 10
            controller.move_random_sequence(int(duration))
        elif choice == '5':
            selected = controller.get_selected_channels()
            if not selected:
                print("No channels selected!")
                time.sleep(1)
                continue
                
            channel_str = input(f"Enter channel to test {selected}: ").strip()
            try:
                channel = int(channel_str)
                if channel not in selected:
                    print(f"Channel {channel} is not in selected channels!")
                    time.sleep(1)
                    continue
                    
                duration = input("Enter duration in seconds [10]: ").strip()
                if not duration:
                    duration = 10
                controller.move_one_random_sequence(channel, int(duration))
            except ValueError:
                print("Invalid channel number!")
                time.sleep(1)
        elif choice == '6':
            # Run keyboard control mode
            print("Entering keyboard control mode...")
            time.sleep(1)
            curses.wrapper(controller.keyboard_control)
        else:
            print("Invalid choice!")
            time.sleep(1)


def check_requirements():
    """Check if all required components are available"""
    try:
        # Check if connected to a Raspberry Pi
        if not os.path.exists('/sys/firmware/devicetree/base/model'):
            print("Warning: This doesn't appear to be a Raspberry Pi!")
            choice = input("Continue anyway? (y/n): ").strip().lower()
            if choice != 'y':
                return False
        
        # Check if the PCA9685 is connected
        try:
            i2c = busio.I2C(board.SCL, board.SDA)
            pca = PCA9685(i2c)
            pca.deinit()
        except Exception as e:
            print(f"Error: Cannot connect to PCA9685: {e}")
            print("Make sure the device is properly connected and enabled in I2C.")
            return False
        
        return True
    except Exception as e:
        print(f"Error checking requirements: {e}")
        return False


if __name__ == "__main__":
    print("PCA9685 Servo Test Suite")
    
    if not check_requirements():
        print("Exiting due to unmet requirements.")
        sys.exit(1)
    
    controller = ServoController()
    
    try:
        # Start with all channels deselected
        controller.selected_channels = [False] * SERVO_COUNT
        
        # Display main menu
        main_menu(controller)
        
    except KeyboardInterrupt:
        print("\nProgram interrupted by user.")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # Clean up resources
        controller.cleanup()
        print("Servo test suite exited.")
END_OF_SCRIPT

    # Make the script executable
    chmod +x /usr/local/bin/servo_test_suite.py
    
    # Create a convenient wrapper script
    cat > /usr/local/bin/servo-test << 'EOF'
#!/bin/bash
sudo python3 /usr/local/bin/servo_test_suite.py
EOF
    
    # Make the wrapper executable
    chmod +x /usr/local/bin/servo-test
    
    print_success "Servo Test Suite installed successfully"
    print_info "You can run it by typing 'servo-test' in the terminal"
}

# Main function
main() {
    print_header "PCA9685 Servo Test Suite Installer"
    
    # Check if running as root
    check_root
    
    # Check I2C configuration
    check_i2c
    
    # Install dependencies
    install_dependencies
    
    # Install the test suite
    install_test_suite
    
    # Check if reboot is needed
    if [ "$REBOOT_REQUIRED" = "1" ]; then
        print_warning "A system reboot is required for all changes to take effect"
        read -p "Would you like to reboot now? (y/n): " REBOOT_NOW
        if [[ $REBOOT_NOW =~ ^[Yy]$ ]]; then
            print_info "Rebooting system..."
            reboot
        else
            print_info "Please remember to reboot your system later"
        fi
    fi
    
    print_header "Installation Complete"
    print_info "To run the Servo Test Suite, type 'servo-test' in the terminal"
    
    # Show usage instructions if PCA9685 was found
    if [ "$PCA9685_FOUND" = "1" ]; then
        print_info "Your PCA9685 was detected at address 0x40"
        print_info "You can start testing your servos immediately"
    else
        print_warning "No PCA9685 was detected on the I2C bus"
        print_info "Make sure your PCA9685 is properly connected and try again after rebooting"
    fi
}

# Run the main function
main

exit 0

