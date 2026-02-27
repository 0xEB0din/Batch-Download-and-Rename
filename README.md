# Batch Download & Rename

A modular Bash toolkit for bulk file acquisition and systematic renaming. Built to handle the real-world scenario of downloading hundreds of files from a remote server and organizing them with human-readable names — without reaching for Python or Node when the shell is enough.

## Why this exists

I needed to pull 92 PDFs off an internal server and rename each one from its cryptic server-side filename (`a8f3e2.pdf`) to something meaningful (`Q3-2024-Security-Audit.pdf`). Every existing tool either required a runtime I didn't want to install on the target machine, or couldn't handle the parallel-list rename pattern I needed. Two scripts later, this grew into a proper toolkit.

## Quick start

```bash
# Clone
git clone https://github.com/0xEB0din/Batch-Download-and-Rename.git
cd Batch-Download-and-Rename

# Download files from a URL list
./batch-dl -i urls.txt -o ./downloads

# Rename them using a name mapping
./batch-rename -f filenames.txt -m names.txt -s ./downloads -o ./final

# Preview what would happen without touching anything
./batch-dl -i urls.txt --dry-run
./batch-rename -f filenames.txt -m names.txt --dry-run
```

## Installation

```bash
# Option 1: Run directly from the repo (no install needed)
chmod +x batch-dl batch-rename

# Option 2: Install system-wide
sudo make install

# Option 3: Install to user directory
make install PREFIX=~/.local
```

## Architecture

```
.
├── batch-dl               # CLI entry point — download orchestrator
├── batch-rename           # CLI entry point — rename orchestrator
├── lib/
│   ├── logging.sh         # Structured logging (severity levels, file + stderr output)
│   ├── validation.sh      # Input sanitization, path traversal guards, URL validation
│   ├── download.sh        # Download engine (retry, checksum, timeout management)
│   └── rename.sh          # Rename engine (collision detection, manifest, dry-run)
├── config/
│   └── batch-dl.conf.example
├── examples/              # Sample input files for testing
├── tests/
│   └── run_tests.sh       # Test suite (validation, rename, dry-run, CLI)
├── Makefile
└── LICENSE
```

**Design decisions:**

- **Library pattern over monolith.** Each concern (logging, validation, download, rename) is a separate sourced module. This keeps individual files testable and makes it straightforward to reuse `lib/validation.sh` in other scripts without pulling in download logic.
- **No `cd` inside loops.** The original version used `cd output/ && mv ... && cd ../` in the rename loop — a well-known anti-pattern that breaks silently if the `cd` fails. All file operations now use absolute or resolved paths.
- **Copy-to-output, don't rename-in-place.** Source files are never modified. Renamed copies go to a separate output directory. This is intentional — destructive renames on a batch of 92 files with no undo is not a risk I want to take.
- **Source guards on library files.** Each `lib/*.sh` file tracks whether it's been sourced and returns early on re-inclusion. This prevents `readonly` collisions when multiple modules share a dependency.

## Usage

### `batch-dl` — Batch downloader

```
Usage: batch-dl [OPTIONS] -i <url-list> [-o <output-dir>]

Required:
  -i, --input FILE        File containing one URL per line

Options:
  -o, --output DIR        Output directory (default: ./downloads)
  -c, --checksums FILE    SHA-256 checksum file for verification
  -r, --retries N         Max retry attempts per file (default: 3)
  -t, --timeout N         Read timeout in seconds (default: 30)
  -d, --delay N           Initial retry delay in seconds (default: 2)
  -l, --log FILE          Write logs to file
  -n, --dry-run           Show what would be downloaded without downloading
  -k, --insecure          Skip TLS certificate verification
  -q, --quiet             Suppress terminal output
  -v, --verbose           Enable debug-level logging
```

**Input format** — one URL per line, blank lines and `#` comments are ignored:

```
# Internal reports server
https://reports.internal/files/a8f3e2.pdf
https://reports.internal/files/b7d1c9.pdf
https://reports.internal/files/c4e6a1.pdf
```

**Checksum verification** — provide a `sha256sum`-compatible file:

```bash
# Generate checksums from known-good copies
sha256sum *.pdf > checksums.sha256

# Download with verification
./batch-dl -i urls.txt -o ./downloads -c checksums.sha256
```

### `batch-rename` — Batch renamer

```
Usage: batch-rename [OPTIONS] -f <file-list> -m <name-map> [-s <source-dir>] [-o <output-dir>]

Required:
  -f, --files FILE        Source filenames (one per line)
  -m, --map FILE          Target names (one per line, same order as --files)

Options:
  -s, --source DIR        Directory containing source files (default: ./)
  -o, --output DIR        Output directory for renamed copies (default: ./output)
  -e, --ext EXT           Override output extension (e.g., pdf)
  -p, --preserve-ext      Preserve original file extension
  -F, --force             Overwrite existing files in output directory
  -n, --dry-run           Show rename plan without executing
  -l, --log FILE          Write logs to file
  -q, --quiet             Suppress terminal output
  -v, --verbose           Enable debug-level logging
```

**Parallel-list mapping** — line N of `--files` maps to line N of `--map`:

```
# files.txt          # names.txt
a8f3e2.pdf           Q3 2024 Security Audit
b7d1c9.pdf           Q3 2024 Penetration Test Results
c4e6a1.pdf           Q3 2024 Compliance Report
```

**Audit trail** — every batch rename writes a `.rename-manifest.csv` to the output directory:

```csv
timestamp,source,target
2024-07-21T14:02:17+0000,a8f3e2.pdf,Q3 2024 Security Audit.pdf
2024-07-21T14:02:17+0000,b7d1c9.pdf,Q3 2024 Penetration Test Results.pdf
```

## Testing

```bash
# Run the full test suite
make test

# Or directly
bash tests/run_tests.sh

# Lint with shellcheck
make lint

# Both
make check
```

The test suite covers: filename validation (path traversal, metacharacters, empty names), URL scheme validation, batch rename operations, content integrity after rename, manifest generation, dry-run isolation, and CLI argument handling.

## Security considerations

This tool was written with a defensive mindset. Here's what's covered and what isn't.

**Implemented:**

- **Path traversal prevention.** Filenames containing `..`, absolute paths, or directory separators are rejected before any file operation.
- **Shell metacharacter blocking.** Filenames with `;`, `|`, `&`, `$`, backticks, or braces are rejected to prevent injection through crafted filenames.
- **URL scheme allowlisting.** Only `http`, `https`, `ftp`, and `ftps` schemes are permitted. `file://`, `data:`, and other potentially dangerous schemes are blocked.
- **Filename length enforcement.** Names exceeding 255 characters (common filesystem limit) are rejected.
- **All variables are quoted.** No unquoted expansions anywhere — safe with filenames containing spaces and special characters.
- **Strict mode.** All scripts run with `set -euo pipefail` — undefined variables, failed commands, and broken pipes are caught immediately.
- **Non-destructive by default.** Source files are copied, never moved or modified. Collision detection prevents silent overwrites.
- **Checksum verification.** Optional SHA-256 verification of downloaded files against a known-good manifest.
- **TLS by default.** Certificate verification is on by default; `--insecure` must be explicitly passed and is logged as a warning.

**Not yet implemented (see Roadmap):**

- No sandboxing of download targets — a malicious redirect could write to unexpected paths within the output directory.
- No rate limiting — rapid downloads may trigger server-side throttling or bans.
- No GPG signature verification — checksums prove integrity but not authenticity.
- wget inherits ambient proxy and credential configuration — no isolation from the host environment.
- No file-type verification — a server could return HTML (e.g., a login page) in place of the expected PDF and the tool would save it without complaint.

## Limitations & tradeoffs

| Decision | Tradeoff | Rationale |
|----------|----------|-----------|
| Bash-only, no external runtime | Limited to what coreutils + wget provide | Zero-dependency portability; runs on any Linux/macOS box without installing Python/Node |
| Sequential downloads | Slower on large batches | Simpler to reason about, avoids overwhelming the target server, easier to debug failures |
| Copy-to-output (not in-place rename) | Uses 2x disk space during rename | Non-destructive; originals are always preserved; safer for irreversible operations |
| Parallel file mapping (not CSV/JSON) | Two files to maintain instead of one | Simpler parsing, no CSV escaping edge cases, easier to generate from shell pipes |
| wget over curl | curl has better error reporting and HTTP/2 | wget handles recursive downloads better; `--output-document` semantics are cleaner for this use case |
| No parallel downloads | Doesn't saturate bandwidth | Predictable ordering, log readability, no partial-file interleaving |

## Roadmap

Planned improvements — contributions welcome:

- [ ] **Parallel downloads** — configurable worker pool using `xargs -P` or `GNU parallel`
- [ ] **Resume support** — skip files that already exist in the output directory (with optional checksum re-verification)
- [ ] **CSV/TSV mapping input** — single-file rename mapping as an alternative to parallel lists
- [ ] **Content-type validation** — verify downloaded files match expected MIME types before saving
- [ ] **Rate limiting** — configurable delay between downloads to avoid server throttling
- [ ] **GPG signature verification** — verify file authenticity alongside integrity
- [ ] **Progress bar** — visual progress indicator for large batches (terminal-aware)
- [ ] **Undo/rollback** — use the rename manifest to reverse a batch operation
- [ ] **Config file support** — load defaults from `~/.config/batch-dl/batch-dl.conf`
- [ ] **macOS compatibility testing** — verify GNU coreutils vs. BSD coreutils edge cases
- [ ] **CI pipeline** — GitHub Actions workflow for shellcheck + test suite on push

## Dependencies

- **bash** >= 4.0
- **wget** (download mode)
- **coreutils** — `cp`, `mv`, `mkdir`, `basename`, `dirname`, `date`, `sha256sum`
- **grep** (input file parsing)
- Optional: **shellcheck** (for `make lint`)

## License

MIT — see [LICENSE](LICENSE).
