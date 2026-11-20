#!/usr/bin/env python3
"""page_probe.py -- what the Python viewer's helpers for the ledger page
say of each string in a JSON list on stdin, as a JSON list of objects,
for test/page_text_test.rb. Writes nothing; exit 0."""

import itertools
import json
import os
import sys
import urllib.parse

import importlib.util

SCRIPTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "scripts"))
sys.path.insert(0, SCRIPTS)
spec = importlib.util.spec_from_file_location("ledger_serve", os.path.join(SCRIPTS, "ledger-serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
ledger = serve.ledger
TITLES = {"P1": "A title", "O2": "x" * 100, "D3": ""}


def short(text, limit):
    return text if len(text) <= limit else text[:limit - 3].rstrip() + "…"


def tupled(pairs):
    return None if pairs is None else [list(p) for p in pairs]


def probe(text):
    serve.ITEMS.titles = TITLES
    serve._TIPS = itertools.count(1)
    titled = serve.inline(text)
    serve._TIPS = itertools.count(1)
    block = serve.md_block(text)
    return {
        "words": text.split(), "splitlines": text.splitlines(),
        "quote": urllib.parse.quote(text), "shorten": short(text, 60),
        "option_code": ledger.option_code(text),
        "scope_words": tupled(ledger.scope_words(text)),
        "split_fields": list(ledger.split_fields(text)),
        "link_see": ledger.link_ids("see", text),
        "clock": serve.clock(text),
        "splitext": list(os.path.splitext(text)),
        "titled": titled, "md_block": block,
        "rows": [serve.risk_band(int(text))] if text.isdigit() else [],
    }


json.dump([probe(t) for t in json.load(sys.stdin)], sys.stdout, ensure_ascii=False)
