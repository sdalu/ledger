#!/usr/bin/env python3
"""text_probe.py -- what the Python viewer's text helpers say of each
string in a JSON list on stdin, as a JSON list of objects, for
test/text_test.rb. Writes nothing; exit 0."""

import html
import importlib.util
import json
import os
import sys

SCRIPTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "scripts"))
sys.path.insert(0, SCRIPTS)
spec = importlib.util.spec_from_file_location("ledger_serve", os.path.join(SCRIPTS, "ledger-serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
ledger = serve.ledger


def probe(text):
    return {
        "escape": html.escape(text),
        "strip": text.strip(),
        "title_of": list(ledger.title_of(text)),
        "case_of": ledger.case_of(text),
        "strip_case": ledger.strip_case(text),
        "risk_rating": list(ledger.risk_rating(text)),
        "question_text": serve.question_text(text),
        "risk_clause": serve.risk_clause(text),
        "inline": serve.inline(text),
        "chip": serve.chip(text),
    }


json.dump([probe(t) for t in json.load(sys.stdin)], sys.stdout, ensure_ascii=False)
