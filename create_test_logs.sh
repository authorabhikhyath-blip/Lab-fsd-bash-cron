#!/usr/bin/env bash
# create_test_logs.sh - builds a logs/ folder with fresh and old files for Lab #23
# Usage: ./create_test_logs.sh [target_dir]   (default: ./logs)

set -euo pipefail                      # stop on errors, unset variables and failed pipes

LOG_DIR="${1:-./logs}"                 # first argument, or ./logs if none given

rm -rf -- "$LOG_DIR"                   # start clean so every run gives the same result
mkdir -p -- "$LOG_DIR"                 # create the folder (-p: no error if parents are missing)

# make_log NAME DAYS_AGO SIZE_KB : creates a file of SIZE_KB of text and backdates its mtime
make_log() {
    local name="$1" days="$2" kb="$3"  # local = variables visible only inside this function
    local path="$LOG_DIR/$name"
    # yes prints a line forever; head -c cuts it to the size we want (text compresses well).
    # Process substitution <( ) is used instead of a pipe: with pipefail, "yes | head"
    # would fail with SIGPIPE (exit 141) when head stops reading.
    head -c "$((kb * 1024))" < <(yes "$(date '+%F %T') INFO app started request id=12345 status=200") > "$path"
    touch -d "$days days ago" -- "$path"   # set modification time to N days in the past
    echo "created: $path  (age ${days}d, ${kb}KB)"
}

# ---- fresh files (must NOT be touched by rotate_logs.sh) ----
make_log "app.log"             0  50
make_log "error.log"           2  20
make_log "access.log"          5  80

# ---- old files (> 7 days, must be gzipped) ----
make_log "app-old.log"        10 120
make_log "payment service.log" 12  60   # name with a space: tests safe quoting
make_log "debug.log"          20 200

# ---- not a .log file: must be ignored even though it is old ----
make_log "notes.txt"          15   5

# ---- existing archives: one young (kept), one older than 30 days (deleted) ----
make_log "archive-recent.log"  15  30 && gzip -f -- "$LOG_DIR/archive-recent.log"
touch -d "15 days ago" -- "$LOG_DIR/archive-recent.log.gz"
make_log "archive-ancient.log" 45  30 && gzip -f -- "$LOG_DIR/archive-ancient.log"
touch -d "45 days ago" -- "$LOG_DIR/archive-ancient.log.gz"

echo
echo "Test data ready in $LOG_DIR:"
ls -lh --time-style=long-iso -- "$LOG_DIR"
