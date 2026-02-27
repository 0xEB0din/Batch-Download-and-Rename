#!/usr/bin/env bash
# validation.sh — Input sanitization and validation helpers.
#
# Guards against path traversal, command injection via filenames,
# and malformed input files.

set -euo pipefail

# Source guard
[[ -n "${_VALIDATION_SH_LOADED:-}" ]] && return 0
_VALIDATION_SH_LOADED=1

# Maximum filename length (most filesystems cap at 255).
readonly MAX_FILENAME_LEN=255

# ── public API ────────────────────────────────────────────────────────

# Validates that a file exists and is readable.
validate_readable_file() {
    local path="$1" label="${2:-file}"
    if [[ ! -f "$path" ]]; then
        echo "error: ${label} not found: ${path}" >&2
        return 1
    fi
    if [[ ! -r "$path" ]]; then
        echo "error: ${label} not readable: ${path}" >&2
        return 1
    fi
}

# Validates that a directory exists or can be created.
validate_output_dir() {
    local dir="$1"
    if [[ -e "$dir" && ! -d "$dir" ]]; then
        echo "error: output path exists but is not a directory: ${dir}" >&2
        return 1
    fi
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            echo "error: cannot create output directory: ${dir}" >&2
            return 1
        }
    fi
    if [[ ! -w "$dir" ]]; then
        echo "error: output directory not writable: ${dir}" >&2
        return 1
    fi
}

# Checks a filename for path traversal sequences and illegal characters.
# Returns 0 if safe, 1 if dangerous.
sanitize_filename() {
    local name="$1"

    if [[ -z "$name" ]]; then
        echo "error: empty filename" >&2
        return 1
    fi

    # Block path traversal
    if [[ "$name" == *".."* ]]; then
        echo "error: path traversal detected in filename: ${name}" >&2
        return 1
    fi

    # Block absolute paths
    if [[ "$name" == /* ]]; then
        echo "error: absolute path not allowed: ${name}" >&2
        return 1
    fi

    # Block directory separators in what should be a bare filename
    if [[ "$name" == *"/"* ]]; then
        echo "error: directory separator in filename: ${name}" >&2
        return 1
    fi

    # Block shell metacharacters that could cause trouble in filenames
    if [[ "$name" =~ [\;\|\&\$\`\(\)\{\}] ]]; then
        echo "error: illegal characters in filename: ${name}" >&2
        return 1
    fi

    # Enforce length limit
    if (( ${#name} > MAX_FILENAME_LEN )); then
        echo "error: filename too long (${#name} > ${MAX_FILENAME_LEN}): ${name}" >&2
        return 1
    fi

    return 0
}

# Validates a URL for basic well-formedness.
validate_url() {
    local url="$1"

    if [[ -z "$url" ]]; then
        echo "error: empty URL" >&2
        return 1
    fi

    # Only allow http(s) and ftp(s) schemes
    if [[ ! "$url" =~ ^(https?|ftps?)://.+ ]]; then
        echo "error: invalid or unsupported URL scheme: ${url}" >&2
        return 1
    fi

    return 0
}

# Strip trailing carriage returns (common when input files come from Windows).
strip_cr() {
    local input="$1"
    printf '%s' "${input%$'\r'}"
}

# Count non-empty lines in a file (for progress reporting).
count_entries() {
    local file="$1"
    grep -c -v '^\s*$' "$file" 2>/dev/null || echo 0
}
