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
    
    if [ -f get_model_list.sh ]; then
        rm -f ollama_model_library.*
        ./get_model_list.sh
        echo "Library updated!"
    else
        echo "Library update script not found. Please run the installation script first."
        exit 1
    fi
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
