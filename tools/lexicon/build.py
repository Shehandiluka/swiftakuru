#!/usr/bin/env python3
"""Builds Swift Akuru's base Sinhala lexicon + word-pair model from public corpora.

Sources (all public, CC BY / CC BY-SA):
  * Leipzig Corpora Collection — Sinhala news / web / Wikipedia word + neighbour counts
  * FrequencyWords (OpenSubtitles 2018) — everyday spoken Sinhala, weighted up
  * Sinhala Wikipedia dump — fallback if Leipzig is unreachable
Output (sorted, plain text, read memory-mapped by the keyboard):
  words.tsv    word \t count                (sorted by word bytes)
  bigrams.tsv  w1 \t w2 \t count            (sorted by w1 \t w2 bytes)
"""
import bz2, collections, glob, io, os, re, sys, tarfile, urllib.request

WORD = re.compile(r"[඀-෿‍]+")
OK = re.compile(r"^[඀-෿][඀-෿‍]*$")
uni, bi = collections.Counter(), collections.Counter()

def fetch(url, path):
    if os.path.exists(path): return True
    try:
        print("GET", url, flush=True)
        urllib.request.urlretrieve(url, path)
        return True
    except Exception as e:
        print("  skip:", e, flush=True)
        if os.path.exists(path): os.remove(path)
        return False

def good(w): return OK.match(w) and 1 <= len(w) <= 25 and not w.endswith("‍")

def add_sentences(lines, weight=1):
    for line in lines:
        prev = None
        for m in re.finditer(r"[඀-෿‍]+|[^\s඀-෿‍]+", line):
            w = m.group(0)
            if good(w):
                uni[w] += weight
                if prev: bi[(prev, w)] += weight
                prev = w
            else:
                prev = None if not w.isspace() else prev

# 1) Leipzig: use the *-sentences.txt files (id \t sentence)
leipzig = ["sin_wikipedia_2016_100K", "sin_community_2017", "sin_wikipedia_2021_100K", "sin_wikipedia_2021_30K",
           "sin_news_2011_30K", "sin_news_2011_100K", "sin_newscrawl_2011_30K", "sin_web_2012_30K", "sin_web_2012_100K",
           "sin-lk_web_2015_30K", "sin-lk_web_2015_100K", "sin-lk_web_2015_300K", "sin_mixed_2011_100K"]
got = 0
for name in leipzig:
    tgz = name + ".tar.gz"
    if not fetch(f"https://downloads.wortschatz-leipzig.de/corpora/{tgz}", tgz): continue
    try:
        with tarfile.open(tgz) as t:
            for m in t.getmembers():
                if m.name.endswith("-sentences.txt"):
                    f = io.TextIOWrapper(t.extractfile(m), encoding="utf-8", errors="ignore")
                    add_sentences((l.split("\t", 1)[-1] for l in f))
                    got += 1
    except Exception as e: print("  bad archive", e)
print("leipzig corpora:", got, "words so far:", len(uni), flush=True)

# 2) Wikipedia dump (fallback / extra)
if fetch("https://dumps.wikimedia.org/siwiki/latest/siwiki-latest-pages-articles.xml.bz2", "siwiki.xml.bz2"):
    with bz2.open("siwiki.xml.bz2", "rt", encoding="utf-8", errors="ignore") as f:
        add_sentences(f)
    print("after wikipedia:", len(uni), flush=True)

# 3) spoken Sinhala from subtitles — weighted up so chat words rank high
if fetch("https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/si/si_full.txt", "si_full.txt"):
    total = sum(uni.values()) or 1
    rows = [l.split() for l in open("si_full.txt", encoding="utf-8")]
    sub_total = sum(int(r[1]) for r in rows if len(r) == 2) or 1
    scale = max(1.0, total / sub_total) * 3
    for r in rows:
        if len(r) == 2 and good(r[0]): uni[r[0]] += int(int(r[1]) * scale) + 1

# 4) our hand-picked everyday words always stay
for w in open(sys.argv[1], encoding="utf-8").read().split():
    if good(w): uni[w] += max(50, uni[w])

top = [w for w, c in uni.most_common(80000) if c >= 2]
keep = set(top)
pairs = [(p, c) for p, c in bi.most_common(150000) if c >= 3 and p[0] in keep and p[1] in keep][:90000]
os.makedirs("out", exist_ok=True)
with open("out/words.tsv", "w", encoding="utf-8") as f:
    for w in sorted(top, key=lambda s: s.encode()): f.write(f"{w}\t{uni[w]}\n")
with open("out/bigrams.tsv", "w", encoding="utf-8") as f:
    for (a, b), c in sorted(pairs, key=lambda x: (x[0][0] + "\t" + x[0][1]).encode()): f.write(f"{a}\t{b}\t{c}\n")
print("words:", len(top), "pairs:", len(pairs))
