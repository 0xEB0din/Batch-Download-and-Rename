#!/usr/bin/env bash
# logging.sh — Structured logging with severity levels and optional file output.
#
# Usage:
#   source lib/logging.sh
#   log_init "/var/log/batch-dl.log"  # optional, enables file logging
#   log_info "starting download..."
#   log_error "wget returned %d for %s" "$rc" "$url"

set -euo pipefail

# Source guard
[[ -n "${_LOGGING_SH_LOADED:-}" ]] && return 0
_LOGGING_SH_LOADED=1

readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

_LOG_LEVEL="${LOG_LEVEL_INFO}"
_LOG_FILE=""
_LOG_QUIET=0

# ── public API ────────────────────────────────────────────────────────

log_init() {
    local log_file="${1:-}"
    if [[ -n "$log_file" ]]; then
        local log_dir
        log_dir="$(dirname "$log_file")"
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || {
                _log_stderr "WARN" "cannot create log directory ${log_dir}, file logging disabled"
                return 1
            }
        fi
        _LOG_FILE="$log_file"
    fi
}

log_set_level() {
    case "${1:-}" in
        debug) _LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        info)  _LOG_LEVEL=$LOG_LEVEL_INFO ;;
        warn)  _LOG_LEVEL=$LOG_LEVEL_WARN ;;
        error) _LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *)     _log_stderr "WARN" "unknown log level: %s" "${1:-}" ;;
    esac
}

log_set_quiet() { _LOG_QUIET=1; }

log_debug() { _log_dispatch "$LOG_LEVEL_DEBUG" "DEBUG" "$@"; }
log_info()  { _log_dispatch "$LOG_LEVEL_INFO"  "INFO"  "$@"; }
log_warn()  { _log_dispatch "$LOG_LEVEL_WARN"  "WARN"  "$@"; }
log_error() { _log_dispatch "$LOG_LEVEL_ERROR" "ERROR" "$@"; }

# ── internal ──────────────────────────────────────────────────────────

_log_dispatch() {
    local level="$1" label="$2"
    shift 2

    (( level < _LOG_LEVEL )) && return 0

    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    local msg
    # shellcheck disable=SC2059
    printf -v msg "$@" 2>/dev/null || msg="$*"

    local line="${ts} [${label}] ${msg}"

    if [[ -n "$_LOG_FILE" ]]; then
        echo "$line" >> "$_LOG_FILE"
    fi

    if (( _LOG_QUIET == 0 )); then
        if (( level >= LOG_LEVEL_WARN )); then
            echo "$line" >&2
        else
            echo "$line"
        fi
    fi
}

_log_stderr() {
    local label="$1"; shift
    local msg
    # shellcheck disable=SC2059
    printf -v msg "$@" 2>/dev/null || msg="$*"
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [${label}] ${msg}" >&2
}
