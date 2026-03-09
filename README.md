# bookf — Komga Book Metadata Fetcher

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/shell-bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Calibre](https://img.shields.io/badge/requires-calibre-green.svg)](https://calibre-ebook.com/)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](https://www.linux.org/)
[![Komga](https://img.shields.io/badge/integrates%20with-Komga-orange.svg)](https://komga.org/)

> Automatically fetch and embed book descriptions into EPUB, MOBI, AZW3, and KEPUB files so that **Komga** displays rich summaries for your novel and non-fiction library — using nothing but **Calibre CLI** and its built-in metadata sources (Google Books, Amazon, Open Library, and more). Optionally extends to **Goodreads** via a third-party Calibre plugin for better coverage of novels and series.

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
- [Customization](#customization)
- [Optional: Adding Goodreads as a metadata source](#optional-adding-goodreads-as-a-metadata-source)
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
3. Queries multiple sources via Calibre's `fetch-ebook-metadata` (Google Books, Amazon, Open Library, Edelweiss, Big Book Search — all active by default; Goodreads available as an optional plugin)
4. Writes **only** the description (summary) back into the file — leaving every other field untouched
5. Results are immediately visible after a Komga library scan

No database. No daemon. No configuration files. One script, one command.

---

## How it works

```
ebook file  ──►  ebook-meta (read title + author)
                      │
                      ▼
              fetch-ebook-metadata (Google Books, Amazon, Open Library, …)
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

## Customization

---

## Optional: Adding Goodreads as a metadata source

By default, bookf uses Calibre's built-in metadata sources: Google Books, Amazon, Open Library, Edelweiss, and Big Book Search. These cover most books well — but for novels, especially series, **Goodreads** often has better descriptions and more accurate series information.

Calibre supports third-party metadata plugins. The Goodreads plugin by **kiwidude68** works via scraping and is actively maintained with support for Calibre 6.x and newer.

> [!NOTE]
> Once installed, the Goodreads plugin is used automatically by `fetch-ebook-metadata` alongside the built-in sources. No changes to `bookf.sh` are needed.

### Install the Goodreads plugin

**Step 1 — Download the plugin**

Download `Goodreads.zip` from the [Calibre plugin index](https://plugins.calibre-ebook.com/):

1. Open https://plugins.calibre-ebook.com/ in your browser
2. Search for **Goodreads**
3. Click **Download plugin** on the metadata plugin row (not the Sync plugin)
4. Save the file to your Downloads folder

**Step 2 — Install the plugin**

```bash
calibre-customize -a /path/to/Goodreads.zip
```

Replace `/path/to/Goodreads.zip` with the actual path to the downloaded file. Example:

```bash
# Linux default Downloads folder
calibre-customize -a ~/Downloads/Goodreads.zip

# If you copied it to /tmp
calibre-customize -a /tmp/Goodreads.zip
```

**Step 3 — Verify the installation**

```bash
fetch-ebook-metadata --help | grep -i goodreads
```

Expected output:

```
plugin names: Goodreads, Google, Google Images,
```

If `Goodreads` appears in the list, the plugin is active and will be used automatically on the next run.

### Re-run bookf to pick up missed books

After installing the plugin, run bookf again without `--force` — it will skip books that already have a description and only retry those that previously failed:

```bash
./bookf.sh --dir /srv/books
```

Or in the background for large libraries:

```bash
nohup ./bookf.sh --dir /srv/books >> /tmp/update-book-metadata.log 2>&1 &
tail -f /tmp/update-book-metadata.log
```

### Docker: installing the plugin inside the container

If you use the Docker Compose setup, add the plugin installation step to the Dockerfile or entrypoint so it runs before bookf.

> [!NOTE]
> The plugin index page at `https://plugins.calibre-ebook.com/` serves an HTML page, not a direct ZIP download. There is no stable direct URL to automate this step. To install the plugin in a container, either:
> - Download the ZIP manually (as described in Step 1 above) and copy it into the image: `COPY Goodreads.zip /tmp/`
> - Or host the ZIP file yourself and `wget` from your own URL
>
> Then install with:
> ```bash
> calibre-customize -a /tmp/Goodreads.zip && rm /tmp/Goodreads.zip
> ```

---

### Changing the default library path

The script defaults to `/mnt/synology_komga`. You do not need to edit the script itself — use `--dir` on the command line:

```bash
./bookf.sh --dir /srv/books
./bookf.sh --dir /home/user/Calibre\ Library
./bookf.sh --dir "/media/nas/ebooks"
```

To make a path permanent without re-typing it every run, create a small wrapper script:

```bash
#!/usr/bin/env bash
exec /path/to/bookf.sh --dir /srv/books "$@"
```

Save it as e.g. `~/bin/bookf`, make it executable (`chmod +x ~/bin/bookf`), and run `bookf` from anywhere.

### Changing the default path in the script itself

If you always use the same machine and path, you can edit the default directly in `bookf.sh`. Find the line near the top that reads:

```bash
BOOK_ROOT="/mnt/synology_komga"
```

and change it to your own path:

```bash
BOOK_ROOT="/srv/books"
```

After that, running `./bookf.sh` without any flags will use your path.

### Docker: setting the library path

In the Docker Compose setup, set the `BOOK_ROOT` environment variable and update the volume mount:

```yaml
environment:
  - BOOK_ROOT=/books

volumes:
  - .:/bookf
  - /srv/books:/books   # ← change the left side to your host path
```

Or pass it on the command line without editing the file:

```bash
BOOK_ROOT=/books docker compose up
```

### Docker: using an NFS or SMB mount

If your library lives on a NAS mounted on the host (e.g. via `/etc/fstab` or `autofs`), just point the left side of the volume at the mount point:

```yaml
volumes:
  - /mnt/nas/ebooks:/books
```

No extra Docker configuration is needed — the container sees the files through the host mount.

### Running on a schedule (cron)

To run bookf automatically (e.g. every night at 02:00):

```bash
crontab -e
```

Add a line like:

```
0 2 * * * /path/to/bookf.sh --dir /srv/books >> /tmp/update-book-metadata.log 2>&1
```

For Docker:

```
0 2 * * * docker compose -f /opt/bookf/docker-compose.yml up >> /tmp/bookf-docker.log 2>&1
```

### Adjusting the sleep delay between requests

The script sleeps 1 second between API calls to avoid hammering remote servers. If your library is very large and you want to speed things up (at the risk of occasional rate-limit errors), edit `bookf.sh` and change:

```bash
sleep 1
```

to a shorter value, e.g. `sleep 0.3`. Values below 0.3 seconds are not recommended.

---

## Known limitations

| Limitation | Detail |
|------------|--------|
| Books not indexed online | If a book is not found in any of Calibre's metadata sources (Google Books, Amazon, Open Library, Edelweiss, Big Book Search), `fetch-ebook-metadata` returns nothing and the file is skipped silently. Check the log for `FAILED` lines. |
| Books not indexed by built-in sources | If a book is missing from Google Books, Amazon, and Open Library, installing the optional Goodreads plugin (see [Optional: Adding Goodreads as a metadata source](#optional-adding-goodreads-as-a-metadata-source)) often resolves this for novels and series. |
| Multiple formats of the same book | If you have `book.epub`, `book.kepub`, and `book.mobi` for the same title, each file is processed and updated individually. This is intentional — each format is a self-contained file. |
| Counter variables | The script uses process substitution (`< <(find …)`) to keep the loop in the current shell, so `Processed/Updated/Skipped/Failed` counts are accurate. If you run on a shell that does not support process substitution (e.g. `/bin/sh`), use `grep -c` on the log file instead (see [Monitoring progress](#monitoring-progress)). |
| Rate limiting | The script sleeps 1 second between requests to be polite to remote APIs. For very large libraries this means the run can take a long time. |
| Requires write access | The script modifies files in place. Ensure the user running the script has write permission on the library directory. |
| No ISBN-based lookup | Lookups are done by title + author. ISBN-based lookup (more accurate) is not yet implemented. |

---

## Comparison to komf

| Feature | **bookf** | **[komf](https://github.com/Snd-R/komf)** |
|---------|-----------|------------------------------------------|
| Target content | Novels, non-fiction ebooks | Manga, comics, webtoons |
| Metadata sources | Google Books, Amazon, Open Library, Edelweiss, Big Book Search (built-in); Goodreads (optional plugin) | MangaUpdates, AniList, MyAnimeList, etc. |
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
