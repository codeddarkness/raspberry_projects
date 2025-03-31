#!/bin/bash

# Raspberry Pi File Sharing Client Setup Script
# This script analyzes NFS and Samba configurations to help set up client-side mounts

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect server IP
detect_server_ip() {
    echo ""
    read -p "Enter Raspberry Pi server IP address: " SERVER_IP
    
    if [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid IP address format"
        detect_server_ip
        return
    fi
    
    # Test if server is reachable
    if ! ping -c 1 -W 2 "$SERVER_IP" &> /dev/null; then
        print_warning "Server at $SERVER_IP is not responding to ping"
        read -p "Continue anyway? (y/n) [n]: " CONTINUE
        CONTINUE=${CONTINUE:-n}
        if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
            detect_server_ip
            return
        fi
    else
        print_success "Server at $SERVER_IP is reachable"
    fi
}

# Function to analyze NFS exports on the server
analyze_nfs_exports() {
    print_info "Analyzing NFS exports on $SERVER_IP..."
    
    # Check if NFS client is installed
    if ! command -v showmount &> /dev/null; then
        print_warning "NFS client tools not installed"
        read -p "Install NFS client tools? (y/n) [y]: " INSTALL_NFS
        INSTALL_NFS=${INSTALL_NFS:-y}
        
        if [[ $INSTALL_NFS =~ ^[Yy]$ ]]; then
            apt update
            apt install nfs-common -y
        else
            print_error "NFS client tools are required to analyze NFS exports"
            return 1
        fi
    fi
    
    # Get NFS exports from server
    NFS_EXPORTS=$(showmount -e "$SERVER_IP" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get NFS exports from $SERVER_IP"
        print_info "Please check if NFS server is running and ports are open"
        return 1
    fi
    
    if [ -z "$NFS_EXPORTS" ]; then
        print_warning "No NFS exports found on $SERVER_IP"
        return 1
    fi
    
    print_success "Found NFS exports on $SERVER_IP:"
    echo "$NFS_EXPORTS" | sed 's/^/    /'
    
    # Parse and store exports
    NFS_EXPORT_PATHS=()
    while read -r line; do
        if [[ $line =~ ^Export\ list\ for ]]; then
            continue
        fi
        export_path=$(echo "$line" | awk '{print $1}')
        NFS_EXPORT_PATHS+=("$export_path")
    done <<< "$NFS_EXPORTS"
    
    return 0
}

# Function to analyze Samba shares on the server
analyze_samba_shares() {
    print_info "Analyzing Samba shares on $SERVER_IP..."
    
    # Check if smbclient is installed
    if ! command -v smbclient &> /dev/null; then
        print_warning "Samba client tools not installed"
        read -p "Install Samba client tools? (y/n) [y]: " INSTALL_SMB
        INSTALL_SMB=${INSTALL_SMB:-y}
        
        if [[ $INSTALL_SMB =~ ^[Yy]$ ]]; then
            apt update
            apt install smbclient -y
        else
            print_error "Samba client tools are required to analyze Samba shares"
            return 1
        fi
    fi
    
    # Get Samba shares from server (anonymous)
    SMB_SHARES=$(smbclient -L "$SERVER_IP" -N 2>/dev/null | grep Disk)
    
    if [ $? -ne 0 ] || [ -z "$SMB_SHARES" ]; then
        print_warning "No anonymous Samba shares found or access denied"
        read -p "Enter username for Samba authentication: " SMB_USER
        
        if [ -n "$SMB_USER" ]; then
            read -sp "Enter password for $SMB_USER: " SMB_PASS
            echo ""
            SMB_SHARES=$(smbclient -L "$SERVER_IP" -U "$SMB_USER%$SMB_PASS" 2>/dev/null | grep Disk)
            
            if [ $? -ne 0 ] || [ -z "$SMB_SHARES" ]; then
                print_error "Authentication failed or no Samba shares found"
                return 1
            fi
        else
            print_error "Username required for Samba authentication"
            return 1
        fi
    fi
    
    print_success "Found Samba shares on $SERVER_IP:"
    echo "$SMB_SHARES" | sed 's/^/    /'
    
    # Parse and store shares
    SMB_SHARE_NAMES=()
    while read -r line; do
        share_name=$(echo "$line" | awk '{print $1}')
        SMB_SHARE_NAMES+=("$share_name")
    done <<< "$SMB_SHARES"
    
    # Store SMB credentials if available
    if [ -n "$SMB_USER" ] && [ -n "$SMB_PASS" ]; then
        SMB_CREDENTIALS="username=$SMB_USER
password=$SMB_PASS"
    fi
    
    return 0
}

# Function to generate fstab entries for NFS
generate_nfs_fstab() {
    if [ ${#NFS_EXPORT_PATHS[@]} -eq 0 ]; then
        print_error "No NFS exports found to generate fstab entries"
        return 1
    fi
    
    echo ""
    print_info "Generating fstab entries for NFS mounts:"
    echo ""
    
    NFS_FSTAB_ENTRIES=()
    NFS_MOUNT_POINTS=()
    
    for export_path in "${NFS_EXPORT_PATHS[@]}"; do
        echo "NFS Export: $export_path"
        
        # Suggest a mount point
        default_mount_point="/mnt/nfs$(echo "$export_path" | tr '/' '_')"
        read -p "Enter local mount point [$default_mount_point]: " mount_point
        mount_point=${mount_point:-$default_mount_point}
        
        # Create mount point if it doesn't exist
        if [ ! -d "$mount_point" ]; then
            mkdir -p "$mount_point"
            print_success "Created mount point: $mount_point"
        fi
        
        # NFS mount options
        read -p "Auto mount at boot? (y/n) [y]: " AUTO_MOUNT
        AUTO_MOUNT=${AUTO_MOUNT:-y}
        
        if [[ $AUTO_MOUNT =~ ^[Yy]$ ]]; then
            MOUNT_OPTION="auto"
        else
            MOUNT_OPTION="noauto"
        fi
        
        # Generate fstab entry
        FSTAB_ENTRY="$SERVER_IP:$export_path $mount_point nfs rw,${MOUNT_OPTION},noatime,soft,intr 0 0"
        NFS_FSTAB_ENTRIES+=("$FSTAB_ENTRY")
        NFS_MOUNT_POINTS+=("$mount_point")
        
        echo "Fstab entry: $FSTAB_ENTRY"
        echo ""
    done
    
    return 0
}

# Function to generate fstab entries for Samba
generate_samba_fstab() {
    if [ ${#SMB_SHARE_NAMES[@]} -eq 0 ]; then
        print_error "No Samba shares found to generate fstab entries"
        return 1
    fi
    
    echo ""
    print_info "Generating fstab entries for Samba mounts:"
    echo ""
    
    # Check if cifs-utils is installed
    if ! command -v mount.cifs &> /dev/null; then
        print_warning "CIFS utilities not installed"
        read -p "Install CIFS utilities? (y/n) [y]: " INSTALL_CIFS
        INSTALL_CIFS=${INSTALL_CIFS:-y}
        
        if [[ $INSTALL_CIFS =~ ^[Yy]$ ]]; then
            apt update
            apt install cifs-utils -y
        else
            print_error "CIFS utilities are required to mount Samba shares"
            return 1
        fi
    fi
    
    SMB_FSTAB_ENTRIES=()
    SMB_MOUNT_POINTS=()
    CREDENTIALS_FILE="/etc/samba/credentials"
    
    # Create credentials file if we have username/password
    if [ -n "$SMB_CREDENTIALS" ]; then
        echo "$SMB_CREDENTIALS" > "$CREDENTIALS_FILE"
        chmod 600 "$CREDENTIALS_FILE"
        print_success "Created credentials file: $CREDENTIALS_FILE"
    fi
    
    for share_name in "${SMB_SHARE_NAMES[@]}"; do
        echo "Samba Share: $share_name"
        
        # Suggest a mount point
        default_mount_point="/mnt/samba/$share_name"
        read -p "Enter local mount point [$default_mount_point]: " mount_point
        mount_point=${mount_point:-$default_mount_point}
        
        # Create mount point if it doesn't exist
        if [ ! -d "$mount_point" ]; then
            mkdir -p "$mount_point"
            print_success "Created mount point: $mount_point"
        fi
        
        # Samba mount options
        read -p "Auto mount at boot? (y/n) [y]: " AUTO_MOUNT
        AUTO_MOUNT=${AUTO_MOUNT:-y}
        
        if [[ $AUTO_MOUNT =~ ^[Yy]$ ]]; then
            MOUNT_OPTION="auto"
        else
            MOUNT_OPTION="noauto"
        fi
        
        # Generate fstab entry
        if [ -f "$CREDENTIALS_FILE" ]; then
            FSTAB_ENTRY="//$SERVER_IP/$share_name $mount_point cifs credentials=$CREDENTIALS_FILE,${MOUNT_OPTION},iocharset=utf8 0 0"
        else
            FSTAB_ENTRY="//$SERVER_IP/$share_name $mount_point cifs guest,${MOUNT_OPTION},iocharset=utf8 0 0"
        fi
        
        SMB_FSTAB_ENTRIES+=("$FSTAB_ENTRY")
        SMB_MOUNT_POINTS+=("$mount_point")
        
        echo "Fstab entry: $FSTAB_ENTRY"
        echo ""
    done
    
    return 0
}

# Function to update local fstab
update_local_fstab() {
    print_info "Preparing to update local /etc/fstab..."
    
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
    print_success "Backup created: /etc/fstab.backup.$(date +%Y%m%d%H%M%S)"
    
    # Add NFS entries if available
    if [ ${#NFS_FSTAB_ENTRIES[@]} -gt 0 ]; then
        echo "" >> /etc/fstab
        echo "# NFS mounts added by Raspberry Pi File Sharing Client Setup Script" >> /etc/fstab
        for entry in "${NFS_FSTAB_ENTRIES[@]}"; do
            echo "$entry" >> /etc/fstab
        done
        print_success "Added ${#NFS_FSTAB_ENTRIES[@]} NFS mount entries to fstab"
    fi
    
    # Add Samba entries if available
    if [ ${#SMB_FSTAB_ENTRIES[@]} -gt 0 ]; then
        echo "" >> /etc/fstab
        echo "# Samba mounts added by Raspberry Pi File Sharing Client Setup Script" >> /etc/fstab
        for entry in "${SMB_FSTAB_ENTRIES[@]}"; do
            echo "$entry" >> /etc/fstab
        done
        print_success "Added ${#SMB_FSTAB_ENTRIES[@]} Samba mount entries to fstab"
    fi
    
    print_info "Local /etc/fstab has been updated"
    echo "You may want to test the mounts with 'mount -a' command"
}

# Function to create a remote fstab file
create_remote_fstab() {
    print_info "Creating remote fstab file..."
    
    # Determine filename
    remote_file="remote_fstab_$(hostname)_$(date +%Y%m%d%H%M%S).txt"
    
    # Start with a header
    echo "# File sharing mounts from $(hostname) (generated $(date))" > "$remote_file"
    echo "# Copy and append these lines to your remote system's /etc/fstab" >> "$remote_file"
    echo "" >> "$remote_file"
    
    # Add NFS entries if available
    if [ ${#NFS_FSTAB_ENTRIES[@]} -gt 0 ]; then
        echo "# NFS mounts" >> "$remote_file"
        for entry in "${NFS_FSTAB_ENTRIES[@]}"; do
            echo "$entry" >> "$remote_file"
        done
    fi
    
    # Add Samba entries if available
    if [ ${#SMB_FSTAB_ENTRIES[@]} -gt 0 ]; then
        echo "" >> "$remote_file"
        echo "# Samba mounts" >> "$remote_file"
        for entry in "${SMB_FSTAB_ENTRIES[@]}"; do
            echo "$entry" >> "$remote_file"
        done
        
        # Add note about credentials if needed
        if [ -f "$CREDENTIALS_FILE" ]; then
            echo "" >> "$remote_file"
            echo "# Note: Create a credentials file on the remote system with:" >> "$remote_file"
            echo "# sudo mkdir -p /etc/samba" >> "$remote_file"
            echo "# sudo tee /etc/samba/credentials > /dev/null << EOF" >> "$remote_file"
            echo "# username=$SMB_USER" >> "$remote_file"
            echo "# password=$SMB_PASS" >> "$remote_file"
            echo "# EOF" >> "$remote_file"
            echo "# sudo chmod 600 /etc/samba/credentials" >> "$remote_file"
        fi
    fi
    
    print_success "Created remote fstab file: $remote_file"
    echo "You can transfer this file to your remote system and append its contents to /etc/fstab"
}

# Function to test mount entries
test_mount_entries() {
    print_info "Testing mount entries..."
    
    # Test NFS mounts if available
    if [ ${#NFS_MOUNT_POINTS[@]} -gt 0 ]; then
        for mount_point in "${NFS_MOUNT_POINTS[@]}"; do
            echo "Testing NFS mount: $mount_point"
            mount "$mount_point" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                print_success "Successfully mounted $mount_point"
                # List contents
                ls -la "$mount_point" | head -n 5
                # Unmount
                umount "$mount_point"
            else
                print_error "Failed to mount $mount_point"
            fi
            echo ""
        done
    fi
    
    # Test Samba mounts if available
    if [ ${#SMB_MOUNT_POINTS[@]} -gt 0 ]; then
        for mount_point in "${SMB_MOUNT_POINTS[@]}"; do
            echo "Testing Samba mount: $mount_point"
            mount "$mount_point" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                print_success "Successfully mounted $mount_point"
                # List contents
                ls -la "$mount_point" | head -n 5
                # Unmount
                umount "$mount_point"
            else
                print_error "Failed to mount $mount_point"
            fi
            echo ""
        done
    fi
}

# Function to parse local configuration files
parse_local_configs() {
    print_info "Parsing local configuration files..."
    
    # Parse /etc/fstab
    if [ -f /etc/fstab ]; then
        print_info "Current /etc/fstab entries related to NFS and Samba:"
        grep -E "(nfs|cifs)" /etc/fstab | sed 's/^/    /'
        echo ""
    fi
    
    # Parse /etc/exports
    if [ -f /etc/exports ]; then
        print_info "Current /etc/exports entries:"
        grep -v "^#" /etc/exports | grep -v "^$" | sed 's/^/    /'
        echo ""
    fi
    
    # Parse /etc/samba/smb.conf for shares
    if [ -f /etc/samba/smb.conf ]; then
        print_info "Current Samba shares defined in smb.conf:"
        grep -E "^\[.*\]" /etc/samba/smb.conf | grep -v "\[global\]" | sed 's/^/    /'
        echo ""
    fi
    
    # Parse /etc/nfs.conf if it exists
    if [ -f /etc/nfs.conf ]; then
        print_info "NFS configuration in /etc/nfs.conf:"
        grep -v "^#" /etc/nfs.conf | grep -v "^$" | head -n 10 | sed 's/^/    /'
        echo ""
    fi
}

# Main menu
main_menu() {
    clear
    echo "===== Raspberry Pi File Sharing Client Setup ====="
    echo "1. Analyze NFS exports on server"
    echo "2. Analyze Samba shares on server"
    echo "3. Generate and update local fstab entries"
    echo "4. Create remote fstab file"
    echo "5. Parse local configuration files"
    echo "6. Test mount entries"
    echo "7. Exit"
    echo ""
    read -p "Select an option: " OPTION
    
    case $OPTION in
        1)
            check_root
            detect_server_ip
            analyze_nfs_exports
            read -p "Press Enter to continue..."
            main_menu
            ;;
        2)
            check_root
            detect_server_ip
            analyze_samba_shares
            read -p "Press Enter to continue..."
            main_menu
            ;;
        3)
            check_root
            
            # Check if we have analyzed exports/shares
            if [ -z "$SERVER_IP" ]; then
                detect_server_ip
            fi
            
            if [ ${#NFS_EXPORT_PATHS[@]} -eq 0 ] && [ ${#SMB_SHARE_NAMES[@]} -eq 0 ]; then
                print_warning "No exports or shares analyzed yet"
                read -p "Analyze NFS exports? (y/n) [y]: " ANALYZE_NFS
                ANALYZE_NFS=${ANALYZE_NFS:-y}
                
                if [[ $ANALYZE_NFS =~ ^[Yy]$ ]]; then
                    analyze_nfs_exports
                fi
                
                read -p "Analyze Samba shares? (y/n) [y]: " ANALYZE_SMB
                ANALYZE_SMB=${ANALYZE_SMB:-y}
                
                if [[ $ANALYZE_SMB =~ ^[Yy]$ ]]; then
                    analyze_samba_shares
                fi
            fi
            
            # Generate fstab entries
            if [ ${#NFS_EXPORT_PATHS[@]} -gt 0 ]; then
                generate_nfs_fstab
            fi
            
            if [ ${#SMB_SHARE_NAMES[@]} -gt 0 ]; then
                generate_samba_fstab
            fi
            
            # Update fstab if we have entries
            if [ ${#NFS_FSTAB_ENTRIES[@]} -gt 0 ] || [ ${#SMB_FSTAB_ENTRIES[@]} -gt 0 ]; then
                read -p "Update local /etc/fstab with these entries? (y/n) [y]: " UPDATE_FSTAB
                UPDATE_FSTAB=${UPDATE_FSTAB:-y}
                
                if [[ $UPDATE_FSTAB =~ ^[Yy]$ ]]; then
                    update_local_fstab
                fi
            else
                print_error "No fstab entries to add"
            fi
            
            read -p "Press Enter to continue..."
            main_menu
            ;;
        4)
            check_root
            
            # Check if we have generated fstab entries
            if [ ${#NFS_FSTAB_ENTRIES[@]} -eq 0 ] && [ ${#SMB_FSTAB_ENTRIES[@]} -eq 0 ]; then
                print_warning "No fstab entries generated yet"
                
                # Check if we have analyzed exports/shares
                if [ -z "$SERVER_IP" ]; then
                    detect_server_ip
                fi
                
                if [ ${#NFS_EXPORT_PATHS[@]} -eq 0 ] && [ ${#SMB_SHARE_NAMES[@]} -eq 0 ]; then
                    read -p "Analyze NFS exports? (y/n) [y]: " ANALYZE_NFS
                    ANALYZE_NFS=${ANALYZE_NFS:-y}
                    
                    if [[ $ANALYZE_NFS =~ ^[Yy]$ ]]; then
                        analyze_nfs_exports
                    fi
                    
                    read -p "Analyze Samba shares? (y/n) [y]: " ANALYZE_SMB
                    ANALYZE_SMB=${ANALYZE_SMB:-y}
                    
                    if [[ $ANALYZE_SMB =~ ^[Yy]$ ]]; then
                        analyze_samba_shares
                    fi
                fi
                
                # Generate fstab entries
                if [ ${#NFS_EXPORT_PATHS[@]} -gt 0 ]; then
                    generate_nfs_fstab
                fi
                
                if [ ${#SMB_SHARE_NAMES[@]} -gt 0 ]; then
                    generate_samba_fstab
                fi
            fi
            
            # Create remote fstab file if we have entries
            if [ ${#NFS_FSTAB_ENTRIES[@]} -gt 0 ] || [ ${#SMB_FSTAB_ENTRIES[@]} -gt 0 ]; then
                create_remote_fstab
            else
                print_error "No fstab entries to create remote file"
            fi
            
            read -p "Press Enter to continue..."
            main_menu
            ;;
        5)
            check_root
            parse_local_configs
            read -p "Press Enter to continue..."
            main_menu
            ;;
        6)
            check_root
            
            # Check if we have generated fstab entries
            if [ ${#NFS_FSTAB_ENTRIES[@]} -eq 0 ] && [ ${#SMB_FSTAB_ENTRIES[@]} -eq 0 ]; then
                print_warning "No mount entries generated yet"
                main_menu
                return
            fi
            
            test_mount_entries
            read -p "Press Enter to continue..."
            main_menu
            ;;
        7)
            print_info "Exiting program"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            main_menu
            ;;
    esac
}

# Start the program
main_menu

exit 0

