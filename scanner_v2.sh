#!/bin/bash
# ============================================================
# Intelligent Archive & File Scanner with Resume Capability
# ------------------------------------------------------------
# Inputs:
#   1. dirlist.txt  -> Contains directories to scan (one per line)
#   2. filelist.txt -> Contains full file paths to process directly (one per line)
#
# This script:
#   - Recursively scans directories from dirlist.txt for files with
#     extensions: .zip, .tar, .war, .tar.gz, .json, .txt, .rar, .tar.wz.
#   - Processes files from filelist.txt as provided.
#   - Uses appropriate commands to list archive contents without full extraction.
#   - Searches for the case-sensitive keyword "swagger".
#   - Logs results (full path and matching content) in result.txt and detailed logs in script.log.
#   - Records processed files in progress.log to resume after interruption.
#   - Logs missing files or errors in missing.log.
#   - Uses custom magic number detection when the file command is unavailable.
# ============================================================

# Input files
DIR_LIST="dirlist.txt"
FILE_LIST="filelist.txt"

# Output & log files
RESULT_FILE="result.txt"
LOG_FILE="script.log"
PROGRESS_FILE="progress.log"
MISSING_LOG="missing.log"

# Ensure necessary files exist
touch "$RESULT_FILE" "$LOG_FILE" "$PROGRESS_FILE" "$MISSING_LOG"

# Sleep interval to throttle processing
SLEEP_INTERVAL=0.1

# Log function with timestamp
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to detect archive type using magic numbers (no file command)
detect_archive_type() {
  local file="$1"
  # Read first 4 bytes as hex
  local magic
  magic=$(head -c 4 "$file" 2>/dev/null | od -An -tx1 | tr -d ' ')
  if [[ "$magic" == "504b0304" ]]; then
    echo "zip"
    return 0
  fi

  # Check for gzip (first 2 bytes: 1f8b)
  local magic2
  magic2=$(head -c 2 "$file" 2>/dev/null | od -An -tx1 | tr -d ' ')
  if [[ "$magic2" == "1f8b" ]]; then
    echo "targz"
    return 0
  fi

  # Check for tar: look for 'ustar' in first 1024 bytes
  if head -c 1024 "$file" 2>/dev/null | grep -q "ustar"; then
    echo "tar"
    return 0
  fi

  echo "unknown"
  return 1
}

# Function to process a single file
process_file() {
  local file="$1"
  
  # Check if file already processed
  if grep -Fxq "$file" "$PROGRESS_FILE"; then
    log_message "Skipping already processed file: $file"
    return
  fi

  # Check if file exists
  if [ ! -f "$file" ]; then
    log_message "ERROR: File not found: $file"
    echo "$file" >> "$MISSING_LOG"
    echo "$file" >> "$PROGRESS_FILE"
    return
  fi

  log_message "Processing file: $file"

  # Determine file extension (if any)
  local filename ext output archive_type
  filename=$(basename "$file")
  if [[ "$filename" == *.* ]]; then
    ext=$(echo "$filename" | awk -F. '{print tolower($NF)}')
  else
    ext=""
  fi

  # Based on extension, choose the command to list or cat the file content
  case "$ext" in
    jar|war|zip)
      output=$(unzip -l "$file" 2>/dev/null)
      ;;
    tar)
      output=$(tar -tf "$file" 2>/dev/null)
      ;;
    gz|tgz)
      output=$(tar -tzf "$file" 2>/dev/null)
      ;;
    "tar.wz")
      output=$(tar -tf "$file" 2>/dev/null)
      ;;
    rar)
      output=$(unrar l "$file" 2>/dev/null)
      ;;
    json|txt)
      output=$(cat "$file" 2>/dev/null)
      ;;
    *)
      # No extension or unknown extension, try to detect using magic numbers
      archive_type=$(detect_archive_type "$file")
      case "$archive_type" in
        zip)
          output=$(unzip -l "$file" 2>/dev/null)
          ;;
        tar)
          output=$(tar -tf "$file" 2>/dev/null)
          ;;
        targz)
          output=$(tar -tzf "$file" 2>/dev/null)
          ;;
        *)
          # If detection fails, try reading as plain text
          output=$(cat "$file" 2>/dev/null)
          ;;
      esac
      ;;
  esac

  # Check if the listing command succeeded
  if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to process $file"
    echo "$file" >> "$MISSING_LOG"
    echo "$file" >> "$PROGRESS_FILE"
    return
  fi

  # Search for the case-sensitive keyword "swagger"
  if echo "$output" | grep -q "swagger"; then
      # Capture matching lines
      local matches
      matches=$(echo "$output" | grep "swagger")
      {
        echo "----------------------------"
        echo "File: $file"
        echo "$matches"
        echo "----------------------------"
      } >> "$RESULT_FILE"
      log_message "Match found in $file: $matches"
  fi

  # Mark the file as processed
  echo "$file" >> "$PROGRESS_FILE"
  sleep "$SLEEP_INTERVAL"
}

# Function to recursively scan a directory (if find is not available)
scan_directory() {
  local dir="$1"
  # List items in directory
  for entry in "$dir"/*; do
    # Skip if no entry exists
    [ -e "$entry" ] || continue
    if [ -d "$entry" ]; then
      scan_directory "$entry"
    elif [ -f "$entry" ]; then
      # Process only files that match our allowed types
      if [[ "$entry" =~ \.(jar|war|zip|tar|gz|tgz|json|txt|rar|tar\.wz)$ ]]; then
        process_file "$entry"
      else
        # Even if file doesn't match, try to process it using detection
        process_file "$entry"
      fi
    fi
  done
}

####################
# MAIN SCRIPT FLOW #
####################

log_message "=== Starting Archive & File Scan ==="

# Process directories listed in DIR_LIST
if [ -f "$DIR_LIST" ]; then
  while IFS= read -r dir || [ -n "$dir" ]; do
    [ -z "$dir" ] && continue
    if [ ! -d "$dir" ]; then
      log_message "ERROR: Not a directory: $dir"
      echo "$dir" >> "$MISSING_LOG"
      continue
    fi
    log_message "Scanning directory: $dir"
    scan_directory "$dir"
  done < "$DIR_LIST"
fi

# Process files listed in FILE_LIST
if [ -f "$FILE_LIST" ]; then
  while IFS= read -r file || [ -n "$file" ]; do
    [ -z "$file" ] && continue
    process_file "$file"
  done < "$FILE_LIST"
fi

log_message "=== Archive & File Scan Completed ==="
