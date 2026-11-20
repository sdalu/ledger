#!/usr/bin/env python3
"""python_render.py -- a page of the Python viewer, on stdout, for the
comparison harness (test/compare_pages.rb).

    python3 python_render.py index ROOT|LEDGER...
    python3 python_render.py ledger TOKEN ROOT|LEDGER...
    python3 python_render.py csp

Imports ledger-serve.py by path and calls its render functions directly,
over the ledgers it finds under the roots. `index` prints the index page;
`ledger` prints one JSON object, {ledger id: its page}, the forms
carrying TOKEN; `csp` prints the two Content-Security-Policy values,
{"page": .., "mockup": ..}. Writes nothing and starts no server. Exit 0 printed,
2 usage."""

import importlib.util
import json
import os
import sys

SCRIPTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "scripts"))


def serve_module():
    sys.path.insert(0, SCRIPTS)
    spec = importlib.util.spec_from_file_location("ledger_serve", os.path.join(SCRIPTS, "ledger-serve.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def ledgers(serve, token, roots):
    found = serve.discover(roots)
    st = serve.stamp(found)
    return {lid: serve.render_ledger(lid, path, project, mockups, st, token)
            for lid, (path, project, mockups) in found.items()}


def main(argv):
    if argv == ["csp"]:
        serve = serve_module()
        json.dump({"page": serve.page_csp(), "mockup": serve.MOCKUP_CSP}, sys.stdout)
        return 0
    if len(argv) < 2 or argv[0] not in ("index", "ledger") or (argv[0] == "ledger" and len(argv) < 3):
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    serve = serve_module()
    if argv[0] == "ledger":
        json.dump(ledgers(serve, argv[1], argv[2:]), sys.stdout)
        return 0
    found = serve.discover(argv[1:])
    sys.stdout.write(serve.render_index(found, serve.stamp(found)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
