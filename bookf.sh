#!/usr/bin/env bash
# bookf.sh
# Populates metadata fields in e-books using the Calibre CLI
# Reads/writes the ebook library via the path specified by --dir (default: /mnt/synology_komga)
#
# Syntax: ./bookf.sh [--dry-run] [--force] [--dir /path] [--config /path]

set -euo pipefail

BOOK_ROOT="/mnt/synology_komga"
TMP_META=$(mktemp /tmp/meta_XXXXXX.opf)
TMP_COVER=""
LOG_FILE="/tmp/update-book-metadata.log"
DRY_RUN=false
FORCE=false
CONFIG_PATH=""
PROCESSED=0
UPDATED=0
SKIPPED=0
FAILED=0

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        --dir)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "ERROR: --dir requires a path argument"; exit 1
            fi
            BOOK_ROOT="$2"; shift ;;
        --config)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "ERROR: --config requires a path argument"; exit 1
            fi
            CONFIG_PATH="$2"; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

if [[ ! -d "$BOOK_ROOT" ]]; then
    echo "ERROR: Library directory not found: $BOOK_ROOT"
    exit 1
fi

# --------------------------------------------------------------------------
# Cleanup
# --------------------------------------------------------------------------

cleanup() {
    rm -f "$TMP_META"
    [[ -n "$TMP_COVER" ]] && rm -f "$TMP_COVER"
}
trap cleanup EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# --------------------------------------------------------------------------
# Config defaults
# --------------------------------------------------------------------------

CFG_description="empty"
CFG_cover="no"
CFG_publisher="no"
CFG_tags="no"
CFG_series="no"
CFG_isbn="no"
CFG_language="no"
CFG_date="no"
CFG_sources="all"

KNOWN_KEYS="description cover publisher tags series isbn language date sources"

validate_field_value() {
    local key="$1" val="$2"
    if [[ "$key" != "sources" ]]; then
        case "$val" in
            no|empty|overwrite) ;;
            *) echo "ERROR: Invalid value '$val' for key '$key' in config. Must be: no, empty, or overwrite"; exit 1 ;;
        esac
    fi
}

# --------------------------------------------------------------------------
# Config loading
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_LOADED=""

if [[ -n "$CONFIG_PATH" ]]; then
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "ERROR: Config file not found: $CONFIG_PATH"; exit 1
    fi
    CONFIG_LOADED="$CONFIG_PATH"
elif [[ -f "$SCRIPT_DIR/bookf.conf" ]]; then
    CONFIG_LOADED="$SCRIPT_DIR/bookf.conf"
elif [[ -f "${HOME}/.config/bookf/bookf.conf" ]]; then
    CONFIG_LOADED="${HOME}/.config/bookf/bookf.conf"
fi

if [[ -n "$CONFIG_LOADED" ]]; then
    while IFS='=' read -r key val; do
        # Strip inline comments and whitespace
        key="${key%%#*}"
        key="${key// /}"
        key="${key//	/}"
        val="${val%%#*}"
        val="${val## }"
        val="${val%% }"
        val="${val//	/}"
        [[ -z "$key" || -z "$val" ]] && continue

        known=false
        for k in $KNOWN_KEYS; do
            [[ "$key" == "$k" ]] && known=true && break
        done
        if [[ "$known" == false ]]; then
            log "WARN: Unknown config key '$key' — skipping"
            continue
        fi

        validate_field_value "$key" "$val"

        case "$key" in
            description) CFG_description="$val" ;;
            cover)       CFG_cover="$val" ;;
            publisher)   CFG_publisher="$val" ;;
            tags)        CFG_tags="$val" ;;
            series)      CFG_series="$val" ;;
            isbn)        CFG_isbn="$val" ;;
            language)    CFG_language="$val" ;;
            date)        CFG_date="$val" ;;
            sources)     CFG_sources="$val" ;;
        esac
    done < <(grep -v '^\s*#' "$CONFIG_LOADED" | grep '=')
    log "Config loaded: $CONFIG_LOADED"
else
    log "Config: using defaults (no bookf.conf found)"
fi

# --force overrides all enabled fields to overwrite
if [[ "$FORCE" == true ]]; then
    log "WARN: --force is set — all enabled fields treated as 'overwrite' for this run"
    [[ "$CFG_description" != "no" ]] && CFG_description="overwrite"
    [[ "$CFG_cover"       != "no" ]] && CFG_cover="overwrite"
    [[ "$CFG_publisher"   != "no" ]] && CFG_publisher="overwrite"
    [[ "$CFG_tags"        != "no" ]] && CFG_tags="overwrite"
    [[ "$CFG_series"      != "no" ]] && CFG_series="overwrite"
    [[ "$CFG_isbn"        != "no" ]] && CFG_isbn="overwrite"
    [[ "$CFG_language"    != "no" ]] && CFG_language="overwrite"
    [[ "$CFG_date"        != "no" ]] && CFG_date="overwrite"
fi

# --------------------------------------------------------------------------
# Log field plan
# --------------------------------------------------------------------------

log "Field plan: description=$CFG_description cover=$CFG_cover publisher=$CFG_publisher tags=$CFG_tags series=$CFG_series isbn=$CFG_isbn language=$CFG_language date=$CFG_date sources=$CFG_sources"

# --------------------------------------------------------------------------
# Tool check
# --------------------------------------------------------------------------

for tool in ebook-meta fetch-ebook-metadata python3; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: $tool not found. Run: sudo apt install calibre"
        exit 1
    fi
done

log "=== Starting metadata update ==="
log "Root: $BOOK_ROOT | dry-run: $DRY_RUN | force: $FORCE"

# --------------------------------------------------------------------------
# Build --allowed-plugin args for fetch-ebook-metadata
# --------------------------------------------------------------------------

FETCH_PLUGIN_ARGS=()
if [[ "$CFG_sources" != "all" ]]; then
    IFS=',' read -ra _sources <<< "$CFG_sources"
    for _src in "${_sources[@]}"; do
        _src="${_src## }"
        _src="${_src%% }"
        [[ -n "$_src" ]] && FETCH_PLUGIN_ARGS+=(--allowed-plugin "$_src")
    done
fi

# --------------------------------------------------------------------------
# Helper: check if a field is currently empty in the file
# --------------------------------------------------------------------------

field_is_empty() {
    local file="$1" label="$2"
    local val
    val=$(ebook-meta "$file" 2>/dev/null | grep -i "^${label}" | head -1 || true)
    # Strip the "Label   : " prefix and check if anything remains
    val=$(echo "$val" | sed 's/^[^:]*:[[:space:]]*//')
    [[ -z "$val" ]]
}

# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------

while IFS= read -r -d '' file; do

    PROCESSED=$((PROCESSED + 1))
    fname=$(basename "$file")

    meta_out=$(ebook-meta "$file" 2>/dev/null || true)
    title=$(echo "$meta_out" | grep "^Title " | sed 's/^Title *: //' | head -1)
    author=$(echo "$meta_out" | grep "^Author(s)" | sed 's/^Author(s) *: //' | sed 's/ \[.*\]//' | head -1)

    if [[ -z "$title" || -z "$author" ]]; then
        log "SKIP (missing title/author in file): $fname"
        FAILED=$((FAILED + 1))
        continue
    fi

    log "Processing: $fname (\"$title\" by $author)"

    if [[ "$DRY_RUN" == true ]]; then
        log "  [dry-run] Would search: title=\"$title\" author=\"$author\""
        continue
    fi

    # Fetch OPF
    if ! fetch-ebook-metadata --opf --title "$title" --authors "$author" \
            "${FETCH_PLUGIN_ARGS[@]}" > "$TMP_META" 2>/dev/null; then
        log "  FAILED fetch-ebook-metadata for \"$title\""
        FAILED=$((FAILED + 1))
        sleep 1
        continue
    fi

    # -----------------------------------------------------------------------
    # Parse all fields from OPF in one Python pass
    # -----------------------------------------------------------------------
    opf_data=$(python3 - "$TMP_META" <<'PYEOF'
import sys, xml.etree.ElementTree as ET

opf_file = sys.argv[1]
try:
    tree = ET.parse(opf_file)
except Exception as e:
    sys.exit(0)

root = tree.getroot()
ns = {
    'dc':      'http://purl.org/dc/elements/1.1/',
    'opf':     'http://www.idpf.org/2007/opf',
    'calibre': 'http://calibre.kovidgoyal.net/2009/metadata',
}

def text(el):
    return (el.text or '').strip() if el is not None else ''

def find(path):
    return text(root.find('.//' + path, ns))

def findall(path):
    return [text(e) for e in root.findall('.//' + path, ns) if (e.text or '').strip()]

description = find('dc:description')
publisher   = find('dc:publisher')
language    = find('dc:language')
date        = find('dc:date')

tags = findall('dc:subject')

isbn = ''
for el in root.findall('.//dc:identifier', ns):
    scheme = el.get('{http://www.idpf.org/2007/opf}scheme', '')
    if scheme.upper() == 'ISBN':
        isbn = text(el)
        break

series = ''
series_index = ''
for meta in root.findall('.//opf:meta', ns):
    name = meta.get('name', '')
    if name == 'calibre:series':
        series = (meta.get('content') or '').strip()
    elif name == 'calibre:series_index':
        series_index = (meta.get('content') or '').strip()

cover_url = ''
for meta in root.findall('.//opf:meta', ns):
    if meta.get('name') == 'cover':
        cover_url = (meta.get('content') or '').strip()
        break
if not cover_url:
    for ref in root.findall('.//opf:reference', ns):
        if ref.get('type') == 'cover':
            cover_url = (ref.get('href') or '').strip()
            break

def emit(key, val):
    # Escape newlines in value so it fits on one line
    print(key + '=' + val.replace('\n', '\\n'))

emit('description', description)
emit('publisher',   publisher)
emit('language',    language)
emit('date',        date)
emit('isbn',        isbn)
emit('series',      series)
emit('series_index', series_index)
emit('tags',        ','.join(tags))
emit('cover_url',   cover_url)
PYEOF
)

    # Parse key=value pairs from Python output
    declare -A opf
    while IFS='=' read -r k v; do
        [[ -z "$k" ]] && continue
        opf["$k"]="$v"
    done <<< "$opf_data"

    # Restore newlines in description
    opf_description="${opf[description]:-}"
    opf_description="${opf_description//\\n/$'\n'}"

    EBOOK_META_ARGS=()
    WRITTEN_FIELDS=()

    # -----------------------------------------------------------------------
    # description
    # -----------------------------------------------------------------------
    if [[ "$CFG_description" != "no" && -n "$opf_description" ]]; then
        write=false
        if [[ "$CFG_description" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "Comments"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            EBOOK_META_ARGS+=(--comments "$opf_description")
            WRITTEN_FIELDS+=("description (${#opf_description} chars)")
        fi
    fi

    # -----------------------------------------------------------------------
    # publisher
    # -----------------------------------------------------------------------
    if [[ "$CFG_publisher" != "no" && -n "${opf[publisher]:-}" ]]; then
        write=false
        if [[ "$CFG_publisher" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "Publisher"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            EBOOK_META_ARGS+=(--publisher "${opf[publisher]}")
            WRITTEN_FIELDS+=("publisher")
        fi
    fi

    # -----------------------------------------------------------------------
    # tags
    # -----------------------------------------------------------------------
    if [[ "$CFG_tags" != "no" && -n "${opf[tags]:-}" ]]; then
        write=false
        if [[ "$CFG_tags" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "Tags"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            tag_count=$(echo "${opf[tags]}" | awk -F',' '{print NF}')
            EBOOK_META_ARGS+=(--tags "${opf[tags]}")
            WRITTEN_FIELDS+=("tags ($tag_count)")
        fi
    fi

    # -----------------------------------------------------------------------
    # series (coupled with series_index)
    # -----------------------------------------------------------------------
    if [[ "$CFG_series" != "no" && -n "${opf[series]:-}" ]]; then
        write=false
        if [[ "$CFG_series" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "Series"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            EBOOK_META_ARGS+=(--series "${opf[series]}")
            _idx="${opf[series_index]:-}"
            if [[ -n "$_idx" ]]; then
                EBOOK_META_ARGS+=(--index "$_idx")
                WRITTEN_FIELDS+=("series (#${_idx})")
            else
                WRITTEN_FIELDS+=("series")
            fi
        fi
    fi

    # -----------------------------------------------------------------------
    # isbn
    # -----------------------------------------------------------------------
    if [[ "$CFG_isbn" != "no" && -n "${opf[isbn]:-}" ]]; then
        write=false
        if [[ "$CFG_isbn" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "ISBN"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            EBOOK_META_ARGS+=(--isbn "${opf[isbn]}")
            WRITTEN_FIELDS+=("isbn")
        fi
    fi

    # -----------------------------------------------------------------------
    # language
    # -----------------------------------------------------------------------
    if [[ "$CFG_language" != "no" && -n "${opf[language]:-}" ]]; then
        write=false
        if [[ "$CFG_language" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "Languages"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            EBOOK_META_ARGS+=(--language "${opf[language]}")
            WRITTEN_FIELDS+=("language")
        fi
    fi

    # -----------------------------------------------------------------------
    # date
    # -----------------------------------------------------------------------
    if [[ "$CFG_date" != "no" && -n "${opf[date]:-}" ]]; then
        write=false
        if [[ "$CFG_date" == "overwrite" ]]; then
            write=true
        elif field_is_empty "$file" "Published"; then
            write=true
        fi
        if [[ "$write" == true ]]; then
            EBOOK_META_ARGS+=(--date "${opf[date]}")
            WRITTEN_FIELDS+=("date")
        fi
    fi

    # -----------------------------------------------------------------------
    # cover (downloaded separately — not via ebook-meta batch args)
    # -----------------------------------------------------------------------
    cover_written=false
    if [[ "$CFG_cover" != "no" && -n "${opf[cover_url]:-}" ]]; then
        TMP_COVER=$(mktemp /tmp/cover_XXXXXX.jpg)
        if curl -fsSL "${opf[cover_url]}" -o "$TMP_COVER" 2>/dev/null && [[ -s "$TMP_COVER" ]]; then
            ebook-meta "$file" --cover "$TMP_COVER" > /dev/null 2>&1
            cover_written=true
            WRITTEN_FIELDS+=("cover")
        fi
        rm -f "$TMP_COVER"
        TMP_COVER=""
    fi

    # -----------------------------------------------------------------------
    # Write non-cover fields
    # -----------------------------------------------------------------------
    if [[ ${#EBOOK_META_ARGS[@]} -gt 0 ]]; then
        ebook-meta "$file" "${EBOOK_META_ARGS[@]}" > /dev/null 2>&1
    fi

    if [[ ${#WRITTEN_FIELDS[@]} -gt 0 ]]; then
        joined=$(IFS=', '; echo "${WRITTEN_FIELDS[*]}")
        log "  OK $joined"
        UPDATED=$((UPDATED + 1))
    else
        log "  -- No new data written"
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
