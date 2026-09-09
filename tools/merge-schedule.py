import json, sys, os, shutil, datetime

raw_path, out_path = sys.argv[1], sys.argv[2]
apply = len(sys.argv) > 3 and sys.argv[3] == "--apply"

raw = open(raw_path).read()
try:
    body = raw.split("CLASSBAR_JSON_START", 1)[1].split("CLASSBAR_JSON_END", 1)[0]
except IndexError:
    sys.exit("Banner fetch produced no schedule. Run again, or check the term code.")

fetched = json.loads(body.strip())
if not fetched:
    sys.exit("No classes parsed — refusing to touch the existing file.")

existing = {}
if os.path.exists(out_path):
    existing = json.load(open(out_path))

prev = {c["code"]: c for c in existing.get("classes", [])}

merged = []
for c in fetched:
    p = prev.get(c["code"], {})
    entry = {
        "name": p.get("name", c["name"]),
        "code": c["code"],
        "room": c["room"],
        "days": c["days"],
        "start": c["start"],
        "end": c["end"],
    }
    for k in ("canvas", "zoom"):
        if p.get(k):
            entry[k] = p[k]
    merged.append(entry)

changes = []
for c in merged:
    p = prev.get(c["code"])
    if not p:
        changes.append(f"  + {c['code']}  {c['room']}  {c['start']}-{c['end']}")
        continue
    if p.get("room") != c["room"]:
        changes.append(f"  ~ {c['code']}  room  {p.get('room')} -> {c['room']}")
    if (p.get("start"), p.get("end")) != (c["start"], c["end"]):
        changes.append(
            f"  ~ {c['code']}  time  {p.get('start')}-{p.get('end')} -> {c['start']}-{c['end']}")
    if p.get("days") != c["days"]:
        changes.append(f"  ~ {c['code']}  days  {p.get('days')} -> {c['days']}")
for code in prev:
    if not any(c["code"] == code for c in merged):
        changes.append(f"  - {code}  no longer registered")

out = {
    "canvasHome": existing.get("canvasHome", "https://northeastern.instructure.com/"),
    "refreshAgent": existing.get("refreshAgent", ""),
    "term": existing.get("term", {"start": 0, "end": 99999999, "beforeLabel": ""}),
    "classes": merged,
}

kept = sum(1 for c in merged if "canvas" in c or "zoom" in c)
print(f"parsed {len(merged)} classes; preserved links on {kept}")
print("\n".join(changes) if changes else "  no changes")

if not apply:
    print("\nDry run. Re-run with --apply to write.")
    sys.exit(0)

if os.path.exists(out_path):
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    shutil.copy2(out_path, f"{out_path}.bak-{stamp}")
    print(f"backup: {out_path}.bak-{stamp}")

with open(out_path, "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")
print(f"wrote {out_path}")
