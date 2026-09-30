#!/usr/bin/env python3
"""Contract check for the US Chess services OpenBoard reads. No app build.

Reads the app's endpoints from Shared/USChessEndpoints.swift (the one place
they're written), calls each one, and compares each response's *shape* (fields
and their types, not values: ratings and names change daily) with a recorded
snapshot. HTML pages, which have no schema, are checked for the markup the
app's parsers look for.

    python3 scripts/api_contract_check.py            # check against the snapshot
    python3 scripts/api_contract_check.py --record   # (re)write the snapshot

Result per endpoint:
  FAIL  a field the snapshot has is gone, or changed type; HTTP error; a marker
        the parser needs is missing; fewer items than expected
  NOTE  new fields appeared (harmless for the app, worth knowing)
Exit code 1 when anything fails. Standard library only.
"""
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Endpoints, query parameters and parser patterns come from the app's own
# source file, so the monitor always checks what the app actually calls.
ENDPOINTS_FILE = Path(__file__).resolve().parent.parent / "Shared" / "USChessEndpoints.swift"
SNAPSHOT = Path(__file__).with_name("api_contract.json")
USER_AGENT = "OpenBoard-iOS/1.0 (contract check)"

# Public, long-lived subjects: GM Fabiano Caruana and the 2025 North American Open.
PLAYER = "12743305"
EVENT = "202512300043"


def load_endpoints(path=ENDPOINTS_FILE):
    """{"Ratings": {"member": "members/{memberID}", ...}, "Site": {...}, ...}
    from lines like `static let member = #"members/{memberID}"#` inside
    `enum Ratings { ... }`."""
    groups, current = {}, None
    for line in path.read_text().splitlines():
        enum = re.match(r"\s*enum (\w+)", line)
        if enum and enum.group(1) != "USChess":
            current = groups.setdefault(enum.group(1), {})
            continue
        constant = re.match(r'\s*static let (\w+)\s*=\s*(#*)"(.*)"\2\s*$', line)
        if constant and current is not None:
            current[constant.group(1)] = constant.group(3)
    for group in ("Ratings", "Site", "Params", "Patterns"):
        if not groups.get(group):
            sys.exit(f"Couldn't read enum {group} from {path}; keep its one-constant-per-line format.")
    return groups


E = load_endpoints()
R, S, P, PAT = E["Ratings"], E["Site"], E["Params"], E["Patterns"]
API = R["base"].rstrip("/") + "/"
SITE = S["base"].rstrip("/")
USED = set()  # endpoint constants this run checked


def endpoint(group, name, **values):
    """The template `group.name` with placeholders filled, recorded as covered."""
    USED.add(f"{group}.{name}")
    template = E[group][name]
    for key, value in values.items():
        template = template.replace("{" + key + "}", value)
    return template


def query(**params):
    """?Name=value using the app's parameter names (P keys)."""
    return "?" + urllib.parse.urlencode({P[key]: value for key, value in params.items()})


# ---------- HTTP ----------

def get(url, retries=3):
    """Body text of `url`. Waits out a 429 (the API allows ~100 requests/minute)."""
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < retries - 1:
                time.sleep(20)
                continue
            raise


# ---------- Shapes ----------

def type_name(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "number"
    return {str: "string", list: "array", dict: "object"}[type(value)]


def shape(value):
    """{"types": [...], "fields": {name: shape}, "items": shape} — lists merge
    all their items, so fields seen on any item count."""
    node = {"types": [type_name(value)]}
    if isinstance(value, dict):
        node["fields"] = {key: shape(item) for key, item in value.items()}
    elif isinstance(value, list) and value:
        merged = shape(value[0])
        for item in value[1:]:
            merged = merge(merged, shape(item))
        node["items"] = merged
    return node


def merge(a, b):
    node = {"types": sorted(set(a["types"]) | set(b["types"]))}
    if "fields" in a or "fields" in b:
        fields_a, fields_b = a.get("fields", {}), b.get("fields", {})
        node["fields"] = {key: merge(fields_a[key], fields_b[key]) if key in fields_a and key in fields_b
                          else fields_a.get(key) or fields_b.get(key)
                          for key in sorted(set(fields_a) | set(fields_b))}
    if "items" in a or "items" in b:
        node["items"] = merge(a["items"], b["items"]) if "items" in a and "items" in b \
            else a.get("items") or b.get("items")
    return node


def compare(expected, actual, path, problems, notes):
    """Missing fields and type changes are problems; new fields are notes.
    null is compatible with any type (the API leaves optional fields empty)."""
    real_expected = set(expected["types"]) - {"null"}
    real_actual = set(actual["types"]) - {"null"}
    if real_expected and real_actual and not real_actual & real_expected:
        problems.append(f"{path or '(root)'}: type {sorted(real_expected)} → {sorted(real_actual)}")
        return
    fields_e, fields_a = expected.get("fields"), actual.get("fields")
    if fields_e is not None and fields_a is not None:
        for key in fields_e:
            if key not in fields_a:
                problems.append(f"{path}.{key}: field missing" if path else f"{key}: field missing")
            else:
                compare(fields_e[key], fields_a[key], f"{path}.{key}" if path else key, problems, notes)
        added = sorted(set(fields_a) - set(fields_e))
        if added:
            notes.append(f"{path or '(root)'}: new fields {', '.join(added)}")
    if "items" in expected and "items" in actual:
        compare(expected["items"], actual["items"], f"{path}[]", problems, notes)


def pick(data, keys):
    """Only the fields the app reads, for big documents with many unused fields."""
    return {key: data[key] for key in keys if key in data}


# ---------- Endpoints ----------

def json_check(name, url, *, keys=None, items_at=None, min_items=0):
    """A JSON endpoint: shape vs snapshot, plus a minimum item count."""
    def run(context):
        data = json.loads(get(url(context) if callable(url) else url))
        document = pick(data, keys) if keys else data
        errors = []
        if keys:
            errors += [f"{key}: field missing" for key in keys if key not in data]
        items = data
        for step in (items_at or []):
            items = items.get(step, []) if isinstance(items, dict) else []
        if min_items and len(items) < min_items:
            errors.append(f"only {len(items)} items, expected at least {min_items}")
        return document, errors, data
    return name, run


def html_check(name, url, markers, row_marker=None, min_rows=0, pattern_min=None):
    """An HTML page: the app's parser patterns must still match."""
    def run(context):
        html = get(url)
        errors = [f"parser pattern no longer matches: {label}" for label, pattern in markers
                  if not re.search(pattern, html, re.S | re.I)]
        if row_marker:
            rows = html.count(row_marker)
            if rows < min_rows:
                errors.append(f"only {rows} rows ({row_marker!r}), expected at least {min_rows}")
        if pattern_min:
            label, minimum = pattern_min
            count = len(re.findall(PAT[label], html, re.S | re.I))
            if count < minimum:
                errors.append(f"{label} matched {count} times, expected at least {minimum}")
        return None, errors, html
    return name, run


def remember_top_list(data, context):
    regular = [d for d in data.get("items", []) if "Regular" in (d.get("id") or "")]
    context["top_list"] = (regular or data.get("items", [{}]))[0].get("id")


def remember_listing(html, context):
    paths = re.findall(PAT["listingPath"], html, re.S | re.I)
    context["listing"] = paths[0] if paths else None


# The announcement document has dozens of Drupal fields; these are the ones
# the app decodes (TournamentParser.NodeJSON).
ANNOUNCEMENT_FIELDS = ["title", "body", "field_event_dates", "field_event_location_name",
                       "field_event_address", "field_geofield", "field_online_event",
                       "field_fide_rated", "field_banner_line", "field_organizer_name",
                       "field_organizer_email_address", "field_organizer_phone_number",
                       "field_organizer_website"]

UPCOMING_URL = (SITE + "/" + endpoint("Site", "upcomingSearch")
                + query(radius="50", origin="Somerville, NJ"))

CHECKS = [
    json_check("Player profile  · " + R["member"],
               API + endpoint("Ratings", "member", memberID=PLAYER)),
    json_check("Player history  · " + R["memberSections"],
               API + endpoint("Ratings", "memberSections", memberID=PLAYER) + query(size="20"),
               items_at=["items"], min_items=5),
    json_check("Rank totals     · " + R["maxRanks"], API + endpoint("Ratings", "maxRanks")),
    json_check("Name search     · " + R["memberSearch"] + "?" + P["fuzzy"] + "=",
               API + endpoint("Ratings", "memberSearch") + query(fuzzy="caruana", size="10"),
               items_at=["items"], min_items=1),
    json_check("Event           · " + R["ratedEvent"],
               API + endpoint("Ratings", "ratedEvent", eventID=EVENT)),
    json_check("Crosstable      · " + R["sectionStandings"],
               API + endpoint("Ratings", "sectionStandings", eventID=EVENT, section="1") + query(size="50"),
               items_at=["items"], min_items=10),
    json_check("Top 100 catalog · " + R["topListCatalog"],
               API + endpoint("Ratings", "topListCatalog") + query(size="200"),
               items_at=["items"], min_items=20),
    json_check("Top 100 list    · " + R["topList"],
               lambda c: API + endpoint("Ratings", "topList", listID=c["top_list"]),
               items_at=["topPlayers"], min_items=50),
    json_check("Games (Best wins) · " + R["memberGames"],
               API + endpoint("Ratings", "memberGames", memberID=PLAYER) + query(ratingSource="R", size="50"),
               items_at=["items"], min_items=10),
    html_check("Upcoming search · " + S["upcomingSearch"], UPCOMING_URL,
               markers=[(name, PAT[name]) for name in
                        ("listingPath", "listingName", "listingDate", "listingAddress", "listingOrganizer")],
               row_marker=PAT["listingRow"], min_rows=5),
    json_check("Announcement    · " + S["announcement"] + "?" + P["format"] + "=json",
               lambda c: SITE + endpoint("Site", "announcement", path=c["listing"]) + query(format="json"),
               keys=ANNOUNCEMENT_FIELDS),
    html_check("Major events    · " + S["planAheadCalendar"], SITE + "/" + endpoint("Site", "planAheadCalendar"),
               markers=[("planAheadEntry", PAT["planAheadEntry"])],
               pattern_min=("planAheadEntry", 10)),
]

FOLLOW_UPS = {"Top 100 catalog": remember_top_list, "Upcoming search": remember_listing}


# ---------- Main ----------

def main(record):
    snapshot = json.loads(SNAPSHOT.read_text()) if SNAPSHOT.exists() and not record else {}
    recorded, context, failures = {}, {}, 0
    for name, run in CHECKS:
        key = name.split("·")[0].strip()
        try:
            document, errors, raw = run(context)
        except Exception as error:  # HTTP errors, timeouts, bad JSON, missing context
            document, errors, raw = None, [f"{type(error).__name__}: {error}"], None
        for prefix, follow_up in FOLLOW_UPS.items():
            if key.startswith(prefix) and raw is not None:
                follow_up(json.loads(raw) if isinstance(raw, str) and raw.lstrip().startswith("{") else raw, context)
        notes = []
        if document is not None:
            live = shape(document)
            recorded[key] = live
            if not record:
                if key in snapshot:
                    compare(snapshot[key], live, "", errors, notes)
                else:
                    notes.append("not in the snapshot yet (run with --record)")
        failures += bool(errors)
        print(f"{'FAIL' if errors else 'ok  '}  {name}")
        for line in errors:
            print(f"        ✘ {line}")
        for line in notes:
            print(f"        · {line}")
    if record:
        SNAPSHOT.write_text(json.dumps(recorded, indent=1, sort_keys=True) + "\n")
        print(f"\nRecorded {len(recorded)} response shapes to {SNAPSHOT}")
    # Every endpoint in the shared file must be checked here.
    declared = {f"{group}.{name}" for group in ("Ratings", "Site") for name in E[group] if name != "base"}
    unchecked = sorted(declared - USED)
    if unchecked:
        failures += 1
        print(f"FAIL  Coverage: in {ENDPOINTS_FILE.name} but not checked here: {', '.join(unchecked)}")
    print(f"\n{len(CHECKS) - failures}/{len(CHECKS)} endpoints match their contract "
          f"({len(declared)} endpoints read from {ENDPOINTS_FILE.name}).")
    return 1 if failures and not record else 0


if __name__ == "__main__":
    sys.exit(main(record="--record" in sys.argv))
