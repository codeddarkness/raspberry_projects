#!/bin/bash

# Raspberry Pi 5 LLM Setup Script
# Based on testing from It's FOSS article on running LLMs on Pi 5
# Installs Ollama and recommended models that work well on Pi 5

set -e

echo "=========================================="
echo "Raspberry Pi 5 LLM Setup Script"
echo "=========================================="

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo "Warning: This script is designed for Raspberry Pi 5"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check available RAM
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ $TOTAL_RAM -lt 7500 ]; then
    echo "Warning: Less than 8GB RAM detected ($TOTAL_RAM MB)"
    echo "Some larger models may not work properly"
fi

# Check available disk space
AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
echo "Available disk space: ${AVAILABLE_GB}GB"

if [ $AVAILABLE_GB -lt 20 ]; then
    echo "Error: Insufficient disk space. Need at least 20GB free"
    exit 1
fi

echo "Installing Ollama..."

# Install Ollama
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama already installed"
fi

# Start ollama service
sudo systemctl enable ollama
sudo systemctl start ollama

# Wait for service to be ready
echo "Waiting for Ollama service to start..."
sleep 5

echo "=========================================="
echo "Installing recommended models..."
echo "=========================================="

# Function to install model with size check
install_model() {
    local model=$1
    local size_gb=$2
    local rating=$3
    local description=$4
    
    echo "Installing $model (${size_gb}GB, ${rating} rating)"
    echo "Description: $description"
    
    if [ $AVAILABLE_GB -lt $size_gb ]; then
        echo "Skipping $model - insufficient disk space"
        return
    fi
    
    read -p "Install $model? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Skipping $model"
        return
    fi
    
    ollama pull $model
    echo "$model installed successfully"
    echo "---"
}

# Install top-rated models (5 stars)
echo "=== TOP PERFORMERS (5-star models) ==="
install_model "gemma2:2b" 2 "5/5" "Google's Gemma 2, excellent performance, fast inference, 3GB RAM usage"
install_model "qwen2.5:3b" 3 "5/5" "Alibaba's Qwen 2.5, impressive speed and accuracy, 5.4GB RAM usage"

echo "=== GOOD PERFORMERS (4-star models) ==="
install_model "nemotron-mini:4b" 4 "4/5" "NVIDIA's Nemotron Mini, efficient and fast, 4GB RAM usage"

echo "=== DECENT PERFORMERS (3-star models) ==="
read -p "Install 3-star models (slower but functional)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    install_model "mistral:7b" 5 "3/5" "Mistral 7B, slow (~6 min) but correct responses, 5GB RAM usage"
    install_model "orca-mini:3b" 3 "3/5" "Orca Mini, decent performance, 4.5GB RAM usage"
fi

echo "=========================================="
echo "Installation complete!"
echo "=========================================="

echo "Installed models:"
ollama list

echo ""
echo "Usage examples:"
echo "  ollama run gemma2:2b"
echo "  ollama run qwen2.5:3b"
echo "  ollama run nemotron-mini:4b"

echo ""
echo "To test a model, try:"
echo "  ollama run gemma2:2b 'Generate a Docker Compose file for WordPress with MySQL database'"

echo ""
echo "Notes:"
echo "- Models under 7B parameters work best on Pi 5"
echo "- Gemma2:2b and Qwen2.5:3b are the top performers"
echo "- Avoid Phi3.5 (hallucination issues) and 7B+ models (RAM constraints)"
echo "- Monitor RAM usage with: watch -n 1 free -m"

echo ""
echo "To uninstall a model: ollama rm <model_name>"
echo "To stop ollama service: sudo systemctl stop ollama"

# Create a simple test script
cat > ~/test_llm.sh << 'EOF'
#!/bin/bash
echo "Testing LLM models..."
echo "Available models:"
ollama list

echo ""
echo "Testing Gemma2:2b (if installed):"
if ollama list | grep -q "gemma2:2b"; then
    echo "Generating Docker Compose example..."
    ollama run gemma2:2b "Create a simple Docker Compose file for WordPress with MySQL. Keep it brief."
else
    echo "Gemma2:2b not installed"
fi
EOF

chmod +x ~/test_llm.sh
echo ""
echo "Created test script: ~/test_llm.sh"
echo "Run it with: ./test_llm.sh"
