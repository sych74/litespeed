#!/bin/bash

# Parameters
SERVICE_LSWS="lsws"
SERVICE_ADC="litespeedadc"
LOG_FILE="/var/log/messages"  # Specify the correct log file path
FLAG_FILE="/tmp/litespeed_license_issue.flag"
JEM_API_URL="https://your-jem-api-endpoint"  # Specify the correct URL
LOG_OUTPUT="/var/log/litespeed_monitor.log"
CURRENT_TIME=$(date +%s)
TIME_THRESHOLD=1800  # 30 minutes in seconds

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_OUTPUT"
}

# Determine Litespeed type from /etc/jelastic/metainf.conf
META_INF_FILE="/etc/jelastic/metainf.conf"
if [[ -f "$META_INF_FILE" ]]; then
    COMPUTE_TYPE=$(grep "^COMPUTE_TYPE=" "$META_INF_FILE" | cut -d'=' -f2)
    if [[ "$COMPUTE_TYPE" == "litespeed" || "$COMPUTE_TYPE" == "LLSMP" ]]; then
        SERVICE="$SERVICE_LSWS"
    elif [[ "$COMPUTE_TYPE" == "litespeed_adc" ]]; then
        SERVICE="$SERVICE_ADC"
    else
        log "Unknown COMPUTE_TYPE: $COMPUTE_TYPE. Exiting."
        exit 1
    fi
else
    log "Meta information file not found. Exiting."
    exit 1
fi

# Check if the process is running
if systemctl is-active --quiet "$SERVICE"; then
    log "Process $SERVICE is running. Removing flag if exists."
    rm -f "$FLAG_FILE"
    exit 0
fi

# If the process is not running, try to start it
log "Process $SERVICE is not running. Attempting to start."
systemctl start "$SERVICE"
# This script pauses execution for 10 seconds to allow sufficient time for a service or process to start up.
sleep 10  # Give some time for startup

# Check if the process started successfully
if systemctl is-active --quiet "$SERVICE"; then
    log "Process $SERVICE successfully started. Removing flag."
    rm -f "$FLAG_FILE"
    exit 0
fi

# Analyze logs for license error
log "Process failed to start. Checking logs for license issues."
LAST_ERROR=$(grep "[FATAL] license problem, back to Apache!" "$LOG_FILE" | tail -1)

if [[ -n "$LAST_ERROR" ]]; then
    LOG_TIME_STR=$(echo "$LAST_ERROR" | awk '{print $1, $2, $3}')
    LOG_TIME=$(date -d "$LOG_TIME_STR" +%s)
    
    TIME_DIFF=$((CURRENT_TIME - LOG_TIME))
    if [[ $TIME_DIFF -le $TIME_THRESHOLD ]]; then
        if [[ ! -f "$FLAG_FILE" ]]; then
            log "License issue detected. Calling JEM API."
            curl -X POST "$JEM_API_URL" -H "Content-Type: application/json" -d '{"event": "license_issue"}'
            touch "$FLAG_FILE"
        else
            log "License issue already recorded, flag exists. Doing nothing."
        fi
    else
        log "License issue is outdated (more than 30 minutes). Ignoring."
    fi
else
    log "No license issue found in logs."
fi
