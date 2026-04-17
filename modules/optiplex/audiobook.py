#!/usr/bin/env python3
"""
Text → audio pipeline via Kokoro TTS.

Usage:
  make-audiobook --gutenberg 1342          # Pride and Prejudice
  make-audiobook --url https://...         # Article
  make-audiobook --gutenberg 1342 --voice af_sky
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote_plus

import requests
from bs4 import BeautifulSoup
from readability import Document

# Override with env vars to run from Mac against OptiPlex:
#   KOKORO_URL=http://optiplex:8880/v1/audio/speech
#   AUDIOBOOKS_DIR=~/audiobooks
KOKORO_URL  = os.environ.get("KOKORO_URL", "http://localhost:8880/v1/audio/speech")
BOOKS_DIR   = Path(os.environ.get("AUDIOBOOKS_DIR", "/var/lib/audiobooks/books"))
PODS_DIR    = Path(os.environ.get("PODCASTS_DIR",   "/var/lib/audiobooks/podcasts"))
CHUNK_CHARS = 1500  # chars per TTS call — keeps latency manageable

GUTENBERG_NS = {
    "dcterms": "http://purl.org/dc/terms/",
    "pgterms": "http://www.gutenberg.org/2009/pgterms/",
    "rdf":     "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
}


# ---------------------------------------------------------------------------
# Text utilities
# ---------------------------------------------------------------------------

def chunk_text(text: str) -> list[str]:
    """Split at sentence boundaries, keeping chunks under CHUNK_CHARS."""
    sentences = re.split(r"(?<=[.!?])\s+", text)
    chunks, current, length = [], [], 0
    for s in sentences:
        if length + len(s) > CHUNK_CHARS and current:
            chunks.append(" ".join(current))
            current, length = [s], len(s)
        else:
            current.append(s)
            length += len(s)
    if current:
        chunks.append(" ".join(current))
    return [c for c in chunks if c.strip()]


def safe_filename(text: str, max_len: int = 60) -> str:
    return re.sub(r"[^\w\s-]", "", text).strip().replace(" ", "_")[:max_len]


# ---------------------------------------------------------------------------
# TTS
# ---------------------------------------------------------------------------

def tts_chunk(text: str, voice: str, output_path: Path) -> None:
    r = requests.post(
        KOKORO_URL,
        json={"model": "kokoro", "input": text, "voice": voice, "response_format": "mp3"},
        stream=True,
        timeout=300,
    )
    r.raise_for_status()
    with open(output_path, "wb") as f:
        for chunk in r.iter_content(8192):
            f.write(chunk)


# ---------------------------------------------------------------------------
# Gutenberg
# ---------------------------------------------------------------------------

def fetch_gutenberg_text(book_id: int) -> str:
    for suffix in [f"{book_id}-0.txt", f"{book_id}.txt"]:
        r = requests.get(f"https://www.gutenberg.org/files/{book_id}/{suffix}", timeout=60)
        if r.status_code == 200:
            return r.text
    raise RuntimeError(f"Could not fetch Gutenberg book {book_id}")


def strip_boilerplate(text: str) -> str:
    start = re.search(r"\*{3} START OF.*?\*{3}", text, re.IGNORECASE)
    end   = re.search(r"\*{3} END OF.*?\*{3}",   text, re.IGNORECASE)
    if start and end:
        return text[start.end():end.start()].strip()
    return text


def fetch_gutenberg_metadata(book_id: int) -> dict:
    url = f"https://www.gutenberg.org/cache/epub/{book_id}/pg{book_id}.rdf"
    root = ET.fromstring(requests.get(url, timeout=30).content)

    title = root.findtext(".//dcterms:title", namespaces=GUTENBERG_NS) or "Unknown Title"
    title = " ".join(title.split())  # collapse embedded newlines

    authors = [
        el.findtext("pgterms:name", namespaces=GUTENBERG_NS)
        for el in root.findall(".//pgterms:agent", GUTENBERG_NS)
    ]
    authors = [a for a in authors if a]

    year = (root.findtext(".//dcterms:issued", namespaces=GUTENBERG_NS) or "")[:4]

    subjects = [
        el.text
        for el in root.findall(".//dcterms:subject/rdf:Description/rdf:value", GUTENBERG_NS)
        if el.text
    ]

    return {
        "title":    title,
        "author":   ", ".join(authors) or "Unknown Author",
        "year":     year,
        "subjects": subjects[:5],
        "source":   f"Project Gutenberg #{book_id}",
    }


def fetch_cover(title: str, author: str) -> bytes | None:
    try:
        q = quote_plus(f"{title} {author}")
        docs = requests.get(
            f"https://openlibrary.org/search.json?q={q}&limit=1", timeout=15
        ).json().get("docs", [])
        if docs and (cover_id := docs[0].get("cover_i")):
            r = requests.get(f"https://covers.openlibrary.org/b/id/{cover_id}-L.jpg", timeout=15)
            if r.status_code == 200 and r.headers.get("content-type", "").startswith("image"):
                return r.content
    except Exception as e:
        print(f"  [cover] {e}", file=sys.stderr)
    return None


def detect_chapters(text: str) -> list[dict]:
    pattern = re.compile(
        r"^(chapter\s+[ivxlcdm]+[^\n]*|chapter\s+\d+[^\n]*)",
        re.IGNORECASE | re.MULTILINE,
    )
    matches = list(pattern.finditer(text))
    if len(matches) < 2:
        return [{"title": "Book", "start": 0, "end": len(text)}]
    return [
        {
            "title": m.group(0).strip(),
            "start": m.start(),
            "end":   matches[i + 1].start() if i + 1 < len(matches) else len(text),
        }
        for i, m in enumerate(matches)
    ]


# ---------------------------------------------------------------------------
# Article
# ---------------------------------------------------------------------------

def fetch_article(url: str) -> dict:
    r = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=30)
    r.raise_for_status()

    doc  = Document(r.text)
    text = BeautifulSoup(doc.summary(), "lxml").get_text(" ", strip=True)

    soup   = BeautifulSoup(r.text, "lxml")
    title  = (
        (soup.find("meta", property="og:title") or {}).get("content")
        or doc.title()
        or url
    )
    author = (
        (soup.find("meta", attrs={"name": "author"}) or {}).get("content")
        or (soup.find("meta", property="article:author") or {}).get("content")
        or "Unknown Author"
    )

    cover = None
    og_img = soup.find("meta", property="og:image")
    if og_img and og_img.get("content"):
        try:
            cr = requests.get(og_img["content"], timeout=15)
            if cr.status_code == 200:
                cover = cr.content
        except Exception:
            pass

    return {"text": text, "metadata": {"title": title, "author": author, "source": url}, "cover": cover}


# ---------------------------------------------------------------------------
# ffmpeg assembly
# ---------------------------------------------------------------------------

def audio_duration_ms(path: Path) -> int:
    out = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    return int(float(json.loads(out)["format"]["duration"]) * 1000)


def assemble_m4b(
    chapter_audio: list[tuple[str, list[Path]]],
    metadata: dict,
    cover: bytes | None,
    output_path: Path,
) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)

        all_files, chapter_markers, cursor_ms = [], [], 0
        for ch_title, chunks in chapter_audio:
            ch_start = cursor_ms
            for p in chunks:
                all_files.append(p)
                cursor_ms += audio_duration_ms(p)
            chapter_markers.append({"title": ch_title, "start_ms": ch_start, "end_ms": cursor_ms})

        concat_file = tmp / "concat.txt"
        concat_file.write_text("\n".join(f"file '{p}'" for p in all_files))

        meta_lines = [
            ";FFMETADATA1",
            f"title={metadata['title']}",
            f"artist={metadata['author']}",
            f"album={metadata['title']}",
            "comment=Narrated by Kokoro TTS",
        ]
        if metadata.get("year"):
            meta_lines.append(f"date={metadata['year']}")
        if metadata.get("subjects"):
            meta_lines.append(f"genre={', '.join(metadata['subjects'])}")
        for ch in chapter_markers:
            meta_lines += [
                "\n[CHAPTER]", "TIMEBASE=1/1000",
                f"START={ch['start_ms']}", f"END={ch['end_ms']}", f"title={ch['title']}",
            ]

        meta_file = tmp / "meta.txt"
        meta_file.write_text("\n".join(meta_lines))

        cover_file = None
        if cover:
            cover_file = tmp / "cover.jpg"
            cover_file.write_bytes(cover)

        cmd = ["ffmpeg", "-y",
               "-f", "concat", "-safe", "0", "-i", str(concat_file),
               "-i", str(meta_file)]
        if cover_file:
            cmd += ["-i", str(cover_file),
                    "-map", "0:a", "-map_metadata", "1", "-map", "2",
                    "-c:a", "aac", "-b:a", "64k",
                    "-c:v", "mjpeg", "-disposition:v:0", "attached_pic"]
        else:
            cmd += ["-map", "0:a", "-map_metadata", "1", "-c:a", "aac", "-b:a", "64k"]
        cmd += ["-f", "mp4", str(output_path)]

        subprocess.run(cmd, check=True)


# ---------------------------------------------------------------------------
# Top-level jobs
# ---------------------------------------------------------------------------

def make_gutenberg_book(book_id: int, voice: str) -> None:
    print(f"Fetching Gutenberg #{book_id}...")
    text = strip_boilerplate(fetch_gutenberg_text(book_id))

    print("Fetching metadata...")
    metadata = fetch_gutenberg_metadata(book_id)
    print(f"  {metadata['title']} — {metadata['author']}")

    print("Fetching cover art...")
    cover = fetch_cover(metadata["title"], metadata["author"])
    print(f"  {'found' if cover else 'not found'}")

    chapters = detect_chapters(text)
    print(f"Detected {len(chapters)} chapter(s)")

    BOOKS_DIR.mkdir(parents=True, exist_ok=True)
    output_path = BOOKS_DIR / f"{safe_filename(metadata['title'])}.m4b"

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        chapter_audio = []
        for i, ch in enumerate(chapters):
            print(f"  [{i+1}/{len(chapters)}] {ch['title']}")
            chunks = chunk_text(text[ch["start"]:ch["end"]])
            chunk_paths = []
            for j, chunk in enumerate(chunks):
                print(f"    chunk {j+1}/{len(chunks)} ({len(chunk)} chars)", flush=True)
                path = tmp / f"ch{i:03d}_{j:03d}.mp3"
                tts_chunk(chunk, voice, path)
                chunk_paths.append(path)
            chapter_audio.append((ch["title"], chunk_paths))

        print(f"Assembling {output_path.name}...")
        assemble_m4b(chapter_audio, metadata, cover, output_path)

    print(f"Done → {output_path}")


def make_article(url: str, voice: str) -> None:
    print(f"Fetching article: {url}")
    article  = fetch_article(url)
    metadata = article["metadata"]
    print(f"  {metadata['title']} — {metadata['author']}")

    PODS_DIR.mkdir(parents=True, exist_ok=True)
    output_path = PODS_DIR / f"{safe_filename(metadata['title'])}.mp3"

    chunks = chunk_text(article["text"])
    print(f"  {len(chunks)} chunk(s)")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        chunk_paths = []
        for i, chunk in enumerate(chunks):
            print(f"  Chunk {i+1}/{len(chunks)} ({len(chunk)} chars)", flush=True)
            path = tmp / f"chunk{i:03d}.mp3"
            tts_chunk(chunk, voice, path)
            chunk_paths.append(path)

        concat_file = tmp / "concat.txt"
        concat_file.write_text("\n".join(f"file '{p}'" for p in chunk_paths))
        subprocess.run(
            ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat_file),
             "-c:a", "libmp3lame", "-b:a", "128k", str(output_path)],
            check=True,
        )

    print(f"Done → {output_path}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Convert text to audio via Kokoro TTS")
    group  = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--gutenberg", type=int, metavar="ID", help="Project Gutenberg book ID")
    group.add_argument("--url", help="Article URL")
    parser.add_argument("--voice", default="af_bella", help="Kokoro voice (default: af_bella)")
    args = parser.parse_args()

    if args.gutenberg:
        make_gutenberg_book(args.gutenberg, args.voice)
    else:
        make_article(args.url, args.voice)


if __name__ == "__main__":
    main()
