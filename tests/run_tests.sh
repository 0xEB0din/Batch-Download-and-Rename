#!/usr/bin/env bash
# run_tests.sh — Minimal test harness for batch-dl and batch-rename.
#
# Run: bash tests/run_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMPDIR_BASE=""

# ── test helpers ──────────────────────────────────────────────────────

_pass=0
_fail=0

setup() {
    TMPDIR_BASE="$(mktemp -d)"
}

teardown() {
    if [[ -n "$TMPDIR_BASE" && -d "$TMPDIR_BASE" ]]; then
        rm -rf "$TMPDIR_BASE"
    fi
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assertion}"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: ${msg}"
        _pass=$(( _pass + 1 ))
    else
        echo "  FAIL: ${msg} (expected '${expected}', got '${actual}')"
        _fail=$(( _fail + 1 ))
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-file exists}"
    if [[ -f "$path" ]]; then
        echo "  PASS: ${msg}"
        _pass=$(( _pass + 1 ))
    else
        echo "  FAIL: ${msg} (file not found: ${path})"
        _fail=$(( _fail + 1 ))
    fi
}

assert_exit_code() {
    local expected="$1" msg="${2:-exit code}"
    shift 2
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    assert_eq "$expected" "$actual" "$msg"
}

trap teardown EXIT

# ── validation tests ──────────────────────────────────────────────────

test_validation() {
    echo "=== Validation module ==="
    source "${PROJECT_ROOT}/lib/validation.sh"

    # Path traversal detection
    local rc=0
    sanitize_filename "../etc/passwd" 2>/dev/null || rc=$?
    assert_eq "1" "$rc" "blocks path traversal"

    rc=0
    sanitize_filename "/etc/passwd" 2>/dev/null || rc=$?
    assert_eq "1" "$rc" "blocks absolute paths"

    rc=0
    sanitize_filename "safe-file.pdf" 2>/dev/null || rc=$?
    assert_eq "0" "$rc" "allows safe filenames"

    rc=0
    sanitize_filename "file;rm -rf /" 2>/dev/null || rc=$?
    assert_eq "1" "$rc" "blocks shell metacharacters"

    rc=0
    sanitize_filename "" 2>/dev/null || rc=$?
    assert_eq "1" "$rc" "blocks empty filenames"

    # URL validation
    rc=0
    validate_url "https://example.com/file.pdf" 2>/dev/null || rc=$?
    assert_eq "0" "$rc" "accepts valid HTTPS URL"

    rc=0
    validate_url "ftp://files.example.com/data.csv" 2>/dev/null || rc=$?
    assert_eq "0" "$rc" "accepts valid FTP URL"

    rc=0
    validate_url "file:///etc/passwd" 2>/dev/null || rc=$?
    assert_eq "1" "$rc" "rejects file:// scheme"

    rc=0
    validate_url "" 2>/dev/null || rc=$?
    assert_eq "1" "$rc" "rejects empty URL"

    # CR stripping
    local result
    result="$(strip_cr "hello\r")"
    # The \r is literal here since it came from a variable
    assert_eq "hello" "$(strip_cr $'hello\r')" "strips carriage return"
}

# ── rename tests ──────────────────────────────────────────────────────

test_rename() {
    echo "=== Rename module ==="
    setup

    local src_dir="${TMPDIR_BASE}/src"
    local out_dir="${TMPDIR_BASE}/out"
    local files_list="${TMPDIR_BASE}/files.txt"
    local names_list="${TMPDIR_BASE}/names.txt"

    mkdir -p "$src_dir" "$out_dir"

    # Create test files
    echo "test content 1" > "${src_dir}/file1.txt"
    echo "test content 2" > "${src_dir}/file2.txt"
    echo "test content 3" > "${src_dir}/file3.txt"

    # Create mapping files
    printf 'file1.txt\nfile2.txt\nfile3.txt\n' > "$files_list"
    printf 'Report Alpha.txt\nReport Beta.txt\nReport Gamma.txt\n' > "$names_list"

    source "${PROJECT_ROOT}/lib/rename.sh"
    log_set_level error  # quiet during tests

    rn_batch "$files_list" "$names_list" "$src_dir" "$out_dir"

    assert_file_exists "${out_dir}/Report Alpha.txt" "file1 renamed correctly"
    assert_file_exists "${out_dir}/Report Beta.txt" "file2 renamed correctly"
    assert_file_exists "${out_dir}/Report Gamma.txt" "file3 renamed correctly"

    # Verify content integrity
    local content
    content="$(cat "${out_dir}/Report Alpha.txt")"
    assert_eq "test content 1" "$content" "content preserved after rename"

    # Verify manifest was created
    assert_file_exists "${out_dir}/.rename-manifest.csv" "manifest written"

    teardown
}

# ── dry-run tests ─────────────────────────────────────────────────────

test_dry_run() {
    echo "=== Dry-run mode ==="
    setup

    local src_dir="${TMPDIR_BASE}/src"
    local out_dir="${TMPDIR_BASE}/out"
    local files_list="${TMPDIR_BASE}/files.txt"
    local names_list="${TMPDIR_BASE}/names.txt"

    mkdir -p "$src_dir" "$out_dir"
    echo "content" > "${src_dir}/original.txt"
    echo "original.txt" > "$files_list"
    echo "renamed.txt" > "$names_list"

    source "${PROJECT_ROOT}/lib/rename.sh"
    log_set_level error
    rn_set_dry_run

    rn_batch "$files_list" "$names_list" "$src_dir" "$out_dir"

    # File should NOT exist in dry-run mode
    if [[ ! -f "${out_dir}/renamed.txt" ]]; then
        echo "  PASS: dry-run did not create files"
        _pass=$(( _pass + 1 ))
    else
        echo "  FAIL: dry-run should not create files"
        _fail=$(( _fail + 1 ))
    fi

    teardown
}

# ── CLI help tests ────────────────────────────────────────────────────

test_cli_help() {
    echo "=== CLI interface ==="

    assert_exit_code "0" "batch-dl --help works" bash "${PROJECT_ROOT}/batch-dl" --help
    assert_exit_code "0" "batch-rename --help works" bash "${PROJECT_ROOT}/batch-rename" --help
    assert_exit_code "0" "batch-dl --version works" bash "${PROJECT_ROOT}/batch-dl" --version
    assert_exit_code "1" "batch-dl fails without args" bash "${PROJECT_ROOT}/batch-dl"
    assert_exit_code "1" "batch-rename fails without args" bash "${PROJECT_ROOT}/batch-rename"
}

# ── run ───────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "batch-dl test suite"
    echo "==================="
    echo ""

    test_validation
    echo ""
    test_rename
    echo ""
    test_dry_run
    echo ""
    test_cli_help

    echo ""
    echo "-------------------"
    echo "Results: ${_pass} passed, ${_fail} failed"

    if (( _fail > 0 )); then
        exit 1
    fi
}

main
