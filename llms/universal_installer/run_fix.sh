cat << 'EOF' > fix_status_check.sh
#!/bin/bash

# Fix the status check function in master_llm_setup.sh
cp master_llm_setup.sh master_llm_setup.sh.backup

# Update the check_status function to properly detect management scripts
sed -i.tmp '/^check_status() {/,/^}$/{
    /Management Scripts:/,/^    done$/{
        s|local scripts=(|local scripts=(|
        s|"~/ollama-launcher.sh"|"$HOME/ollama-launcher.sh"|g
        s|"~/ollama-models.sh"|"$HOME/ollama-models.sh"|g
        s|"~/openwebui-manager.sh"|"$HOME/openwebui-manager.sh"|g
        s|"~/ollama-webui-verify.sh"|"$HOME/ollama-webui-verify.sh"|g
    }
}' master_llm_setup.sh

# Fix model library detection
sed -i.tmp2 '/Model Library:/,/^    fi$/{
    s|if \[ -f ~/ollama-models/library/ollama_model_library.list \];|if [ -f "$HOME/ollama-models/library/ollama_model_library.list" ];|
    s|local total_models=\$(wc -l < ~/ollama-models/library/ollama_model_library.list)|local total_models=$(wc -l < "$HOME/ollama-models/library/ollama_model_library.list")|
}' master_llm_setup.sh

# Clean up temp files
rm -f master_llm_setup.sh.tmp master_llm_setup.sh.tmp2

echo "✓ Fixed status check paths"
echo "Now run: bash master_llm_setup.sh status"
EOF

chmod +x fix_status_check.sh
bash fix_status_check.sh
rm fix_status_check.sh


cat << 'EOF' > fix_model_library.sh
#!/bin/bash

# Update model library path
if [ ! -f ~/ollama-models/library/ollama_model_library.list ] && [ -f ~/ollama-models/library/get_model_list.sh ]; then
    echo "Regenerating model library..."
    cd ~/ollama-models/library
    ./get_model_list.sh
    cd - > /dev/null
    echo "✓ Model library regenerated"
elif [ ! -d ~/ollama-models/library ]; then
    echo "Creating model library from existing data..."
    mkdir -p ~/ollama-models/library
    if [ -f ollama_model_library.list ]; then
        cp ollama_model_library.list ~/ollama-models/library/
    fi

    # Create the library update script
    cat << 'LIBRARY_EOF' > ~/ollama-models/library/get_model_list.sh
#!/usr/bin/env bash

url=https://ollama.com/library
file_url=ollama_model_library
file_source=${file_url}.source
file_model_list=${file_url}.list
file_html=${file_url}.html
file_library_info=${file_url}.info

echo "Downloading Ollama model library..."

# write library url to file
[[ ! -e ${file_url} ]] && { \
echo "${url}" > ${file_url} ; }

# download model library source
curl -s $(cat ${file_url}) > ${file_source}

# parse models from source
grep '\/library\/' ${file_source} | cut -d'"' -f2 | cut -d'/' -f3 | sort -u > ${file_model_list}

# render source into text
if command -v html2text &> /dev/null; then
    html2text ${file_source} > ${file_html}

    # get description from source
    paste <(
        grep -o 'title=.*.class\|text-md.*' ${file_source} | grep '^title' | cut -d'"' -f2 | sed 's/$/ :/g') <(
            grep -o 'title=.*.class\|text-md.*' ${file_source} | grep '^text' | sed 's/\<\/p\>$//g' | cut -d'>' -f2 ) > ${file_library_info}.tmp 2>/dev/null

    if [ -f ${file_library_info}.tmp ]; then
        column -s: -t ${file_library_info}.tmp > ${file_library_info} 2>/dev/null || cp ${file_library_info}.tmp ${file_library_info}
        rm -f ${file_library_info}.tmp
    fi
else
    echo "html2text not available - basic model list only"
fi

echo "Model library updated: $(wc -l < ${file_model_list}) models available"
LIBRARY_EOF

    chmod +x ~/ollama-models/library/get_model_list.sh
    cd ~/ollama-models/library
    ./get_model_list.sh
    cd - > /dev/null
    echo "✓ Model library created and updated"
fi
EOF

chmod +x fix_model_library.sh
bash fix_model_library.sh
rm fix_model_library.sh
