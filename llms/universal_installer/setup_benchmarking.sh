cat << 'EOF' > setup_model_benchmarking.sh
#!/bin/bash

echo "Setting up model benchmarking tool..."

# Create the main benchmarking script
cat << 'BENCHMARK_EOF' > ~/llm-benchmark.sh
#!/bin/bash
# LLM Model Benchmarking Tool
# Adapted for Universal LLM Setup

set -e

BENCHMARK_DIR="benchmark_results"
PROMPTS_FILE="benchmark_prompts.txt"
AGGREGATED_RESULTS="benchmark_summary.txt"
SUCCESSFUL_MODELS="benchmark_successful_models.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Animation variables
ANIMATION_PID=""

show_progress_animation() {
    local message="$1"
    local color="$2"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    while true; do
        printf "\r${color}${message} ${chars:$i:1}${RESET}"
        i=$(( (i + 1) % ${#chars} ))
        sleep 0.1
    done
}

stop_animation() {
    if [ -n "${ANIMATION_PID}" ]; then
        kill "${ANIMATION_PID}" 2>/dev/null
        wait "${ANIMATION_PID}" 2>/dev/null
        ANIMATION_PID=""
        printf "\r\033[K"
        sleep 0.1
    fi
}

format_time() {
    local seconds="$1"
    
    if [ -z "${seconds}" ] || [ "${seconds}" = "ERROR" ] || [ "${seconds}" = "0" ]; then
        echo "ERROR"
        return
    fi
    
    local time_int
    time_int=$(echo "${seconds}" | awk '{printf "%.0f", $1}')
    
    if [ "${time_int}" -lt 60 ]; then
        printf "%.2fs" "${seconds}"
    elif [ "${time_int}" -lt 3600 ]; then
        local minutes=$((time_int / 60))
        local remaining_seconds=$((time_int % 60))
        printf "%dm:%02ds" "${minutes}" "${remaining_seconds}"
    else
        local hours=$((time_int / 3600))
        local minutes=$(((time_int % 3600) / 60))
        local remaining_seconds=$((time_int % 60))
        printf "%dh:%02dm:%02ds" "${hours}" "${minutes}" "${remaining_seconds}"
    fi
}

test_model() {
    local model="$1"
    local prompt="$2"
    local timeout_seconds="${3:-300}"
    
    # Start progress animation
    show_progress_animation "[${model}] Processing" "${CYAN}" &
    ANIMATION_PID=$!
    
    # Record start time
    local start_time=$(date +%s%N)
    
    # Create JSON payload
    local json_payload
    json_payload=$(jq -n \
        --arg model "$model" \
        --arg content "$prompt" \
        '{
            model: $model,
            messages: [{role: "user", content: $content}],
            stream: false
        }')
    
    # Make API call with timeout
    local response
    response=$(timeout "${timeout_seconds}" curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>/dev/null)
    local curl_exit_code=$?
    
    # Calculate processing time
    local end_time=$(date +%s%N)
    local processing_time
    processing_time=$(awk "BEGIN {printf \"%.2f\", (${end_time} - ${start_time}) / 1000000000}")
    
    # Stop animation
    stop_animation
    
    # Check for timeout
    if [ ${curl_exit_code} -eq 124 ]; then
        echo "TIMEOUT"
        return 1
    fi
    
    # Check for curl errors
    if [ ${curl_exit_code} -ne 0 ]; then
        echo "ERROR"
        return 1
    fi
    
    # Check response for errors
    local error_msg
    error_msg=$(echo "${response}" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "${error_msg}" ] && [ "${error_msg}" != "null" ]; then
        echo "ERROR"
        return 1
    fi
    
    # Extract response content
    local result
    result=$(echo "${response}" | jq -r '.message.content // empty' 2>/dev/null)
    
    if [ -z "${result}" ] || [ "${result}" = "null" ]; then
        echo "ERROR"
        return 1
    fi
    
    echo "${processing_time}|${result}"
    return 0
}

run_single_benchmark() {
    local prompt="$1"
    local timestamp
    timestamp=$(date +"%Y_%m_%d_%H%M%S")
    local benchmark_file="${BENCHMARK_DIR}/${timestamp}_benchmark.log"
    
    # Get available models
    local available_models=($(ollama list 2>/dev/null | grep -v NAME | awk '{print $1}'))
    
    if [ ${#available_models[@]} -eq 0 ]; then
        echo -e "${RED}Error: No models available${RESET}"
        return 1
    fi
    
    echo -e "${BOLD}=== Running Benchmark Test ===${RESET}"
    echo "Prompt: ${prompt}"
    echo "Testing ${#available_models[@]} models..."
    echo ""
    
    # Create benchmark log header
    mkdir -p "${BENCHMARK_DIR}"
    {
        echo "=== Benchmark Results - $(date +"%Y-%m-%d %H:%M:%S") ==="
        echo "Prompt: ${prompt}"
        echo ""
    } > "${benchmark_file}"
    
    # Store results for ranking
    declare -A results
    declare -A times
    
    local model_count=0
    for model in "${available_models[@]}"; do
        model_count=$((model_count + 1))
        local current_time
        current_time=$(date +"%H:%M:%S")
        echo -e "[${current_time}] Testing ${BOLD}${model}${RESET} (${model_count}/${#available_models[@]})..."
        
        # Test the model
        local test_result
        test_result=$(test_model "${model}" "${prompt}")
        local exit_code=$?
        
        if [ ${exit_code} -eq 0 ] && [[ "${test_result}" == *"|"* ]]; then
            local processing_time="${test_result%%|*}"
            local response="${test_result#*|}"
            local formatted_time
            formatted_time=$(format_time "${processing_time}")
            
            echo -e "  ${GREEN}✓ Success${RESET} - ${formatted_time}"
            
            results["${model}"]="✓"
            times["${model}"]="${formatted_time}"
            
            # Log to file
            {
                echo "Model: ${model}"
                echo "Result: ✓ Success"
                echo "Processing Time: ${formatted_time}"
                echo "Response Length: ${#response} characters"
                echo "Response:"
                echo "${response}"
                echo ""
                echo "----------------------------------------"
                echo ""
            } >> "${benchmark_file}"
        else
            echo -e "  ${RED}✗ Failed${RESET} - ${test_result}"
            
            results["${model}"]="✗"
            times["${model}"]="${test_result}"
            
            {
                echo "Model: ${model}"
                echo "Result: ✗ Failed"
                echo "Processing Time: ${test_result}"
                echo "Response: Failed to generate response"
                echo ""
                echo "----------------------------------------"
                echo ""
            } >> "${benchmark_file}"
        fi
        
        sleep 1
    done
    
    # Show rankings
    echo ""
    echo -e "${BOLD}=== Results Summary ===${RESET}"
    printf "%-5s %-25s %-15s %s\n" "Rank" "Model" "Time" "Status"
    printf "%-5s %-25s %-15s %s\n" "----" "-----" "----" "------"
    
    # Create sorted list of successful models
    local successful_models=()
    local temp_file=$(mktemp)
    
    for model in "${!results[@]}"; do
        local status="${results[$model]}"
        local time_str="${times[$model]}"
        
        if [ "${status}" = "✓" ]; then
            successful_models+=("${model}")
            # Convert time to seconds for sorting
            local sort_key="9999999999"
            if [[ "${time_str}" =~ ^([0-9]+)\.([0-9]+)s$ ]]; then
                sort_key=$(printf "%010.2f" "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}")
            elif [[ "${time_str}" =~ ^([0-9]+)m:([0-9]+)s$ ]]; then
                local minutes=$((10#${BASH_REMATCH[1]}))
                local seconds=$((10#${BASH_REMATCH[2]}))
                local total_seconds=$((minutes * 60 + seconds))
                sort_key=$(printf "%010d" "${total_seconds}")
            fi
            echo "${sort_key}|${model}|${time_str}|${status}" >> "${temp_file}"
        else
            echo "9999999999|${model}|ERROR|${status}" >> "${temp_file}"
        fi
    done
    
    # Display sorted results
    local rank=1
    while IFS='|' read -r sort_key model time_str status; do
        if [ "${status}" = "✓" ]; then
            printf "%-5d %-25s %-15s %s\n" "${rank}" "${model}" "${time_str}" "${status}"
            rank=$((rank + 1))
        else
            printf "%-5s %-25s %-15s %s\n" "---" "${model}" "ERROR" "${status}"
        fi
    done < <(sort -n "${temp_file}")
    
    rm -f "${temp_file}"
    
    echo ""
    echo "Results saved to: ${benchmark_file}"
    
    # Save successful models
    if [ ${#successful_models[@]} -gt 0 ]; then
        printf '%s\n' "${successful_models[@]}" > "${SUCCESSFUL_MODELS}"
        echo "Successful models saved to: ${SUCCESSFUL_MODELS}"
    fi
    
    return 0
}

run_batch_benchmark() {
    if [ ! -f "${PROMPTS_FILE}" ]; then
        echo -e "${RED}Error: Prompts file not found: ${PROMPTS_FILE}${RESET}"
        return 1
    fi
    
    local total_prompts
    total_prompts=$(wc -l < "${PROMPTS_FILE}")
    echo -e "${BOLD}=== Running Batch Benchmark ===${RESET}"
    echo "Total prompts: ${total_prompts}"
    echo ""
    
    local prompt_count=0
    while IFS= read -r prompt; do
        prompt_count=$((prompt_count + 1))
        echo -e "${CYAN}=== PROMPT ${prompt_count}/${total_prompts} ===${RESET}"
        echo -e "${YELLOW}${prompt}${RESET}"
        echo ""
        
        run_single_benchmark "${prompt}"
        
        if [ ${prompt_count} -lt ${total_prompts} ]; then
            echo ""
            echo "Waiting 3 seconds before next prompt..."
            sleep 3
        fi
    done < "${PROMPTS_FILE}"
    
    echo -e "${GREEN}Batch benchmark complete!${RESET}"
}

create_sample_prompts() {
    cat << 'PROMPTS_EOF' > "${PROMPTS_FILE}"
Explain quantum computing in simple terms
Write a Python function to sort a list
What are the benefits of renewable energy?
Describe the process of photosynthesis
How does machine learning work?
What is the difference between TCP and UDP?
Explain the concept of blockchain technology
Write a haiku about autumn
What causes climate change?
Describe how to make bread from scratch
PROMPTS_EOF
    
    echo "Sample prompts created in: ${PROMPTS_FILE}"
}

aggregate_results() {
    echo -e "${BOLD}=== Aggregating Results ===${RESET}"
    
    if [ ! -d "${BENCHMARK_DIR}" ]; then
        echo -e "${RED}No benchmark results found${RESET}"
        return 1
    fi
    
    local log_files=($(find "${BENCHMARK_DIR}" -name "*_benchmark.log" -type f | sort))
    
    if [ ${#log_files[@]} -eq 0 ]; then
        echo -e "${RED}No benchmark log files found${RESET}"
        return 1
    fi
    
    echo "Processing ${#log_files[@]} benchmark files..."
    
    declare -A model_success_count
    declare -A model_total_count
    declare -A model_total_time
    declare -A model_min_time
    declare -A model_max_time
    
    # Process log files
    for log_file in "${log_files[@]}"; do
        echo "Processing: $(basename "${log_file}")"
        
        while IFS= read -r line; do
            if [[ "${line}" =~ ^Model:\ (.+)$ ]]; then
                local model="${BASH_REMATCH[1]}"
                model_total_count["${model}"]=$((${model_total_count["${model}"]} + 1))
                
                local result_line
                local time_line
                read -r result_line
                read -r time_line
                
                if [[ "${result_line}" =~ ✓ ]] && [[ "${time_line}" =~ ^Processing\ Time:\ (.+)$ ]]; then
                    local processing_time="${BASH_REMATCH[1]}"
                    
                    if [ "${processing_time}" != "ERROR" ] && [ "${processing_time}" != "TIMEOUT" ]; then
                        model_success_count["${model}"]=$((${model_success_count["${model}"]} + 1))
                        # Additional time processing would go here
                    fi
                fi
            fi
        done < "${log_file}"
    done
    
    # Generate summary
    {
        echo "=== AGGREGATED BENCHMARK RESULTS ==="
        echo "Generated: $(date +"%Y-%m-%d %H:%M:%S")"
        echo ""
        echo "=== MODEL PERFORMANCE SUMMARY ==="
        printf "%-25s %-12s %-10s\n" "Model" "Success Rate" "Tests"
        printf "%-25s %-12s %-10s\n" "-----" "------------" "-----"
        
        for model in "${!model_total_count[@]}"; do
            local success_count=${model_success_count["${model}"]:-0}
            local total_count=${model_total_count["${model}"]:-0}
            local success_rate="0.0"
            
            if [ "${total_count}" -gt 0 ]; then
                success_rate=$(awk "BEGIN {printf \"%.1f\", ${success_count} * 100 / ${total_count}}")
            fi
            
            printf "%-25s %-12s %-10s\n" "${model}" "${success_rate}%" "${success_count}/${total_count}"
        done
        
    } | tee "${AGGREGATED_RESULTS}"
    
    echo ""
    echo "Aggregated results saved to: ${AGGREGATED_RESULTS}"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  benchmark \"prompt\"    Run single benchmark with given prompt"
    echo "  batch                 Run batch benchmark using prompts file"
    echo "  aggregate             Aggregate existing benchmark results"
    echo "  create-prompts        Create sample prompts file"
    echo "  clean                 Clean old benchmark files"
    echo "  help                  Show this help"
    echo ""
    echo "Files:"
    echo "  ${PROMPTS_FILE}       - Prompts for batch benchmarking"
    echo "  ${AGGREGATED_RESULTS} - Summary of all results"
    echo "  ${BENCHMARK_DIR}/     - Individual benchmark logs"
}

clean_old_files() {
    if [ ! -d "${BENCHMARK_DIR}" ]; then
        echo "No benchmark directory found"
        return
    fi
    
    local file_count
    file_count=$(find "${BENCHMARK_DIR}" -name "*_benchmark.log" -type f | wc -l)
    
    if [ "${file_count}" -le 10 ]; then
        echo "Only ${file_count} files found, keeping all"
        return
    fi
    
    echo "Found ${file_count} files, keeping newest 10..."
    find "${BENCHMARK_DIR}" -name "*_benchmark.log" -type f -printf '%T@ %p\n' | \
    sort -rn | tail -n +11 | cut -d' ' -f2- | \
    while read -r file; do
        echo "Removing: $(basename "${file}")"
        rm -f "${file}"
    done
    
    echo "Cleanup complete"
}

# Check dependencies
for cmd in jq curl ollama awk; do
    if ! command -v "${cmd}" &> /dev/null; then
        echo -e "${RED}Error: Missing required command: ${cmd}${RESET}"
        exit 1
    fi
done

# Main execution
case "${1:-help}" in
    benchmark)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please provide a prompt${RESET}"
            echo "Usage: $0 benchmark \"Your prompt here\""
            exit 1
        fi
        run_single_benchmark "$2"
        ;;
    batch)
        run_batch_benchmark
        ;;
    aggregate)
        aggregate_results
        ;;
    create-prompts)
        create_sample_prompts
        ;;
    clean)
        clean_old_files
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown option: $1${RESET}"
        show_usage
        exit 1
        ;;
esac
BENCHMARK_EOF

chmod +x ~/llm-benchmark.sh

# Create sample prompts file if it doesn't exist
if [ ! -f ~/benchmark_prompts.txt ]; then
    ~/llm-benchmark.sh create-prompts
fi

echo "✓ Created ~/llm-benchmark.sh"
echo "✓ Created sample prompts file"
echo ""
echo "Usage examples:"
echo "  ~/llm-benchmark.sh benchmark \"Explain machine learning\""
echo "  ~/llm-benchmark.sh batch"
echo "  ~/llm-benchmark.sh aggregate"
echo ""
echo "The tool will benchmark all your installed models and rank them by performance."
EOF

chmod +x setup_model_benchmarking.sh
bash setup_model_benchmarking.sh
rm setup_model_benchmarking.sh
