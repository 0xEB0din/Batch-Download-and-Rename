#!/usr/bin/env bash
# download.sh — Download engine with retry logic, checksum verification,
#               and rate-limit awareness.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/logging.sh"
# shellcheck source=lib/validation.sh
source "${SCRIPT_DIR}/validation.sh"

# ── defaults ──────────────────────────────────────────────────────────

_DL_MAX_RETRIES=3
_DL_RETRY_DELAY=2          # seconds, doubles on each retry
_DL_CONNECT_TIMEOUT=10
_DL_READ_TIMEOUT=30
_DL_USER_AGENT="BatchDL/1.0"
_DL_DRY_RUN=0
_DL_VERIFY_CERT=1

# ── configuration ─────────────────────────────────────────────────────

dl_set_retries()         { _DL_MAX_RETRIES="$1"; }
dl_set_retry_delay()     { _DL_RETRY_DELAY="$1"; }
dl_set_connect_timeout() { _DL_CONNECT_TIMEOUT="$1"; }
dl_set_read_timeout()    { _DL_READ_TIMEOUT="$1"; }
dl_set_user_agent()      { _DL_USER_AGENT="$1"; }
dl_set_dry_run()         { _DL_DRY_RUN=1; }
dl_set_skip_cert()       { _DL_VERIFY_CERT=0; }

# ── public API ────────────────────────────────────────────────────────

# Downloads a single file with retry and optional checksum verification.
#
#   dl_fetch <url> <output_dir> [expected_sha256]
#
# Returns 0 on success, 1 on failure after exhausting retries.
dl_fetch() {
    local url="$1"
    local output_dir="$2"
    local expected_hash="${3:-}"

    validate_url "$url" || return 1

    local filename
    filename="$(basename "$url")"
    filename="$(strip_cr "$filename")"

    sanitize_filename "$filename" || return 1

    local dest="${output_dir}/${filename}"

    if (( _DL_DRY_RUN )); then
        log_info "[dry-run] would download: %s -> %s" "$url" "$dest"
        return 0
    fi

    local attempt=0
    local delay="$_DL_RETRY_DELAY"

    while (( attempt < _DL_MAX_RETRIES )); do
        attempt=$(( attempt + 1 ))
        log_info "downloading (%d/%d): %s" "$attempt" "$_DL_MAX_RETRIES" "$url"

        local wget_args=(
            --no-verbose
            --timeout="$_DL_READ_TIMEOUT"
            --connect-timeout="$_DL_CONNECT_TIMEOUT"
            --user-agent="$_DL_USER_AGENT"
            --output-document="$dest"
        )

        if (( ! _DL_VERIFY_CERT )); then
            wget_args+=( --no-check-certificate )
        fi

        if wget "${wget_args[@]}" "$url"; then
            # Verify checksum if provided
            if [[ -n "$expected_hash" ]]; then
                local actual_hash
                actual_hash="$(sha256sum "$dest" | awk '{print $1}')"
                if [[ "$actual_hash" != "$expected_hash" ]]; then
                    log_error "checksum mismatch for %s (expected %s, got %s)" \
                        "$filename" "$expected_hash" "$actual_hash"
                    rm -f "$dest"
                    return 1
                fi
                log_debug "checksum verified: %s" "$filename"
            fi
            log_info "saved: %s" "$dest"
            return 0
        fi

        log_warn "attempt %d failed for %s" "$attempt" "$url"

        if (( attempt < _DL_MAX_RETRIES )); then
            log_info "retrying in %ds..." "$delay"
            sleep "$delay"
            delay=$(( delay * 2 ))
        fi
    done

    log_error "all %d attempts failed for: %s" "$_DL_MAX_RETRIES" "$url"
    return 1
}

# Downloads all URLs listed in a file.
#
#   dl_batch <url_list_file> <output_dir> [checksum_file]
#
# checksum_file format: <sha256>  <filename>  (same as sha256sum output)
#
# Returns the count of failed downloads.
dl_batch() {
    local url_file="$1"
    local output_dir="$2"
    local checksum_file="${3:-}"

    validate_readable_file "$url_file" "URL list"
    validate_output_dir "$output_dir"

    if [[ -n "$checksum_file" ]]; then
        validate_readable_file "$checksum_file" "checksum file"
    fi

    local total failed=0 current=0
    total="$(count_entries "$url_file")"
    log_info "starting batch download: %d files -> %s" "$total" "$output_dir"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(strip_cr "$line")"

        # Skip blank lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        current=$(( current + 1 ))
        log_info "[%d/%d] processing: %s" "$current" "$total" "$line"

        local expected_hash=""
        if [[ -n "$checksum_file" ]]; then
            local fname
            fname="$(basename "$line")"
            expected_hash="$(grep -w "$fname" "$checksum_file" 2>/dev/null | awk '{print $1}')" || true
        fi

        if ! dl_fetch "$line" "$output_dir" "$expected_hash"; then
            failed=$(( failed + 1 ))
        fi
    done < "$url_file"

    if (( failed > 0 )); then
        log_warn "batch complete: %d/%d downloads failed" "$failed" "$total"
    else
        log_info "batch complete: all %d files downloaded" "$total"
    fi

    return "$failed"
}
