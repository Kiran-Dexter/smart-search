#!/bin/bash
# =============================
# Intelligent Archive Scanner (Recursive)
# -----------------------------
# This script reads a list of directories (from "dirlist.txt"), then recursively finds archive files
# (with extensions .jar, .war, .zip, .tar, .tar.gz, .tgz, .tar.wz) inside each directory.
#
# It lists the archive contents without full extraction, searches for the keyword "Swagger" (case sensitive),
# and if found, writes details to an output file ("result.txt").
#
# It logs progress and errors to "script.log" and tracks processed files in "progress.log".
# If interrupted, it resumes from where it left off.
# =============================

# Files used by the script
INPUT_DIR_LIST="dirlist.txt"
OUTPUT_FILE="result.txt"
LOG_FILE="script.log"
PROGRESS_FILE="progress.log"

# Ensure log files exist
touch "$LOG_FILE" "$PROGRESS_FILE" "$OUTPUT_FILE"

# Function to log messages with timestamp
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting recursive archive scan..."

# Read each directory from the input file
while IFS= read -r dir || [ -n "$dir" ]; do
    # Skip empty lines
    [ -z "$dir" ] && continue

    # Validate that it's a directory
    if [ ! -d "$dir" ]; then
        log_message "ERROR: Not a directory: $dir"
        continue
    fi

    log_message "Scanning directory: $dir"
    
    # Use find to recursively locate files with allowed archive extensions
    while IFS= read -r file; do
        # Skip if file was already processed
        if grep -Fxq "$file" "$PROGRESS_FILE"; then
            log_message "Skipping already processed file: $file"
            continue
        fi

        log_message "Processing file: $file"

        # Determine the command to list archive contents based on file extension
        if [[ "$file" =~ \.(jar|war|zip)$ ]]; then
            list_cmd=(unzip -l "$file")
        elif [[ "$file" =~ \.tar$ ]]; then
            list_cmd=(tar -tf "$file")
        elif [[ "$file" =~ \.(tar\.gz|tgz)$ ]]; then
            list_cmd=(tar -tzf "$file")
        elif [[ "$file" =~ \.tar\.wz$ ]]; then
            list_cmd=(tar -tf "$file")
        else
            log_message "Unsupported file type: $file"
            echo "$file" >> "$PROGRESS_FILE"
            continue
        fi

        # Execute the command to list archive contents
        archive_output=$("${list_cmd[@]}" 2>> "$LOG_FILE")
        cmd_exit_code=$?

        # If command fails, log the error and mark the file as processed
        if [ $cmd_exit_code -ne 0 ]; then
            log_message "ERROR: Listing contents of $file failed with exit code $cmd_exit_code."
            echo "$file" >> "$PROGRESS_FILE"
            continue
        fi

        # Search for the keyword "Swagger" (case sensitive)
        if echo "$archive_output" | grep -q "Swagger"; then
            log_message "Keyword found in: $file"
            {
                echo "----------------------------"
                echo "File: $file"
                echo "$archive_output" | grep "Swagger"
                echo "----------------------------"
            } >> "$OUTPUT_FILE"
        fi

        # Mark file as processed
        echo "$file" >> "$PROGRESS_FILE"

        # Print progress and throttle a bit
        echo "Processed: $file"
        sleep 0.1

    done < <(find "$dir" -type f \( -iname "*.jar" -o -iname "*.war" -o -iname "*.zip" -o -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.tar.wz" \))
done < "$INPUT_DIR_LIST"

log_message "Archive scan completed."
