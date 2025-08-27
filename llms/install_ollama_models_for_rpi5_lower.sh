#!/bin/bash

# Install Missing LLM Models from Pi 5 Article
# Includes models that had issues or poor ratings

set -e

echo "=========================================="
echo "Installing Missing LLM Models"
echo "From It's FOSS Raspberry Pi 5 Article"
echo "=========================================="

# Check available disk space
AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
echo "Available disk space: ${AVAILABLE_GB}GB"

if [ $AVAILABLE_GB -lt 25 ]; then
    echo "Warning: Low disk space. These models need ~20GB total"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Current models installed:"
ollama list

echo ""
echo "Missing models from article (with their issues):"
echo "1. phi3.5:3.8b     - 2/5 stars (hallucination problems)"
echo "2. mistral:7b      - 3/5 stars (slow ~6min, works)"  
echo "3. llama2:7b       - Failed (insufficient RAM)"
echo "4. codellama:7b    - Failed (insufficient RAM)"
echo "5. orca-mini:3b    - 3/5 stars (decent performance)"
echo "6. codegemma:2b    - 1/5 star (responds with questions)"

echo ""
echo "=========================================="
echo "INSTALLATION OPTIONS"
echo "=========================================="

# Function to install model with warnings
install_model_with_warning() {
    local model=$1
    local size_gb=$2  
    local rating=$3
    local warning=$4
    
    echo ""
    echo "Model: $model"
    echo "Size: ~${size_gb}GB"
    echo "Rating: $rating"
    echo "Warning: $warning"
    echo ""
    
    read -p "Install $model? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing $model..."
        if ollama pull $model; then
            echo "$model installed successfully"
        else
            echo "Failed to install $model"
        fi
    else
        echo "Skipping $model"
    fi
    echo "---"
}

# Install problematic models with warnings
echo "Installing models with known issues:"

install_model_with_warning "phi3.5:3.8b" 4 "2/5" "Hallucination issues - generates infinite responses"

install_model_with_warning "orca-mini:3b" 3 "3/5" "Decent performance but accuracy needs verification" 

install_model_with_warning "codegemma:2b" 2 "1/5" "Responds with questions instead of answers"

echo ""
echo "Attempting larger models (may fail on 8GB Pi):"

install_model_with_warning "mistral:7b" 5 "3/5" "Slow (~6 minutes) but works if you have patience"

# Check available RAM before attempting 7B models
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ $TOTAL_RAM -lt 7500 ]; then
    echo ""
    echo "Warning: Only ${TOTAL_RAM}MB RAM detected"
    echo "The following 7B models will likely fail:"
    echo "- llama2:7b"  
    echo "- codellama:7b"
    echo ""
    read -p "Attempt anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping large 7B models"
        echo ""
        echo "Installation complete!"
        ollama list
        exit 0
    fi
fi

install_model_with_warning "llama2:7b" 4 "Failed" "Requires more than 8GB RAM - will likely fail"

install_model_with_warning "codellama:7b" 4 "Failed" "Requires more than 8GB RAM - will likely fail"

echo ""
echo "=========================================="
echo "INSTALLATION COMPLETE"
echo "=========================================="

echo "All available models:"
ollama list

echo ""
echo "Performance Summary (from article testing):"
echo "★★★★★ gemma2:2b     - Excellent (fast, accurate)"
echo "★★★★★ qwen2.5:3b    - Excellent (fast, accurate)" 
echo "★★★★  nemotron-mini:4b - Good (efficient, under 2min)"
echo "★★★   mistral:7b    - Decent (slow but works)"
echo "★★★   orca-mini:3b  - Decent (needs verification)"
echo "★★    phi3.5:3.8b   - Poor (hallucination issues)"
echo "★     codegemma:2b  - Poor (responds with questions)"
echo "-     llama2:7b     - Failed (insufficient RAM)"
echo "-     codellama:7b  - Failed (insufficient RAM)"

echo ""
echo "Testing suggestions:"
echo "1. Test phi3.5:3.8b with simple prompts (watch for infinite output)"
echo "2. Be patient with mistral:7b (6+ minute responses)"
echo "3. Use codegemma:2b only for code completion in IDE"
echo "4. Verify orca-mini:3b responses for accuracy"

# Create a test script for the problematic models
cat > ~/test-problematic-models.sh << 'EOF'
#!/bin/bash
echo "Testing Problematic Models"
echo "========================="

test_model() {
    local model=$1
    local warning=$2
    
    if ollama list | grep -q "$model"; then
        echo ""
        echo "Testing $model..."
        echo "Warning: $warning"
        echo "Prompt: 'Write a simple hello world in Python'"
        echo ""
        timeout 120 ollama run "$model" "Write a simple hello world in Python" || echo "Timeout or error occurred"
        echo ""
        echo "---"
    else
        echo "$model not installed"
    fi
}

test_model "phi3.5:3.8b" "May generate infinite output - use Ctrl+C if needed"
test_model "codegemma:2b" "May respond with questions instead of answers"
test_model "orca-mini:3b" "Check response accuracy"
test_model "mistral:7b" "Will be slow (~6 minutes)"
EOF

chmod +x ~/test-problematic-models.sh

echo ""
echo "Created test script: ~/test-problematic-models.sh"
echo "Use this to safely test the problematic models"

echo ""
echo "Memory usage monitoring:"
echo "  watch -n 1 free -m"
echo "  htop"
