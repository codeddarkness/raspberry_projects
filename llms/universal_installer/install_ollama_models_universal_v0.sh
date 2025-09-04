#!/bin/bash

# Universal Ollama Installation Script
# Supports Debian/Ubuntu Linux, macOS Intel, with CPU and GPU options
# Integrates with model library downloader

set -e

echo "=========================================="
echo "Universal Ollama Installation Script"
echo "=========================================="

# Detect OS
OS=""
ARCH=""
GPU_SUPPORT=""
RECOMMENDED_MODELS=()

case "$(uname -s)" in
    Linux*)
        OS="Linux"
        if [ -f /etc/debian_version ]; then
            DISTRO="Debian"
        elif [ -f /etc/redhat-release ]; then
            DISTRO="RedHat"
        else
            DISTRO="Unknown"
        fi
        ;;
    Darwin*)
        OS="macOS"
        ;;
    *)
        echo "Unsupported operating system: $(uname -s)"
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64|amd64)
        ARCH="x64"
        ;;
    arm64|aarch64)
        ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

echo "Detected: $OS ($ARCH)"

# Check system resources
check_system_resources() {
    if [ "$OS" = "Linux" ]; then
        TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
        AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
    elif [ "$OS" = "macOS" ]; then
        TOTAL_RAM=$(($(sysctl -n hw.memsize) / 1024 / 1024))
        AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
    fi
    
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    
    echo "System Resources:"
    echo "  RAM: ${TOTAL_RAM}MB"
    echo "  Available disk space: ${AVAILABLE_GB}GB"
    
    if [ $AVAILABLE_GB -lt 20 ]; then
        echo "Warning: Less than 20GB available. Large models may not fit."
    fi
}

# Detect GPU support
detect_gpu() {
    echo "Detecting GPU support..."
    
    if [ "$OS" = "Linux" ]; then
        # Check for NVIDIA GPU
        if command -v nvidia-smi &> /dev/null; then
            if nvidia-smi > /dev/null 2>&1; then
                GPU_SUPPORT="CUDA"
                echo "✓ NVIDIA GPU with CUDA detected"
            fi
        fi
        
        # Check for AMD GPU
        if [ -z "$GPU_SUPPORT" ] && command -v rocm-smi &> /dev/null; then
            if rocm-smi > /dev/null 2>&1; then
                GPU_SUPPORT="ROCm"
                echo "✓ AMD GPU with ROCm detected"
            fi
        fi
        
        # Check for Intel GPU
        if [ -z "$GPU_SUPPORT" ] && lspci | grep -i "intel.*graphics" > /dev/null; then
            echo "! Intel GPU detected (limited support)"
        fi
        
    elif [ "$OS" = "macOS" ]; then
        # macOS has Metal support
        GPU_SUPPORT="Metal"
        echo "✓ macOS Metal GPU support available"
    fi
    
    if [ -z "$GPU_SUPPORT" ]; then
        echo "! No GPU acceleration detected, using CPU only"
        GPU_SUPPORT="CPU"
    fi
}

# Install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    
    if [ "$OS" = "Linux" ]; then
        if [ "$DISTRO" = "Debian" ]; then
            sudo apt-get update
            sudo apt-get install -y curl wget jq html2text
        fi
    elif [ "$OS" = "macOS" ]; then
        if ! command -v brew &> /dev/null; then
            echo "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install jq html2text
    fi
}

# Install Ollama
install_ollama() {
    echo "Installing Ollama..."
    
    if ! command -v ollama &> /dev/null; then
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "Ollama already installed"
    fi
    
    # Configure Ollama for external access (Linux only)
    if [ "$OS" = "Linux" ]; then
        # Configure systemd service for external connections
        OLLAMA_CONFIG="/etc/systemd/system/ollama.service.d/override.conf"
        if [ ! -f "$OLLAMA_CONFIG" ]; then
            echo "Configuring Ollama for external connections..."
            sudo mkdir -p /etc/systemd/system/ollama.service.d/
            sudo tee $OLLAMA_CONFIG > /dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
        fi
        
        sudo systemctl daemon-reload
        sudo systemctl enable ollama
        sudo systemctl start ollama
    fi
    
    # Wait for service to be ready
    echo "Waiting for Ollama service to start..."
    sleep 5
    
    # Verify installation
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "✓ Ollama is running and accessible"
    else
        echo "! Ollama may not be fully ready yet"
    fi
}

# Download and parse model library
setup_model_library() {
    echo "Setting up model library..."
    
    # Create library directory
    mkdir -p ~/ollama-models/library
    cd ~/ollama-models/library
    
    # Download model library script if not exists
    if [ ! -f "get_model_list.sh" ]; then
        cat > get_model_list.sh << 'EOF'
#!/usr/bin/env bash

url=https://ollama.com/library
file_url=ollama_model_library
file_source=${file_url}.source
file_model_list=${file_url}.list
file_html=${file_url}.html
file_library_info=${file_url}.info

# write library url to file 
[[ ! -e ${file_url} ]] && { \
echo "${url}" > ${file_url} ; }

# download model library source
[[ ! -e ${file_source} ]] && { \
curl $(cat ${file_url}) > ${file_source} ; }

# parse models from source
[[ ! -e ${file_model_list} ]] && { \
grep '\/library\/' ${file_source} | cut -d'"' -f2 | cut -d'/' -f3 > ${file_model_list} ; }

# render source into text
[[ ! -e ${file_html} ]] && { \
html2text ${file_source} > ${file_html} ; }

# get description from source
paste <(
    grep -o 'title=.*.class\|text-md.*' ${file_source} | grep '^title' | cut -d'"' -f2 | sed 's/$/ :/g') <(
        grep -o 'title=.*.class\|text-md.*' ${file_source} | grep '^text' | sed 's/\<\/p\>$//g' | cut -d'>' -f2 ) > ${file_library_info}.tmp
column -s: -t ${file_library_info}.tmp | tee ${file_library_info}
rm -f ${file_library_info}.tmp
EOF
        chmod +x get_model_list.sh
    fi
    
    # Run the script to get latest models
    ./get_model_list.sh
    
    cd - > /dev/null
}

# Recommend models based on system capabilities
recommend_models() {
    echo "Analyzing system for model recommendations..."
    
    # Base recommendations on RAM and GPU
    if [ $TOTAL_RAM -ge 32000 ]; then
        # 32GB+ RAM - can handle large models
        RECOMMENDED_MODELS+=("llama3.1:70b" "qwen2.5:72b" "mixtral:8x7b")
    elif [ $TOTAL_RAM -ge 16000 ]; then
        # 16GB+ RAM - medium models
        RECOMMENDED_MODELS+=("llama3.1:8b" "qwen2.5:14b" "mistral:7b" "gemma2:9b")
    elif [ $TOTAL_RAM -ge 8000 ]; then
        # 8GB+ RAM - small-medium models
        RECOMMENDED_MODELS+=("llama3.1:3b" "qwen2.5:7b" "phi3:3.8b" "gemma2:2b")
    else
        # <8GB RAM - tiny models only
        RECOMMENDED_MODELS+=("phi3:mini" "gemma2:2b" "qwen2.5:1.5b")
    fi
    
    # Add GPU-specific recommendations
    if [ "$GPU_SUPPORT" != "CPU" ]; then
        echo "GPU acceleration available - larger models recommended"
        if [ $TOTAL_RAM -ge 16000 ]; then
            RECOMMENDED_MODELS+=("codellama:13b" "llava:13b")
        fi
    fi
}

# Interactive model installation
install_models() {
    echo "=========================================="
    echo "Model Installation"
    echo "=========================================="
    
    echo "Available model categories:"
    echo "1. Quick start (install recommended models)"
    echo "2. Browse all models"
    echo "3. Custom selection"
    echo "4. Skip model installation"
    
    read -p "Choose option (1-4): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            echo "Installing recommended models for your system..."
            for model in "${RECOMMENDED_MODELS[@]}"; do
                echo "Installing $model..."
                ollama pull "$model" || echo "Failed to install $model"
            done
            ;;
        2)
            if [ -f ~/ollama-models/library/ollama_model_library.list ]; then
                echo "Available models:"
                cat ~/ollama-models/library/ollama_model_library.list | head -20
                echo "... (showing first 20, see ~/ollama-models/library/ollama_model_library.list for full list)"
                echo ""
                while true; do
                    read -p "Enter model name to install (or 'done' to finish): " model_name
                    if [ "$model_name" = "done" ]; then
                        break
                    fi
                    if grep -q "^$model_name$" ~/ollama-models/library/ollama_model_library.list; then
                        ollama pull "$model_name"
                    else
                        echo "Model not found. Available models:"
                        grep -i "$model_name" ~/ollama-models/library/ollama_model_library.list || echo "No matches found"
                    fi
                done
            else
                echo "Model list not available. Installing recommended models..."
                for model in "${RECOMMENDED_MODELS[@]}"; do
                    ollama pull "$model"
                done
            fi
            ;;
        3)
            echo "Popular model categories:"
            echo "Code: codellama, codeqwen, starcoder2"
            echo "Chat: llama3.1, qwen2.5, mistral, gemma2"
            echo "Vision: llava, moondream, bakllava"
            echo "Specialized: nomic-embed-text, all-minilm"
            echo ""
            while true; do
                read -p "Enter model name to install (or 'done' to finish): " model_name
                if [ "$model_name" = "done" ]; then
                    break
                fi
                ollama pull "$model_name" || echo "Failed to install $model_name"
            done
            ;;
        *)
            echo "Skipping model installation"
            ;;
    esac
}

# Create GPU/CPU startup scripts
create_startup_scripts() {
    echo "Creating startup scripts..."
    
    # Create main launcher script
    cat > ~/ollama-launcher.sh << 'EOF'
#!/bin/bash

# Ollama Launcher Script
# Choose between CPU and GPU modes

show_usage() {
    echo "Usage: $0 [cpu|gpu|auto|status]"
    echo "  cpu    - Start with CPU only"
    echo "  gpu    - Start with GPU acceleration"
    echo "  auto   - Auto-detect best option"
    echo "  status - Show current status"
    echo "  models - List available models"
    echo "  install - Interactive model installer"
}

start_cpu() {
    echo "Starting Ollama in CPU mode..."
    export OLLAMA_NUM_GPU=0
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo systemctl restart ollama
    else
        ollama serve > /tmp/ollama.log 2>&1 &
    fi
}

start_gpu() {
    echo "Starting Ollama with GPU acceleration..."
    unset OLLAMA_NUM_GPU
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo systemctl restart ollama
    else
        ollama serve > /tmp/ollama.log 2>&1 &
    fi
}

show_status() {
    echo "Ollama Status:"
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "✓ Ollama is running"
        echo "Available models:"
        ollama list
    else
        echo "✗ Ollama is not running"
    fi
}

install_models() {
    if [ -f ~/ollama-models/library/ollama_model_library.list ]; then
        echo "Available models (first 20):"
        head -20 ~/ollama-models/library/ollama_model_library.list
        echo ""
        read -p "Enter model name to install: " model_name
        if [ ! -z "$model_name" ]; then
            ollama pull "$model_name"
        fi
    else
        echo "Model library not available. Popular models:"
        echo "llama3.1:8b, qwen2.5:7b, mistral:7b, gemma2:9b, codellama:7b"
        read -p "Enter model name to install: " model_name
        if [ ! -z "$model_name" ]; then
            ollama pull "$model_name"
        fi
    fi
}

case $1 in
    cpu)
        start_cpu
        ;;
    gpu)
        start_gpu
        ;;
    auto)
        # Auto-detect GPU support and start accordingly
        if command -v nvidia-smi &> /dev/null && nvidia-smi > /dev/null 2>&1; then
            start_gpu
        elif command -v rocm-smi &> /dev/null && rocm-smi > /dev/null 2>&1; then
            start_gpu
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            start_gpu  # macOS has Metal support
        else
            start_cpu
        fi
        ;;
    status)
        show_status
        ;;
    models)
        ollama list
        ;;
    install)
        install_models
        ;;
    *)
        show_usage
        ;;
esac
EOF
    
    chmod +x ~/ollama-launcher.sh
    
    # Create model management script
    cat > ~/ollama-models.sh << 'EOF'
#!/bin/bash

# Ollama Model Management Script

show_usage() {
    echo "Usage: $0 [list|search|install|remove|update-library]"
    echo "  list           - List installed models"
    echo "  search <term>  - Search available models"
    echo "  install <model> - Install a model"
    echo "  remove <model>  - Remove a model"
    echo "  update-library - Update model library from ollama.com"
}

update_library() {
    echo "Updating model library..."
    cd ~/ollama-models/library 2>/dev/null || {
        mkdir -p ~/ollama-models/library
        cd ~/ollama-models/library
    }
    
    rm -f ollama_model_library.*
    ./get_model_list.sh 2>/dev/null || {
        echo "Library update script not found. Please run the installation script first."
        exit 1
    }
    echo "Library updated!"
}

search_models() {
    if [ -f ~/ollama-models/library/ollama_model_library.list ]; then
        echo "Searching for: $1"
        grep -i "$1" ~/ollama-models/library/ollama_model_library.list || echo "No matches found"
    else
        echo "Model library not available. Run: $0 update-library"
    fi
}

case $1 in
    list)
        ollama list
        ;;
    search)
        if [ -z "$2" ]; then
            echo "Please provide a search term"
        else
            search_models "$2"
        fi
        ;;
    install)
        if [ -z "$2" ]; then
            echo "Please provide a model name"
        else
            ollama pull "$2"
        fi
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "Please provide a model name"
        else
            ollama rm "$2"
        fi
        ;;
    update-library)
        update_library
        ;;
    *)
        show_usage
        ;;
esac
EOF
    
    chmod +x ~/ollama-models.sh
}

# Main installation flow
main() {
    check_system_resources
    detect_gpu
    install_dependencies
    install_ollama
    setup_model_library
    recommend_models
    install_models
    create_startup_scripts
    
    echo "=========================================="
    echo "Installation Complete!"
    echo "=========================================="
    
    echo "System Configuration:"
    echo "  OS: $OS"
    echo "  Architecture: $ARCH"
    echo "  GPU Support: $GPU_SUPPORT"
    echo "  RAM: ${TOTAL_RAM}MB"
    echo ""
    
    echo "Usage:"
    echo "  Start Ollama: ~/ollama-launcher.sh auto"
    echo "  Manage models: ~/ollama-models.sh list"
    echo "  Test installation: ollama run gemma2:2b 'Hello, world!'"
    echo ""
    
    echo "Quick start examples:"
    if [ ${#RECOMMENDED_MODELS[@]} -gt 0 ]; then
        echo "  ollama run ${RECOMMENDED_MODELS[0]} 'Write a Python function to calculate fibonacci'"
    fi
    
    echo ""
    echo "Files created:"
    echo "  ~/ollama-launcher.sh - GPU/CPU startup control"
    echo "  ~/ollama-models.sh - Model management"
    echo "  ~/ollama-models/ - Model library and scripts"
}

# Run main installation
main "$@"
