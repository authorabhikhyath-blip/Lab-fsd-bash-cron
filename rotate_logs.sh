#!/usr/bin/env bash
# =============================================================================
# rotate_logs.sh - compress .log files older than DAYS and delete .gz archives
#                  older than RETENTION_DAYS.                     (Lab #23)
#
# Exit codes: 0 = success, 1 = bad usage, 2 = log folder missing/unusable,
#             3 = one or more files failed to compress
# =============================================================================

set -euo pipefail          # -e: exit on any failing command
                           # -u: using an unset variable is an error
                           # -o pipefail: a pipe fails if ANY command in it fails
IFS=$'\n\t'                # word-split only on newline/tab, never on spaces

# ---- defaults: environment variable if set, otherwise the fixed value -------
LOG_DIR="${LOG_DIR:-./logs}"              # folder that holds the logs
DAYS="${DAYS:-7}"                         # compress .log files older than this
RETENTION_DAYS="${RETENTION_DAYS:-30}"    # delete .gz files older than this
DRY_RUN=0                                 # 1 = only print what would happen

SCRIPT_NAME="$(basename "$0")"            # used in the help text

# ---- helper functions --------------------------------------------------------
log() {                                   # timestamped message to stdout
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}
err() {                                   # timestamped message to stderr
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}
usage() {                                 # help text (heredoc keeps formatting)
    cat <<EOF
Usage: $SCRIPT_NAME [-d DIR] [-a DAYS] [-r RETENTION_DAYS] [-n|--dry-run] [-h|--help]

  -d, --dir DIR          log folder              (env LOG_DIR, default ./logs)
  -a, --age DAYS         gzip .log older than    (env DAYS, default 7)
  -r, --retention DAYS   delete .gz older than   (env RETENTION_DAYS, default 30)
  -n, --dry-run          show actions, change nothing
  -h, --help             show this help

Example: $SCRIPT_NAME -d /var/log/myapp -a 7 -r 30
Exit codes: 0 ok, 1 usage error, 2 folder missing, 3 compression failure
EOF
}

# ---- parse command-line arguments (they override env vars) ------------------
while [[ $# -gt 0 ]]; do                  # loop while arguments remain
    case "$1" in
        -d|--dir)        LOG_DIR="${2:?missing value for $1}"; shift 2 ;;
        -a|--age)        DAYS="${2:?missing value for $1}"; shift 2 ;;
        -r|--retention)  RETENTION_DAYS="${2:?missing value for $1}"; shift 2 ;;
        -n|--dry-run)    DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               err "unknown option: $1"; usage >&2; exit 1 ;;
    esac
done

# ---- validate input ----------------------------------------------------------
for v in DAYS RETENTION_DAYS; do          # both must be whole numbers
    if ! [[ "${!v}" =~ ^[0-9]+$ ]]; then  # ${!v} = value of the variable named by v
        err "$v must be a non-negative integer (got '${!v}')"; exit 1
    fi
done
if [[ ! -d "$LOG_DIR" ]]; then            # folder must exist
    err "log directory '$LOG_DIR' does not exist"; exit 2
fi
if [[ ! -w "$LOG_DIR" ]]; then            # and we must be able to write in it
    err "log directory '$LOG_DIR' is not writable"; exit 2
fi

# run CMD...: execute the command, or only print it in dry-run mode
run() {
    local IFS=" "                         # join "$*" with spaces (global IFS is newline)
    if [[ $DRY_RUN -eq 1 ]]; then log "DRY-RUN: $*"; else "$@"; fi
}

log "START dir=$LOG_DIR age>${DAYS}d retention>${RETENTION_DAYS}d dry_run=$DRY_RUN"

compressed=0; deleted=0; failed=0         # counters for the summary
                                          # (x=$((x+1)) is used, not ((x++)), because
                                          #  ((x++)) returns status 1 when x=0 and set -e would exit)

# ---- step 1: delete archives older than RETENTION_DAYS -----------------------
# Done FIRST so that logs compressed in this same run are never deleted at once.
# -print0 + read -d '' passes names separated by NUL bytes -> safe for spaces/newlines.
while IFS= read -r -d '' gz; do
    log "DELETE   $gz"
    run rm -f -- "$gz"                    # -- ends options: a name like "-x.gz" is safe
    deleted=$((deleted + 1))
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.gz' -mtime +"$RETENTION_DAYS" -print0)

# ---- step 2: compress (rotate) .log files older than DAYS --------------------
# -mtime +7 = modified more than 7 full days (7*24h) ago.
while IFS= read -r -d '' f; do
    dest="$f.gz"                          # app.log -> app.log.gz
    if [[ -e "$dest" ]]; then             # never overwrite an existing archive
        dest="${f%.log}-$(date '+%Y%m%d%H%M%S').log.gz"
    fi
    log "COMPRESS $f -> $dest"
    if [[ $DRY_RUN -eq 1 ]]; then
        log "DRY-RUN: gzip -9 -c -- '$f' > '$dest' && rm -- '$f'"
        compressed=$((compressed + 1))    # counts "would compress" in dry-run
    elif gzip -9 -c -- "$f" > "$dest" && touch -r "$f" -- "$dest" && rm -f -- "$f"; then
        # gzip -9: best compression, -c: write to stdout (we pick the name)
        # touch -r: archive keeps the original log's age, so retention counts from it
        compressed=$((compressed + 1))
    else
        err "failed to compress '$f'"
        rm -f -- "$dest"                  # remove half-written archive, keep original
        failed=$((failed + 1))
    fi
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$DAYS" -print0)

# ---- summary + exit code -----------------------------------------------------
log "DONE compressed=$compressed deleted=$deleted failed=$failed"
if [[ $failed -gt 0 ]]; then exit 3; fi
exit 0
