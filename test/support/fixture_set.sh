# fixture_set.sh -- the ledgers the comparison harness renders when it is
# given no roots. Run: ledger=PATH-TO-ledger.py sh fixture_set.sh ROOT
# The orchestration tests' own fixture (every state the viewer draws,
# tests/viewer-fixture.sh) in ROOT/proj, and beside it: a second ledger
# of that project holding words for the user (one sent, one not, one
# needing 'other'), a project with nothing waiting whose name needs
# escaping, one with an open line that has no id, and one ledger that
# cannot be read.

here=$(cd "$(dirname "$0")" && pwd)
root=$1
. "$here/../../../tests/viewer-fixture.sh"

make_fixture "$root" >/dev/null

# a second ledger in proj: P1 waits for commit (sent), P2 for 'other'
S="$root/proj/.claude/LEDGER-sfx.md"
python3 "$ledger" new "$S" --goal 'words' --title 'Second one' --short 'second' --date 2026-11-19 >/dev/null
python3 "$ledger" piece "$S" new --route "sonnet, effort: low" --title "first piece" --status verified --evidence "suite green" \
    --problem "done" --risk "3/10 — small" --plan "commit it" --awaits "commit" >/dev/null
python3 "$ledger" piece "$S" new --route "sonnet, effort: low" --title "second piece" --status verified --evidence "suite green" \
    --problem "done" --risk "4/10 — a look is cheap" --plan "look at it" --awaits "other (a look at the diff & the log)" >/dev/null
python3 "$ledger" piece "$S" new --route "sonnet, effort: low" --title "third piece" --status verified --evidence "suite green" \
    --problem "done" --risk "6/10 — bigger" --plan "merge it" --awaits "merge, deploy" >/dev/null
printf '%s\n' '{"id": "N1", "at": "2026-11-19 16:05:00", "ref": "P1", "word": "commit", "text": "go ahead"}' > "$S.inbox"

# nothing waiting, a name that needs escaping
C="$root/calm & <odd>'s/.claude/LEDGER.md"
mkdir -p "$root/calm & <odd>'s/.git" "$root/calm & <odd>'s/.claude"
python3 "$ledger" new "$C" --goal 'nothing to do' --title 'A calm one' --short 'calm' --date 2026-11-19 >/dev/null

# an open line without an id
mkdir -p "$root/loose/.git"
python3 "$ledger" new "$root/loose/LEDGER.md" --goal 'loose' --title 'A loose one' --short 'loose' --date 2026-11-19 >/dev/null
python3 - "$root/loose/LEDGER.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("Open:\n", "Open:\n- a loose question with no id & a <tag>\n", 1))
PY

# one ledger holding every card the ledger page draws: two goals, a
# constraint and a fact, a question per kind (pictures, a choice per
# item, none, answered and replaced, answered by items, by text, being
# prepared), a word sent and one dropped, pieces in every state, the
# pictures (a before/after pair, a long text figure, a missing file, a
# placeholder), decisions dated today, a note filed and one not
R="$root/rich/.claude/LEDGER.md"
mkdir -p "$root/rich/.git" "$root/rich/.claude/mockups" "$root/art"
python3 "$ledger" new "$R" --goal 'first goal of the rich ledger, long enough' --title 'Rich one' --short 'every card' --date 2026-11-18 >/dev/null
python3 "$ledger" goal "$R" --quote 'the second goal revises the first one' --title 'Rich two' --short 'the revised goal' --context 'a context with `code` and [P1](#piece-P1)' --date 2026-11-19 >/dev/null
python3 "$ledger" constraint "$R" --where "turn 2" 'never touch the "legacy" parser' >/dev/null
python3 "$ledger" fact "$R" 'the parser lives in src/parse.c:40-52 — read on 2026-11-18' >/dev/null
python3 "$ledger" criterion "$R" D1 --met "done" >/dev/null
python3 - "$R" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("Done when:\n", "Done when:\n- [ ] D2: the 'A & B' <case> works — evidence:\n", 1)
open(p, "w").write(s)
PY
TODAY=$(date +%Y-%m-%d)
python3 "$ledger" piece "$R" new --route "sonnet, effort: low" --title "first A & <b> piece" --status verified --evidence "green" --problem "done" --risk "3/10 — small" --plan "commit it" --awaits "commit" --for D2 >/dev/null
python3 "$ledger" piece "$R" new --route "sonnet, effort: low" --title "second piece" --status verified --evidence "green" --problem "done" --risk "3/10 — small" --plan "commit it" --awaits "commit" >/dev/null
python3 "$ledger" piece "$R" new --route "sonnet, effort: low" --title "third piece" --status verified --evidence "green" --problem "done" --risk "9/10 — large" --plan "commit it" --awaits "commit" --scope "commit = commit the third piece" >/dev/null
python3 "$ledger" piece "$R" new --route "peer: Someone" --title "blocked piece" --status blocked >/dev/null
python3 "$ledger" piece "$R" new --route "haiku, effort: low" --title "planned later" --after P4 >/dev/null
python3 "$ledger" piece "$R" new --route "haiku, effort: low" --title "planned first" >/dev/null
python3 "$ledger" piece "$R" new --route "sonnet, effort: low" --title "drawing the pictures" --status out >/dev/null
python3 "$ledger" ask "$R" --title "Pictures of the nav" "which nav?" --problem "two navs, see [P1](#piece-P1) and [O2](#q-O2) and [D2](#crit-D2)" --risk "6/10 — the wrong one ships" --choices "A = the old one | B = the new one | C = neither, in your comment" --recommend "B, it is smaller" --see "C1, F1, D2" --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Per item with pictures" "each item?" --problem "three items" --risk "4/10 — meh" --items "S1 | S2 | S3" --choices "A = keep | drop = remove | B = rework (in your comment)" --recommend "S1 A, S2 A, S3 B" --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Open question without options" "what do you think?" --problem "unclear" --risk "5/10 — words" --recommend "ask the owner" --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Answered and replaced" "pick one" --problem "x" --risk "2/10 — none" --choices "A = one | B = two (in your comment)" --recommend "A, simple" --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Answered by items" "pick per item" --problem "x" --risk "2/10 — none" --items "X1 | X2" --choices "A = one | B = two" --recommend "X1 A, X2 B" --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Answered by text" "free text" --problem "x" --risk "2/10 — none" --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Not ready" "wait for it" --problem "x" --risk "2/10 — none" --choices "A = a | B = b" --recommend "A, safe" --by P7 --no-picture 'test' >/dev/null
python3 "$ledger" ask "$R" --title "Not ready, no options" "wait for it too" --problem "x" --risk "2/10 — none" --recommend "later" --by P7 --no-picture 'test' >/dev/null
python3 "$ledger" decide "$R" --by user "O9: \"B = as drawn — with a twist\" — chosen" --date "$TODAY" >/dev/null
python3 "$ledger" decide "$R" --by user "O10: \"quoted \\\"inner\\\" only\"" --date "$TODAY" >/dev/null
python3 "$ledger" decide "$R" --by me "O10: R1: Not applied — nothing to do" --date "$TODAY" >/dev/null
python3 "$ledger" decide "$R" --by me "older decision" --date 2026-11-01 >/dev/null
printf '<!doctype html><title>m</title><p>x</p>\n' > "$root/art/nav-old.html"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$root/art/before-nav.svg"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$root/art/nav.svg"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$root/art/s2-detail.svg"
python3 -c "print('\n'.join('line %d with <tag> & more' % i for i in range(30)))" > "$root/art/long.txt"
cp "$root/art/nav-old.html" "$root/art/before-nav.svg" "$root/art/nav.svg" "$root/art/long.txt" "$root/art/s2-detail.svg" "$root/rich/.claude/mockups/"
python3 - "$R" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
def add(prefix, extra):
    global s
    out = []
    for line in s.split("\n"):
        out.append(line + extra if line.startswith(prefix) else line)
    s = "\n".join(out)
add("- O1:", " — mockup: nav-old.html — mockup: before-nav.svg — mockup: nav.svg — mockup: long.txt — mockup: ghost.png")
add("- O2:", " — mockup: s2-detail.svg — mockup: nav.svg")
add("- O3:", " — mockup: nav-old.html — mockup: ../escape.html — mockup: pending (P1) — mockup: pending (P8)")
add("- O8:", " — mockup: pending (P7)")
s = s.replace("\n\nOpen:\n", "\n- P8 [kept: done here] sonnet, effort: low — kept by me\n\nOpen:\n", 1)
open(p, "w").write(s)
PY
cat > "$R.inbox" <<'JSON'
{"id": "N1", "at": "2026-11-19 16:00:00", "ref": "O4", "choice": "A = one", "text": "first try"}
{"id": "N2", "at": "2026-11-19 16:05:00", "ref": "O4", "choice": "B = two (in your comment)", "notes": {"B = two (in your comment)": "because **bold**"}, "replaces": ["N1"], "text": "- a\n- b\n\n1. x\n2. y\n\n> quote\n\n```\ncode & <tag>\n```\npara one\nline two"}
{"id": "N3", "at": "2026-11-19 16:10:00", "ref": "O5", "picks": {"X1": "A = one", "X2": "B = two"}, "notes": {"X2": "why two"}, "text": ""}
{"id": "N4", "at": "2026-11-19 16:11:00", "ref": "O6", "text": "plain answer\nsecond line"}
{"id": "N5", "at": "2026-11-19 16:12:00", "ref": "P1", "word": "commit", "text": "go **now**\n\n- yes"}
{"id": "N6", "at": "2026-11-19 16:13:00", "ref": "P4", "word": "drop", "text": ""}
{"id": "N7", "at": "2026-11-19 16:14:00", "ref": null, "text": "a note"}
{"id": "N8", "at": "2026-11-19 16:15:00", "ref": "order", "order": ["P6", "P5"], "text": ""}
{"id": "N9", "at": "2026-11-19 16:16:00", "ref": "P6", "text": "a comment on planned"}
JSON
printf 'garbage line & <not> json\n' >> "$R.inbox"
printf 'N7 2026-11-19T16:20:00\n' > "$R.inbox.taken"
# lines the page cannot draw as parts: a constraint and a fact in no
# shape, a piece with no status, something noticed and left out
python3 - "$R" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("Constraints (verbatim, where said):\n", "Constraints (verbatim, where said):\n- a loose constraint & <b>\n", 1)
s = s.replace("\nFacts:\n", "\nFacts:\n- a loose fact\n", 1)
s = s.replace("\n\nOpen:\n", "\n- P9 [oops] nonsense & <odd>\n\nOpen:\n", 1)
s = s.replace("Out of scope, noticed:\n", "Out of scope, noticed:\n- left out & <noticed>\n- another\n", 1)
open(p, "w").write(s)
PY
python3 "$ledger" check "$R" >/dev/null 2>&1

# a ledger with nothing left to do: its criterion met, a note on what
# was left out
mkdir -p "$root/ready/.git"
python3 "$ledger" new "$root/ready/LEDGER.md" --goal 'ready' --title 'A ready one' --short 'ready' --date 2026-11-19 >/dev/null
python3 "$ledger" criterion "$root/ready/LEDGER.md" D1 --met "done" >/dev/null
python3 - "$root/ready/LEDGER.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("Out of scope, noticed:\n", "Out of scope, noticed:\n- a thing & <left> out\n", 1))
PY

# a ledger that cannot be read
mkdir -p "$root/shut/.git"
python3 "$ledger" new "$root/shut/LEDGER.md" --goal 'shut' --title 'A shut one' --short 'shut' --date 2026-11-19 >/dev/null
chmod 000 "$root/shut/LEDGER.md"

# the asked times, as a session's check leaves them
for f in "$root/proj/.claude/LEDGER.md" "$S" "$C" "$root/loose/LEDGER.md"; do
    python3 "$ledger" check "$f" >/dev/null 2>&1
done
true
