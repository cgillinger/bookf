# bookf — Komga Book Metadata Fetcher

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/shell-bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Calibre](https://img.shields.io/badge/requires-calibre-green.svg)](https://calibre-ebook.com/)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](https://www.linux.org/)
[![Komga](https://img.shields.io/badge/integrates%20with-Komga-orange.svg)](https://komga.org/)

> Automatically fetch and embed book descriptions into EPUB, MOBI, AZW3, and KEPUB files so that **Komga** displays rich summaries for your novel and non-fiction library — using nothing but **Calibre CLI** and Google Books / Amazon as metadata sources.

---

## Table of Contents

- [Why bookf exists](#why-bookf-exists)
- [How it works](#how-it-works)
- [Supported formats](#supported-formats)
- [Requirements](#requirements)
- [Installing Calibre](#installing-calibre)
- [Installation](#installation)
- [Usage](#usage)
- [Running in the background](#running-in-the-background)
- [Monitoring progress](#monitoring-progress)
- [After the run — trigger Komga scan](#after-the-run--trigger-komga-scan)
- [Docker / Docker Compose](#docker--docker-compose)
- [Known limitations](#known-limitations)
- [Comparison to komf](#comparison-to-komf)
- [License](#license)

---

## Why bookf exists

[Komga](https://komga.org/) is an excellent self-hosted media server for ebooks and comics. It reads metadata embedded directly in the ebook files. For **manga and comics** there is already a great tool called **[komf](https://github.com/Snd-R/komf)** that pulls metadata from MangaUpdates, AniList, and similar sources.

For **novels and non-fiction books**, however, no equivalent automation tool existed — descriptions (summaries) were often missing entirely from the Komga UI, making it hard to browse your library.

**bookf** fills that gap. It is a focused, dependency-light Bash script that:

1. Walks your ebook library directory
2. Reads the title and author already embedded in each file
3. Queries Google Books and Amazon via Calibre's `fetch-ebook-metadata`
4. Writes **only** the description (summary) back into the file — leaving every other field untouched
5. Results are immediately visible after a Komga library scan

No database. No daemon. No configuration files. One script, one command.

---

## How it works

```
ebook file  ──►  ebook-meta (read title + author)
                      │
                      ▼
              fetch-ebook-metadata (Google Books / Amazon)
                      │
                      ▼
              parse description from OPF XML  (Python 3 one-liner)
                      │
                      ▼
              ebook-meta --comments "…"  (write only description)
                      │
                      ▼
              Komga library scan  ──►  description visible in UI
```

The script uses **only** the `--comments` field when writing back to the file. It does **not** touch the title, author, series, ISBN, cover image, or any other field.

> [!WARNING]
> Even though only the description field is written, you are modifying binary ebook files in place. **Always run with `--dry-run` first** to verify what will be changed, and **make a backup of your library** before the first real run. A bug, a crash, or a full disk mid-write can corrupt a file. Once overwritten, the original is gone.

---

## Supported formats

| Format | Extension | Notes |
|--------|-----------|-------|
| EPUB   | `.epub`   | Most common; fully supported |
| MOBI   | `.mobi`   | Kindle legacy format |
| AZW3   | `.azw3`   | Kindle current format |
| KEPUB  | `.kepub`  | Kobo-enhanced EPUB |

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| Linux / Ubuntu (or WSL2) | The script uses standard POSIX tools |
| [Calibre](https://calibre-ebook.com/) ≥ 6.x | Provides `ebook-meta` and `fetch-ebook-metadata` |
| Python 3 | Ships with Ubuntu; used to parse the OPF XML response |
| Read-write access to your ebook library directory | Required to write the description back into each file |

See [Installing Calibre](#installing-calibre) below for platform-specific instructions.

Verify the required tools are available after installation:

```bash
which ebook-meta fetch-ebook-metadata
```

---

## Installing Calibre

The script checks for `ebook-meta` and `fetch-ebook-metadata` at startup and exits immediately with a clear error message if either is missing.

### Ubuntu / Debian

```bash
sudo apt update && sudo apt install calibre
```

### Other Linux (no apt — standalone installer)

Works on any Linux distribution without root access to a package manager:

```bash
wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sh /dev/stdin
```

This installs Calibre to `~/calibre-bin` and adds the tools to your `PATH` automatically.

### macOS

```bash
brew install calibre
```

### Synology NAS / Unraid / other NAS systems

Installing Calibre natively on these systems is non-trivial and not recommended. Use the included **Docker Compose** setup instead — it handles the Calibre installation automatically inside the container and requires no changes to the host system. See [Docker / Docker Compose](#docker--docker-compose).

---

## Installation

```bash
# Clone the repository
git clone https://github.com/cgillinger/bookf.git
cd bookf

# Make the script executable
chmod +x bookf.sh

# Optional: install system-wide
sudo cp bookf.sh /usr/local/bin/bookf
```

---

## Usage

```
bookf.sh [--dry-run] [--force] [--dir /path/to/library]
```

| Flag | Description |
|------|-------------|
| *(no flags)* | Process all ebooks under `/mnt/synology_komga` that have no description yet |
| `--dry-run` | Scan and log what *would* be done — no files are modified |
| `--force` | Re-fetch and overwrite descriptions even if a description already exists |
| `--dir /path` | Override the default library root path |

### Examples

```bash
# Preview what would be updated (safe — no writes)
./bookf.sh --dry-run --dir /srv/books

# Update only books that are missing a description
./bookf.sh --dir /srv/books

# Force-refresh descriptions for every book in the library
./bookf.sh --force --dir /srv/books

# Use the default path (/mnt/synology_komga)
./bookf.sh
```

---

## Running in the background

For large libraries, run the script detached so it survives terminal disconnects:

```bash
nohup ./bookf.sh --dir /srv/books >> /tmp/update-book-metadata.log 2>&1 &
echo "PID: $!"
```

---

## Monitoring progress

```bash
# Live log stream
tail -f /tmp/update-book-metadata.log

# Count successful updates so far
grep -c "OK Description" /tmp/update-book-metadata.log

# Count failures
grep -c "FAILED\|SKIP" /tmp/update-book-metadata.log

# See the last 20 lines
tail -20 /tmp/update-book-metadata.log
```

Log line examples:

```
[2025-06-01 14:32:11] Processing: project-hail-mary.epub ("Project Hail Mary" by Andy Weir)
[2025-06-01 14:32:13]   OK Description updated (842 chars)
[2025-06-01 14:32:14] SKIP (has description): dune.epub
[2025-06-01 14:32:15]   FAILED fetch-ebook-metadata for "Unknown Self-Published Title"
```

---

## After the run — trigger Komga scan

Once the script finishes, trigger a library rescan so Komga picks up the new descriptions.

### Via the Komga web UI

`Administration` → `Libraries` → click the **Scan** button next to your library.

### Via the REST API

```bash
curl -u admin:YOUR_PASSWORD \
     -X POST \
     "http://YOUR_KOMGA_HOST:8342/api/v1/libraries/YOUR_LIBRARY_ID/scan"
```

Replace `YOUR_PASSWORD`, `YOUR_KOMGA_HOST`, and `YOUR_LIBRARY_ID` with your actual values. The library ID is visible in the URL when you open the library in the Komga web UI.

---

## Docker / Docker Compose

For environments where you prefer not to install Calibre on the host, a `docker-compose.yml` is included.

```bash
# Edit docker-compose.yml to set your library path, then:
docker compose up
```

The container installs Calibre, mounts your library, runs the script, and exits. Your ebook files are modified in place on the host volume.

See [`docker-compose.yml`](docker-compose.yml) for the full configuration and inline comments.

---

## Known limitations

| Limitation | Detail |
|------------|--------|
| Books not indexed online | If a book is not in Google Books or Amazon, `fetch-ebook-metadata` returns nothing and the file is skipped silently. Check the log for `FAILED` lines. |
| Multiple formats of the same book | If you have `book.epub`, `book.kepub`, and `book.mobi` for the same title, each file is processed and updated individually. This is intentional — each format is a self-contained file. |
| Counter variables show `0` at end | The `find … | while` construct runs the loop body in a subshell, so counter increments are not visible in the parent shell. The final `Processed/Updated/Skipped/Failed` line will show `0`. Use `grep -c` on the log file to get accurate counts (see [Monitoring progress](#monitoring-progress)). |
| Rate limiting | The script sleeps 1 second between requests to be polite to remote APIs. For very large libraries this means the run can take a long time. |
| Requires write access | The script modifies files in place. Ensure the user running the script has write permission on the library directory. |
| No ISBN-based lookup | Lookups are done by title + author. ISBN-based lookup (more accurate) is not yet implemented. |

---

## Comparison to komf

| Feature | **bookf** | **[komf](https://github.com/Snd-R/komf)** |
|---------|-----------|------------------------------------------|
| Target content | Novels, non-fiction ebooks | Manga, comics, webtoons |
| Metadata sources | Google Books, Amazon (via Calibre) | MangaUpdates, AniList, MyAnimeList, etc. |
| Supported formats | EPUB, MOBI, AZW3, KEPUB | CBZ, CBR, PDF |
| Writes to | Ebook file directly (`ebook-meta`) | Komga API + ComicInfo.xml |
| Architecture | Single Bash script, no daemon | Long-running JVM service |
| Requirements | Calibre, Python 3 | Java 17+, Komga API access |
| Series / volume handling | Not applicable | First-class feature |

Both tools are complementary and can run side-by-side on the same Komga server — komf handles your manga library while bookf handles your novel and non-fiction library.

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

*Made for self-hosters who want their Komga book library to look as good as their manga shelf.*
