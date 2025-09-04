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
