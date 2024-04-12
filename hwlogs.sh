#!/bin/bash
# This script is designed for longer runs which require less frequency of data output.

# USER SETTINGS
LOGS_DIR="/home/$(whoami)/HWlogs/logs"
LOGS_INTERVAL=30 # seconds
STORAGE_DAYS=7

# Sleep before running to ensure drivers are properly loaded. Notably nvidia-smi.
sleep 120

# Check if the log directory exists, if not, create it
if [ ! -d "$LOGS_DIR" ]; then
    mkdir -p "$LOGS_DIR"
fi

while true; do
    # Get timestamp
    time_unix=$(date +%s)

    # Remove logs exceeding number of storage days
    for item in $LOGS_DIR/*; do
        # Check if the item is a directory and is not a symbolic link
        if [ -d "$item" ] && [ ! -L "$item" ]; then
            # Extract and print the directory name
            logged_date=$(basename "$item")

            # Convert string to unix and calculate date difference in days
            logged_date_unix=$(date -d $logged_date +%s)
            date_difference=$(((time_unix - logged_date_unix) / 86400)) # 86400 is number of seconds in a day
            if [ "$date_difference" -gt "$STORAGE_DAYS" ]; then
                rm -rf "$item"
            fi
        fi
    done

    while true; do
        timenow_unix=$(date +%s)
        timenow_yyyymmdd=$(date -d "@$timenow_unix" +'%Y-%m-%d')
        timenow_yyyymmddhhmm=$(date -d "@$timenow_unix" +'%Y-%m-%d %H:%M:%S')

        # Check if the log folder for today exists, if not, create it
        logs_path_today="$LOGS_DIR/$timenow_yyyymmdd"
        if [ ! -f "$logs_path_today" ]; then
            mkdir -p "$logs_path_today"
        fi

        ### 1. CPU logs ###
        # Reading from mpstat and converting output into array of rows separated by newline
        mpstat_output=$(mpstat -P ALL)
        readarray -t cpu_util_rows <<<"$mpstat_output"

        # Included additional CPU temperature information from sensors; Assuming AMD k10 driver; Tested for AMD Ryzen 9
        cpu_temp=$((sensors | grep -E 'Tctl|Tccd1|Tccd2') | awk '{print $2}')
        cpu_temp_csv=$(echo $cpu_temp | xargs | sed -e 's/ /, /g') # Convert to csv

        # Create file if it does not exist
        path_cpu_log="$logs_path_today/cpu.csv"
        if [ ! -f "$path_cpu_log" ]; then
            touch "$path_cpu_log"
        fi

        # Add header to csv if it does not exist
        csv_cpu_header=$(head -n 1 "$path_cpu_log")
        if ! echo "$csv_cpu_header" | grep -q "\<timestamp\>"; then
            cpu_util_header=(${cpu_util_rows[2]})
            cpu_util_header_csv=$(echo ${cpu_util_header[@]:1} | xargs | sed -e 's/ /, /g') # Convert to csv
            cpu_log_header=$(echo "timestamp," ${cpu_util_header_csv[@]:1} ", Tctl, Tccd1, Tccd2")
            awk -v header="$cpu_log_header" 'BEGIN {print header} {print}' "$path_cpu_log" > temp.csv && mv temp.csv "$path_cpu_log"
        fi

        # Logging by looping through all CPU cores
        for cpu_core in "${cpu_util_rows[@]:3}"; do # Data only begin from 3rd line
            cpu_core_array=($cpu_core) # Convert string to array
            cpu_util_csv=$(echo ${cpu_core_array[@]:1} | xargs | sed -e 's/ /, /g') # Convert to csv
            echo "$timenow_yyyymmddhhmm," $cpu_util_csv ", $cpu_temp_csv" >> $path_cpu_log
        done



        ### 2. NVIDIA GPU logs ###
        # Reading from nvidia-smi and converting output into array of rows separated by newline
        nvidiasmi_output=$(nvidia-smi \
                    --query-gpu=timestamp,name,pci.bus_id,driver_version,pstate,pcie.link.gen.max,pcie.link.gen.current,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.free,memory.used \
                    --format=csv)
        readarray -t nvgpu_logs_rows <<<"$nvidiasmi_output"

        # Create csv file if it does not exist
        path_nvgpu_log="$logs_path_today/nvgpu.csv"
        if [ ! -f "$path_nvgpu_log" ]; then
            touch "$path_nvgpu_log"
        fi

        # Logging
        if echo "$nvgpu_logs_rows" | grep -q "\<failed\>"; then
            # When NVIDIA driver fails, only log timestamp
            echo "$timenow_yyyymmddhhmm" >> $path_nvgpu_log

        else 
            # Add headers to csv if it does not exist
            csv_gpu_header=$(head -n 1 "$path_nvgpu_log")
            if ! echo "$csv_gpu_header" | grep -q "\<timestamp\>"; then
                awk -v header="${nvgpu_logs_rows[0]}" 'BEGIN {print header} {print}' "$path_nvgpu_log" > temp.csv && mv temp.csv "$path_nvgpu_log"
            fi

            # Log output from nvidia-smi
            for nvgpu in "${nvgpu_logs_rows[@]:1}"; do
                echo "$nvgpu" >> $path_nvgpu_log
            done

        fi



        ### 3. All output from sensors ###
        # Reading from sensors and converting the output into an array of rows
        sensors_output=$(sensors)
        readarray -t sensors_rows<<<"$sensors_output"

        device_headers=()
        device_values=()
        for row in "${sensors_rows[@]}"; do

            if [ -n "$row" ]; then
                # Prepocessing - remove parathensis (for nvme)
                row_parenthesis_remove=$(echo "$row" | awk '{gsub(/\([^()]*\)/, "")} 1')

                # Prepocessing - awk print elements before colon, tr remove whitespaces before first word
                device_header=$(echo $row_parenthesis_remove |  awk -F ':' '{print $1}' |  tr -d ' ')
                device_value=$(echo $row_parenthesis_remove |  awk -F ':' '{print $2}' |  tr -d ' ')
                
                # Collate data of same sensor into single array
                device_headers+=("$device_header")
                device_values+=("$device_value")

            else
                device_name=${device_headers[0]}
                path_device_log="$logs_path_today/$device_name.csv"

                # Create file if it does not exist
                if [ ! -f "$path_device_log" ]; then
                    touch "$path_device_log"
                fi

                # Add header to csv if it does not exist
                csv_device_header=$(head -n 1 "$path_device_log")
                if ! echo "$csv_device_header" | grep -q "\<timestamp\>"; then
                    device_headers_csv=$(echo ${device_headers[@]:1} | xargs | sed -e 's/ /, /g') # Convert to csv
                    device_log_header=$(echo "timestamp," "$device_headers_csv")
                    awk -v header="$device_log_header" 'BEGIN {print header} {print}' "$path_device_log" > temp.csv && mv temp.csv "$path_device_log"
                fi

                # Logging
                device_values_csv=$(echo ${device_values[@]} | xargs | sed -e 's/ /, /g') # Convert to csv
                echo "$timenow_yyyymmddhhmm," "$device_values_csv" >> $path_device_log

                # Initialize headers and values again
                device_headers=()
                device_values=()
            fi
        done


        # Break if new day started, if not resume logging
        time_difference=$((timenow_unix - time_unix))
        if [ "$time_difference" -gt 86400 ]; then # 86400 is number of seconds in a day
            break
        else
            sleep $LOGS_INTERVAL
        fi

    done
    
done

