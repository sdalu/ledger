#!/usr/bin/env python3
"""python_icons.py -- every icon viewer_icons.py draws, as JSON
{name: svg}, for test/icons_test.rb. Writes nothing; exit 0."""

import json
import os
import sys

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "scripts")))
import viewer_icons

names = list(viewer_icons.LUCIDE) + ["git"]
json.dump({n: viewer_icons.icon(n) for n in names}, sys.stdout, ensure_ascii=False)
