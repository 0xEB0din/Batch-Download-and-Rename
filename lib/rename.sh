#!/usr/bin/env bash
# rename.sh — Batch file renaming engine with collision detection,
#              dry-run support, and rollback capability.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/logging.sh"
# shellcheck source=lib/validation.sh
source "${SCRIPT_DIR}/validation.sh"

# ── defaults ──────────────────────────────────────────────────────────

_RN_DRY_RUN=0
_RN_FORCE=0
_RN_TARGET_EXT=""           # override extension (e.g., "pdf")
_RN_PRESERVE_EXT=0          # keep original extension instead of mapping

# ── configuration ─────────────────────────────────────────────────────

rn_set_dry_run()      { _RN_DRY_RUN=1; }
rn_set_force()        { _RN_FORCE=1; }
rn_set_target_ext()   { _RN_TARGET_EXT="$1"; }
rn_set_preserve_ext() { _RN_PRESERVE_EXT=1; }

# ── public API ────────────────────────────────────────────────────────

# Renames files based on a parallel mapping of source names to target names.
#
#   rn_batch <source_list> <names_list> <source_dir> <output_dir>
#
# source_list:  one filename per line (files in source_dir)
# names_list:   one target name per line (paired with source_list)
# source_dir:   where source files live
# output_dir:   where renamed copies go
#
# Returns the count of failed renames.
rn_batch() {
    local source_list="$1"
    local names_list="$2"
    local source_dir="$3"
    local output_dir="$4"

    validate_readable_file "$source_list" "source file list"
    validate_readable_file "$names_list" "names list"
    validate_output_dir "$output_dir"

    if [[ ! -d "$source_dir" ]]; then
        log_error "source directory does not exist: %s" "$source_dir"
        return 1
    fi

    local total_src total_names
    total_src="$(count_entries "$source_list")"
    total_names="$(count_entries "$names_list")"

    if (( total_src != total_names )); then
        log_error "line count mismatch: %s has %d entries, %s has %d entries" \
            "$source_list" "$total_src" "$names_list" "$total_names"
        return 1
    fi

    log_info "starting batch rename: %d files" "$total_src"

    local failed=0 current=0
    local manifest=()

    while read -r src_file <&3 && read -r target_name <&4; do
        src_file="$(strip_cr "$src_file")"
        target_name="$(strip_cr "$target_name")"

        # Skip blank lines
        [[ -z "$src_file" || -z "$target_name" ]] && continue

        current=$(( current + 1 ))

        sanitize_filename "$src_file" || { failed=$(( failed + 1 )); continue; }

        local src_path="${source_dir}/${src_file}"
        if [[ ! -f "$src_path" ]]; then
            log_error "[%d/%d] source file missing: %s" "$current" "$total_src" "$src_path"
            failed=$(( failed + 1 ))
            continue
        fi

        # Determine target filename
        local target_filename
        target_filename="$(_resolve_target_name "$target_name" "$src_file")"

        sanitize_filename "$target_filename" || { failed=$(( failed + 1 )); continue; }

        local dest_path="${output_dir}/${target_filename}"

        # Collision detection
        if [[ -f "$dest_path" ]] && (( ! _RN_FORCE )); then
            log_error "[%d/%d] target already exists (use --force to overwrite): %s" \
                "$current" "$total_src" "$dest_path"
            failed=$(( failed + 1 ))
            continue
        fi

        if (( _RN_DRY_RUN )); then
            log_info "[dry-run] [%d/%d] %s -> %s" "$current" "$total_src" "$src_file" "$target_filename"
        else
            if cp -- "$src_path" "$dest_path"; then
                log_info "[%d/%d] %s -> %s" "$current" "$total_src" "$src_file" "$target_filename"
                manifest+=("${src_file}|${target_filename}")
            else
                log_error "[%d/%d] failed to copy %s" "$current" "$total_src" "$src_file"
                failed=$(( failed + 1 ))
            fi
        fi
    done 3<"$source_list" 4<"$names_list"

    # Write manifest for audit trail
    if (( ! _RN_DRY_RUN )) && (( ${#manifest[@]} > 0 )); then
        _write_manifest "$output_dir" "${manifest[@]}"
    fi

    if (( failed > 0 )); then
        log_warn "batch rename complete: %d/%d operations failed" "$failed" "$total_src"
    else
        log_info "batch rename complete: all %d files renamed" "$total_src"
    fi

    return "$failed"
}

# ── internal ──────────────────────────────────────────────────────────

_resolve_target_name() {
    local target_name="$1"
    local src_file="$2"

    local base="${target_name%%.*}"
    local ext=""

    if (( _RN_PRESERVE_EXT )); then
        ext="${src_file##*.}"
    elif [[ -n "$_RN_TARGET_EXT" ]]; then
        ext="$_RN_TARGET_EXT"
    else
        # Use extension from the target name, fallback to source extension
        if [[ "$target_name" == *.* ]]; then
            ext="${target_name##*.}"
        else
            ext="${src_file##*.}"
        fi
    fi

    if [[ -n "$ext" ]]; then
        printf '%s.%s' "$base" "$ext"
    else
        printf '%s' "$base"
    fi
}

_write_manifest() {
    local output_dir="$1"
    shift
    local entries=("$@")

    local manifest_path="${output_dir}/.rename-manifest.csv"
    {
        echo "timestamp,source,target"
        local ts
        ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
        for entry in "${entries[@]}"; do
            local src="${entry%%|*}"
            local tgt="${entry##*|}"
            echo "${ts},${src},${tgt}"
        done
    } > "$manifest_path"
    log_debug "manifest written: %s" "$manifest_path"
}
