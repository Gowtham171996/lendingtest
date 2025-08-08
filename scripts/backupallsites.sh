#!/bin/bash

# --- User-configurable variables ---
# These are your API credentials and bench settings
API_URL="http://erpnext1.localhost:8000/api/method/solventumbackupmonitor.api.log_backup_status"
API_KEY="f77b4a6f900e6e4"
API_SECRET="cdaecd986e287fe"
BENCH_PATH="/home/gowtham/frappe-projects/lendingtest"
BACKUP_RETENTION=3


# --- Core script logic (do not edit below this line) ---

# Function to print a message with a timestamp to the console
print_log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_log "Starting bench backup for all sites..."
print_log "----------------------------------------"

# Change to the bench directory
cd "$BENCH_PATH" || { print_log "Failed to change to bench directory. Exiting."; exit 1; }

# Loop through all sites and perform a backup and cleanup
for SITE in sites/*; do
  if [ -d "$SITE" ] && [ -f "$SITE/site_config.json" ]; then
    SITE_NAME=$(basename "$SITE")
    BACKUP_DIR="$SITE/private/backups"

    # 1. Perform the backup
    print_log "Starting backup for site: $SITE_NAME..."
    BACKUP_OUTPUT=$(bench --site "$SITE_NAME" backup --with-files 2>&1)
    BACKUP_EXIT_CODE=$?

    # Check if the backup was successful
    if [ $BACKUP_EXIT_CODE -eq 0 ]; then
      STATUS="Success"
      print_log "Backup for $SITE_NAME completed successfully."
    else
      STATUS="Error"
      print_log "Backup for $SITE_NAME failed. Check the output for details."
    fi

    # 2. Clean redundant backups
    CLEANUP_OUTPUT=""
    if [ -d "$BACKUP_DIR" ]; then
      # Find and delete old backups
      find "$BACKUP_DIR" -type f \( -name "*.sql.gz" -o -name "*.tar.gz" \) | sort | head -n -"$BACKUP_RETENTION" | xargs -r rm --

      # Get the list of last 3 files
      LAST_3_FILES=$(find "$BACKUP_DIR" -type f \( -name "*.sql.gz" -o -name "*.tar.gz" \) | sort | tail -n "$BACKUP_RETENTION" | tr '\n' ' ')

      CLEANUP_OUTPUT="Cleanup for $SITE_NAME complete. Keeping the last $BACKUP_RETENTION copies. Last copies: $LAST_3_FILES"
    else
      CLEANUP_OUTPUT="No backup directory found for $SITE_NAME. Cleanup skipped."
      LAST_3_FILES=""
    fi
    print_log "$CLEANUP_OUTPUT"

    # 3. Write the list items to API using curl
    # Escape newlines from bench output for clean JSON
    LOG_MESSAGE=$(echo "$BACKUP_OUTPUT" | tr '\n' ' ')

    # Construct a clean JSON string
    JSON_DATA=$(jq -n \
      --arg site_name "$SITE_NAME" \
      --arg status "$STATUS" \
      --arg message "$LOG_MESSAGE | $CLEANUP_OUTPUT" \
      --arg backup_files "$LAST_3_FILES" \
      '{site_name: $site_name, status: $status, message: $message, backup_files: $backup_files}')


    print_log "Sending data to Frappe API at $API_URL"

    # Send the POST request with the JSON data, correctly labeled as the 'data' parameter
    curl -X POST \
      --header "Authorization: token $API_KEY:$API_SECRET" \
      --data-urlencode "data=$JSON_DATA" \
      "$API_URL"

  fi
done

print_log "All site backups and logging complete."
