#!/bin/bash
## CLAUDE OPTION
# Raspberry Pi File Sharing Setup Script
# This script helps set up NFS or Samba file sharing on a Raspberry Pi

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

# Function to update system
update_system() {
    print_info "Updating system packages..."
    apt update
    apt upgrade -y
    print_success "System updated successfully"
}

# Function to get user details
get_user_details() {
    DEFAULT_USER=$(who am i | awk '{print $1}')
    
    echo ""
    read -p "Enter username for share permissions [$DEFAULT_USER]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USER}
    
    # Get user ID and group ID
    if id "$USERNAME" &>/dev/null; then
        USER_ID=$(id -u "$USERNAME")
        GROUP_ID=$(id -g "$USERNAME")
        print_info "Using user: $USERNAME (UID: $USER_ID, GID: $GROUP_ID)"
    else
        print_error "User $USERNAME does not exist"
        exit 1
    fi
}

# Function to get and validate directory
get_directory() {
    echo ""
    read -p "Enter directory to share: " SHARE_DIR
    
    # Validate directory
    if [ -z "$SHARE_DIR" ]; then
        print_error "Directory cannot be empty"
        get_directory
        return
    fi
    
    # Create directory if it doesn't exist
    if [ ! -d "$SHARE_DIR" ]; then
        print_warning "Directory $SHARE_DIR does not exist"
        read -p "Do you want to create it? (y/n): " CREATE_DIR
        if [[ $CREATE_DIR =~ ^[Yy]$ ]]; then
            mkdir -p "$SHARE_DIR"
            print_success "Directory $SHARE_DIR created"
        else
            print_error "Directory is required for sharing"
            get_directory
            return
        fi
    fi
    
    # Set appropriate permissions
    chown -R "$USERNAME:$USERNAME" "$SHARE_DIR"
    find "$SHARE_DIR" -type d -exec chmod 755 {} \;
    find "$SHARE_DIR" -type f -exec chmod 644 {} \;
    print_success "Permissions set for $SHARE_DIR"
}

# Function to set up NFS share
setup_nfs() {
    print_info "Setting up NFS share..."
    
    # Install NFS server
    apt install nfs-kernel-server -y
    
    # Get IP address information
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    # Configure exports
    echo ""
    echo "NFS Access Configuration:"
    echo "1. Allow access to everyone (*)"
    echo "2. Allow access to specific IP or subnet"
    read -p "Select option [1]: " NFS_ACCESS
    NFS_ACCESS=${NFS_ACCESS:-1}
    
    if [ "$NFS_ACCESS" -eq 1 ]; then
        IP_CONFIG="*"
    else
        read -p "Enter IP address or subnet (e.g., 192.168.1.0/24): " IP_CONFIG
    fi
    
    # Configure NFS options
    echo ""
    read -p "Allow write access? (y/n) [y]: " ALLOW_WRITE
    ALLOW_WRITE=${ALLOW_WRITE:-y}
    
    if [[ $ALLOW_WRITE =~ ^[Yy]$ ]]; then
        RW_OPTION="rw"
    else
        RW_OPTION="ro"
    fi
    
    # Create export entry
    EXPORT_ENTRY="$SHARE_DIR $IP_CONFIG($RW_OPTION,all_squash,insecure,async,no_subtree_check,anonuid=$USER_ID,anongid=$GROUP_ID)"
    
    # Check if entry already exists and add if it doesn't
    if grep -q "^$SHARE_DIR " /etc/exports; then
        # Backup exports file
        cp /etc/exports /etc/exports.bak
        # Remove existing entry
        sed -i "\|^$SHARE_DIR |d" /etc/exports
    fi
    
    # Add new entry
    echo "$EXPORT_ENTRY" >> /etc/exports
    
    # Apply changes
    exportfs -ra
    systemctl restart nfs-kernel-server
    
    print_success "NFS share setup completed"
    print_info "You can access your NFS share at: $LOCAL_IP:$SHARE_DIR"
    echo "On Linux clients, mount with: sudo mount $LOCAL_IP:$SHARE_DIR /mount/point"
    echo "On Windows, you'll need to enable NFS client and use: mount -o anon $LOCAL_IP:$SHARE_DIR Z:"
    echo "On macOS, use: mount -t nfs -o resvport $LOCAL_IP:$SHARE_DIR /mount/point"
}

# Function to set up Samba share
setup_samba() {
    print_info "Setting up Samba share..."
    
    # Install Samba
    apt install samba samba-common-bin -y
    
    # Get share name
    echo ""
    DEFAULT_SHARE_NAME=$(basename "$SHARE_DIR")
    read -p "Enter share name [$DEFAULT_SHARE_NAME]: " SHARE_NAME
    SHARE_NAME=${SHARE_NAME:-$DEFAULT_SHARE_NAME}
    
    # Configure share options
    echo ""
    read -p "Make share writeable? (y/n) [y]: " ALLOW_WRITE
    ALLOW_WRITE=${ALLOW_WRITE:-y}
    
    if [[ $ALLOW_WRITE =~ ^[Yy]$ ]]; then
        WRITE_OPTION="yes"
    else
        WRITE_OPTION="no"
    fi
    
    read -p "Make share browseable? (y/n) [y]: " ALLOW_BROWSE
    ALLOW_BROWSE=${ALLOW_BROWSE:-y}
    
    if [[ $ALLOW_BROWSE =~ ^[Yy]$ ]]; then
        BROWSE_OPTION="yes"
    else
        BROWSE_OPTION="no"
    fi
    
    read -p "Make share public (no password)? (y/n) [n]: " MAKE_PUBLIC
    MAKE_PUBLIC=${MAKE_PUBLIC:-n}
    
    if [[ $MAKE_PUBLIC =~ ^[Yy]$ ]]; then
        PUBLIC_OPTION="yes"
        GUEST_OPTION="yes"
    else
        PUBLIC_OPTION="no"
        GUEST_OPTION="no"
    fi
    
    # Create Samba configuration
    SMB_CONFIG="[$SHARE_NAME]
    path = $SHARE_DIR
    writeable = $WRITE_OPTION
    browseable = $BROWSE_OPTION
    public = $PUBLIC_OPTION
    guest ok = $GUEST_OPTION
    create mask = 0644
    directory mask = 0755
    force user = $USERNAME"
    
    # Check if share already exists
    if grep -q "^\[$SHARE_NAME\]" /etc/samba/smb.conf; then
        # Backup config file
        cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
        # Remove existing share
        sed -i "/^\[$SHARE_NAME\]/,/^$/d" /etc/samba/smb.conf
    fi
    
    # Add new share
    echo "$SMB_CONFIG" >> /etc/samba/smb.conf
    
    # Set up user if not public
    if [[ $MAKE_PUBLIC =~ ^[Nn]$ ]]; then
        echo ""
        print_info "Setting up Samba password for user $USERNAME"
        smbpasswd -a "$USERNAME"
    fi
    
    # Restart Samba
    systemctl restart smbd
    
    # Get IP address
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    print_success "Samba share setup completed"
    print_info "You can access your Samba share at: \\\\$LOCAL_IP\\$SHARE_NAME"
    echo "On Linux: smb://$LOCAL_IP/$SHARE_NAME"
    echo "On macOS: smb://$LOCAL_IP/$SHARE_NAME"
    echo "On Windows: \\\\$LOCAL_IP\\$SHARE_NAME"
}

# Function to import from template
import_from_template() {
    echo ""
    echo "Select a template to import:"
    echo "1. NFS - Media Server (optimized for media streaming)"
    echo "2. NFS - Home Directories (secure personal directories)"
    echo "3. Samba - Media Share (optimized for media access)"
    echo "4. Samba - Document Share (optimized for office documents)"
    read -p "Select template [1]: " TEMPLATE
    TEMPLATE=${TEMPLATE:-1}
    
    case $TEMPLATE in
        1)
            SHARE_DIR="/mnt/media"
            mkdir -p "$SHARE_DIR"
            # Media server NFS template with optimized settings
            EXPORT_ENTRY="$SHARE_DIR *(rw,all_squash,insecure,async,no_subtree_check,anonuid=$USER_ID,anongid=$GROUP_ID)"
            print_info "Imported NFS Media Server template for $SHARE_DIR"
            ;;
        2)
            SHARE_DIR="/home/shares"
            mkdir -p "$SHARE_DIR"
            # Home directories NFS template with more secure settings
            EXPORT_ENTRY="$SHARE_DIR 192.168.0.0/24(rw,all_squash,secure,sync,no_subtree_check,anonuid=$USER_ID,anongid=$GROUP_ID)"
            print_info "Imported NFS Home Directories template for $SHARE_DIR"
            ;;
        3)
            SHARE_DIR="/mnt/media"
            mkdir -p "$SHARE_DIR"
            # Media Samba share template
            SHARE_NAME="media"
            SMB_CONFIG="[$SHARE_NAME]
    path = $SHARE_DIR
    writeable = yes
    browseable = yes
    public = yes
    guest ok = yes
    create mask = 0644
    directory mask = 0755
    force user = $USERNAME"
            print_info "Imported Samba Media Share template for $SHARE_DIR"
            ;;
        4)
            SHARE_DIR="/home/documents"
            mkdir -p "$SHARE_DIR"
            # Document Samba share template
            SHARE_NAME="documents"
            SMB_CONFIG="[$SHARE_NAME]
    path = $SHARE_DIR
    writeable = yes
    browseable = yes
    public = no
    guest ok = no
    create mask = 0644
    directory mask = 0755
    force user = $USERNAME
    veto files = /.exe/.com/.dll/"
            print_info "Imported Samba Document Share template for $SHARE_DIR"
            ;;
        *)
            print_error "Invalid template selection"
            import_from_template
            return
            ;;
    esac
    
    # Set appropriate permissions
    chown -R "$USERNAME:$USERNAME" "$SHARE_DIR"
    find "$SHARE_DIR" -type d -exec chmod 755 {} \;
    find "$SHARE_DIR" -type f -exec chmod 644 {} \;
    print_success "Permissions set for $SHARE_DIR"
}

# Main menu
main_menu() {
    clear
    echo "===== Raspberry Pi File Sharing Setup ====="
    echo "1. Set up NFS Share"
    echo "2. Set up Samba Share"
    echo "3. Exit"
    echo ""
    read -p "Select an option: " OPTION
    
    case $OPTION in
        1)
            check_root
            update_system
            get_user_details
            
            echo ""
            echo "Directory Setup:"
            echo "1. Enter custom directory"
            echo "2. Import from template"
            read -p "Select option [1]: " DIR_OPTION
            DIR_OPTION=${DIR_OPTION:-1}
            
            if [ "$DIR_OPTION" -eq 1 ]; then
                get_directory
            else
                import_from_template
                # If using template, determine if it's NFS
                if [[ $TEMPLATE -eq 1 || $TEMPLATE -eq 2 ]]; then
                    setup_nfs
                else
                    print_error "Template not compatible with NFS. Please select an NFS template."
                    main_menu
                fi
                return
            fi
            
            setup_nfs
            ;;
        2)
            check_root
            update_system
            get_user_details
            
            echo ""
            echo "Directory Setup:"
            echo "1. Enter custom directory"
            echo "2. Import from template"
            read -p "Select option [1]: " DIR_OPTION
            DIR_OPTION=${DIR_OPTION:-1}
            
            if [ "$DIR_OPTION" -eq 1 ]; then
                get_directory
            else
                import_from_template
                # If using template, determine if it's Samba
                if [[ $TEMPLATE -eq 3 || $TEMPLATE -eq 4 ]]; then
                    setup_samba
                else
                    print_error "Template not compatible with Samba. Please select a Samba template."
                    main_menu
                fi
                return
            fi
            
            setup_samba
            ;;
        3)
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
