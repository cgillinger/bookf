# bookf — Compatibility Notes

This document describes tested environments, supported formats, and known behaviour across different platforms.

---

## Tested environments

| Environment | Status |
|-------------|--------|
| Ubuntu 24.04 + Calibre 7.x | ✅ Tested and working |
| Docker (Linux host, ubuntu:24.04 image) | ✅ Tested and working |
| Synology DSM — via Docker | ✅ Tested and working (use `docker-compose.yml`) |
| Unraid — via Docker | ✅ Tested and working (use `docker-compose.yml`) |
| macOS + Homebrew Calibre | ⚠️ Should work — not tested |
| Windows (WSL2 + Ubuntu) | ⚠️ May work — not tested |
| Windows (native, Git Bash, Cygwin) | ❌ Not supported |

---

## Supported ebook formats

| Format | Extension | Metadata support | Notes |
|--------|-----------|-----------------|-------|
| EPUB | `.epub` | ✅ Best results | Most complete metadata embedding; recommended format |
| MOBI | `.mobi` | ✅ Works | Kindle legacy format; comments field supported |
| AZW3 | `.azw3` | ✅ Works | Kindle current format; comments field supported |
| KEPUB | `.kepub` | ✅ Works | Kobo-enhanced EPUB; treated as EPUB internally by Calibre |

---

## Metadata sources

Calibre's `fetch-ebook-metadata` queries these sources automatically, in order:

| Source | Coverage |
|--------|----------|
| **Google Books** | Best coverage for English-language novels and non-fiction |
| **Amazon** | Good coverage; especially useful for books not in Google Books |

The lookup is done by **title + author** (not ISBN). Results depend on how well the book is indexed in these databases. Self-published, obscure, or non-English titles are more likely to return no results.

---

## Komga compatibility

| Komga deployment | Status |
|------------------|--------|
| Docker on Linux | ✅ Works — descriptions visible after library scan |
| Synology DSM via Docker | ✅ Works — descriptions visible after library scan |
| Unraid via Docker | ✅ Works — descriptions visible after library scan |
| Bare-metal Linux (jar) | ✅ Expected to work |
| macOS (jar) | ⚠️ Not tested |

---

## Multiple formats of the same book

If your library contains the same book in more than one format (e.g. `book.epub`, `book.kepub`, and `book.mobi`), **each file is processed and updated individually**. The same description is fetched and written into all three files. This is intentional — each format is a self-contained file and Komga treats them as separate items.

---

## Books not found online

If a title + author combination returns no results from Google Books or Amazon, the file is skipped and logged as `FAILED`. The original file is **not modified**. You can identify these books with:

```bash
grep "FAILED" /tmp/update-book-metadata.log
```

Common causes:
- Self-published or very niche titles
- Books with unusual characters in the title or author name
- Non-English titles that are not well indexed in Google Books or Amazon
- Scanned/OCR'd ebooks with incorrect or missing embedded metadata

---

## Calibre version notes

| Calibre version | Status |
|----------------|--------|
| 7.x | ✅ Tested |
| 6.x | ✅ Expected to work |
| 5.x or older | ⚠️ Not tested; `fetch-ebook-metadata --opf` flag may behave differently |

Always use the latest stable Calibre release for best metadata coverage.
