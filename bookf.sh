#!/usr/bin/env bash
# bookf.sh
# Populates the description field in e-books using the Calibre CLI
# Reads/writes the ebook library via the path specified by --dir (default: /mnt/synology_komga)
#
# Syntax: ./bookf.sh [--dry-run] [--force] [--dir /path]

set -euo pipefail

BOOK_ROOT="/mnt/synology_komga"
TMP_META=$(mktemp /tmp/meta_XXXXXX.opf)
LOG_FILE="/tmp/update-book-metadata.log"
DRY_RUN=false
FORCE=false
PROCESSED=0
UPDATED=0
SKIPPED=0
FAILED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        --dir)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "ERROR: --dir requires a path argument"; exit 1
            fi
            BOOK_ROOT="$2"; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

if [[ ! -d "$BOOK_ROOT" ]]; then
    echo "ERROR: Library directory not found: $BOOK_ROOT"
    exit 1
fi

cleanup() { rm -f "$TMP_META"; }
trap cleanup EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

for tool in ebook-meta fetch-ebook-metadata; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: $tool not found. Run: sudo apt install calibre"
        exit 1
    fi
done

log "=== Starting metadata update ==="
log "Root: $BOOK_ROOT | dry-run: $DRY_RUN | force: $FORCE"

while IFS= read -r -d '' file; do

    PROCESSED=$((PROCESSED + 1))
    fname=$(basename "$file")

    if [ "$FORCE" = false ]; then
        existing=$(ebook-meta "$file" 2>/dev/null | grep -i "^Comments" | head -1 || true)
        if [ -n "$existing" ]; then
            log "SKIP (has description): $fname"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi

    meta_out=$(ebook-meta "$file" 2>/dev/null || true)
    title=$(echo "$meta_out" | grep "^Title " | sed 's/^Title *: //' | head -1)
    author=$(echo "$meta_out" | grep "^Author(s)" | sed 's/^Author(s) *: //' | sed 's/ \[.*\]//' | head -1)

    if [ -z "$title" ] || [ -z "$author" ]; then
        log "SKIP (missing title/author in file): $fname"
        FAILED=$((FAILED + 1))
        continue
    fi

    log "Processing: $fname (\"$title\" by $author)"

    if [ "$DRY_RUN" = true ]; then
        log "  [dry-run] Would search: title=\"$title\" author=\"$author\""
        continue
    fi

    if fetch-ebook-metadata --opf --title "$title" --authors "$author" > "$TMP_META" 2>/dev/null; then
        desc=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$TMP_META')
    ns = {'dc': 'http://purl.org/dc/elements/1.1/'}
    el = tree.find('.//dc:description', ns)
    print(el.text.strip() if el is not None and el.text else '')
except Exception:
    print('')
")
        if [ -n "$desc" ]; then
            ebook-meta "$file" --comments "$desc" > /dev/null 2>&1
            log "  OK Description updated (${#desc} chars)"
            UPDATED=$((UPDATED + 1))
        else
            log "  -- No description in response"
            FAILED=$((FAILED + 1))
        fi
    else
        log "  FAILED fetch-ebook-metadata for \"$title\""
        FAILED=$((FAILED + 1))
    fi

    sleep 1

done < <(find "$BOOK_ROOT" -type f \( -iname "*.epub" -o -iname "*.mobi" -o -iname "*.azw3" -o -iname "*.kepub" \) -print0)

log "=== Done ==="
log "Processed: $PROCESSED | Updated: $UPDATED | Skipped: $SKIPPED | Failed: $FAILED"
echo ""
echo "Trigger Komga library scan:"
echo "  curl -u admin:PASSWORD -X POST http://YOUR_KOMGA_IP:8342/api/v1/libraries/LIBRARY_ID/scan"

if [[ $FAILED -gt 0 ]]; then
    exit 2
fi
exit 0
