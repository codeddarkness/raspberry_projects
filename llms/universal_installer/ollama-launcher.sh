#!/bin/bash

# Ollama Launcher Script
# Choose between CPU and GPU modes

show_usage() {
    echo "Usage: $0 [cpu|gpu|auto|status|models|install]"
    echo "  cpu     - Start with CPU only"
    echo "  gpu     - Start with GPU acceleration"
    echo "  auto    - Auto-detect best option"
    echo "  status  - Show current status"
    echo "  models  - List available models"
    echo "  install - Interactive model installer"
}

start_cpu() {
    echo "Starting Ollama in CPU mode..."
    export OLLAMA_NUM_GPU=0
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if systemctl is-enabled ollama &> /dev/null; then
            sudo systemctl restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    else
        # macOS
        if command -v brew &> /dev/null && brew services list | grep -q ollama; then
            brew services restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    fi
}

start_gpu() {
    echo "Starting Ollama with GPU acceleration..."
    unset OLLAMA_NUM_GPU
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if systemctl is-enabled ollama &> /dev/null; then
            sudo systemctl restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    else
        # macOS
        if command -v brew &> /dev/null && brew services list | grep -q ollama; then
            brew services restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
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
        echo "Try: brew services start ollama"
        echo "Or: ollama serve"
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
