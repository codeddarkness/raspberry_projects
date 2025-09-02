#!/usr/bin/env bash

url=https://ollama.com/library
file_url=ollama_model_library
file_source=${file_url}.source
file_model_list=../${file_url}.list
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
#grep 'DBRX is an open, general-purpose LLM created by Databricks.' ${file_source}
#          <p class="max-w-lg break-words text-neutral-800 text-md">DBRX is an open, general-purpose LLM created by Databricks.</p>
paste <(
    grep -o 'title=.*.class\|text-md.*' ${file_source} | grep '^title' | cut -d'"' -f2 | sed 's/$/ :/g') <(
        grep -o 'title=.*.class\|text-md.*' ${file_source} | grep '^text' | sed 's/\<\/p\>$//g' | cut -d'>' -f2 ) > ${file_library_info}.tmp
column -s: -t 2 ${file_library_info}.tmp | tee ${file_library_info}
