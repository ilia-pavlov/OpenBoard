"""Report and pass/fail a CI test step from xcresult JSON.

Usage: check_results.py <summary.json> <tests.json> <job name>
(both from `xcrun xcresulttool get test-results summary|tests --path X.xcresult`)

- Prints every test, grouped by suite: ✔ passed, ✘ failed, ⚠ flaky, ↷ skipped.
- Writes results.md (also appended to the GitHub job summary) and junit.xml
  for dorny/test-reporter, which publishes a separate check run with every
  test and failure annotations on the source lines.
- Flaky = failed, then passed on a retry: the job stays green, but each one gets
  a GitHub warning annotation and flaky.txt is written.
- Fails when any test failed after retries, or when no tests ran (e.g. a wrong
  -only-testing target).
"""
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def test_cases(node, suite=""):
    """Yield one dict per test case, with its suite and retry history."""
    kind = node.get("nodeType")
    if kind == "Test Suite":
        suite = node.get("name", suite)
    if kind == "Test Case":
        children = node.get("children") or []
        runs = [c for c in children if c.get("nodeType") == "Repetition"]
        # The same failure repeats once per attempt; keep each message once.
        messages = list(dict.fromkeys(
            c.get("name", "") for c in _walk(node) if c.get("nodeType") == "Failure Message"))
        result = node.get("result", "Unknown")
        yield {
            "suite": suite,
            "name": node.get("name", "?"),
            "result": result,
            "seconds": node.get("durationInSeconds") or 0,
            "retries": max(len(runs) - 1, 0),
            "attempts": max(len(runs), 1),
            "flaky": result == "Passed" and any(r.get("result") == "Failed" for r in runs),
            "messages": messages,
        }
        return
    for child in node.get("children") or []:
        yield from test_cases(child, suite)


def _walk(node):
    for child in node.get("children") or []:
        yield child
        yield from _walk(child)


def icon(case):
    if case["flaky"]:
        return "⚠"
    return {"Passed": "✔", "Failed": "✘", "Skipped": "↷"}.get(case["result"], "?")


def failed_text(case):
    n = case["attempts"]
    return f"failed all {n} attempts" if n > 1 else "failed"


def retries_text(n):
    return f"passed after {n} {'retry' if n == 1 else 'retries'}"


def repo_paths():
    """Basename → repo-relative path for tracked Swift files (for annotations)."""
    try:
        files = subprocess.run(["git", "ls-files", "*.swift"], capture_output=True, text=True,
                               check=True).stdout.split()
    except (OSError, subprocess.CalledProcessError):
        return {}
    return {os.path.basename(f): f for f in files}


def with_paths(message, paths):
    """'RunnerTests.swift:22: failed' → '…/Tests/RunnerTests.swift:22: failed'."""
    return re.sub(r"\b([\w+-]+\.swift):(\d+)",
                  lambda m: f"{paths.get(m.group(1), m.group(1))}:{m.group(2)}", message)


def write_junit(cases, job_name, path="junit.xml"):
    """JUnit XML: one <testsuite> per suite. Flaky tests pass, with a note."""
    paths = repo_paths()
    root = ET.Element("testsuites", name=job_name)
    for suite in dict.fromkeys(c["suite"] for c in cases):
        members = [c for c in cases if c["suite"] == suite]
        node = ET.SubElement(root, "testsuite", name=suite, tests=str(len(members)),
                             failures=str(sum(c["result"] == "Failed" for c in members)),
                             skipped=str(sum(c["result"] == "Skipped" for c in members)),
                             time=f"{sum(c['seconds'] for c in members):.3f}")
        for c in members:
            case = ET.SubElement(node, "testcase", classname=suite, name=c["name"], time=f"{c['seconds']:.3f}")
            if c["result"] == "Failed":
                messages = [with_paths(m, paths) for m in c["messages"]] or ["failed"]
                failure = ET.SubElement(case, "failure", message=f"{failed_text(c)}: {messages[0]}")
                failure.text = "\n".join(messages)
            elif c["result"] == "Skipped":
                ET.SubElement(case, "skipped")
            elif c["flaky"]:
                ET.SubElement(case, "system-out").text = f"Flaky: {retries_text(c['retries'])}"
    ET.indent(root)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def main(summary_path, tests_path, job_name):
    summary = json.load(open(summary_path))
    tests = json.load(open(tests_path))
    cases = [c for root in tests.get("testNodes", []) for c in test_cases(root)]

    total = summary.get("totalTestCount", 0)
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)
    result = summary.get("result", "Unknown")
    ok = result == "Passed" and total > 0
    flaky = [c for c in cases if c["flaky"]]
    failures = [c for c in cases if c["result"] == "Failed"]
    seconds = sum(c["seconds"] for c in cases)

    headline = f"{job_name}: {result} — {passed}/{total} passed, {failed} failed, {skipped} skipped"
    if flaky:
        headline += f", {len(flaky)} flaky"
    headline += f" ({seconds:.1f}s)"

    # ---- Log: every test, grouped by suite ----
    print(headline)
    for suite in dict.fromkeys(c["suite"] for c in cases):
        print(f"\n{suite}")
        for c in (c for c in cases if c["suite"] == suite):
            note = f" — {retries_text(c['retries'])}" if c["flaky"] else ""
            print(f"  {icon(c)} {c['name']} ({c['seconds']:.2f}s){note}")
            if c["result"] == "Failed":
                for message in c["messages"]:
                    print(f"      {message}")
    print()
    for c in flaky:
        # GitHub annotation: a yellow warning on the run and the PR.
        print(f"::warning title=Flaky test::{c['suite']}/{c['name']} {retries_text(c['retries'])}")
    for c in failures:
        print(f"::error title=Test failed::{c['suite']}/{c['name']} ({failed_text(c)}): {' | '.join(c['messages'])}")

    # ---- results.md (artifact + job summary) ----
    status = "✅" if ok and not flaky else ("⚠️" if ok else "❌")
    md = [f"### {status} {headline}", ""]
    if failures:
        md += ["**Failed tests**", ""]
        md += [f"- `{c['suite']}/{c['name']}` — {failed_text(c)}: {' | '.join(c['messages']) or 'no message'}"
               for c in failures]
        md.append("")
    if flaky:
        md += ["**Flaky tests** (failed, then passed on a retry)", ""]
        md += [f"- `{c['suite']}/{c['name']}` — {retries_text(c['retries'])}" for c in flaky]
        md.append("")
    md += [f"<details><summary>All {len(cases)} tests</summary>", "",
           "| | Suite | Test | Time |", "|:-:|---|---|--:|"]
    md += [f"| {icon(c)} | {c['suite']} | `{c['name']}` | {c['seconds']:.2f}s |" for c in cases]
    md += ["", "</details>", ""]
    text = "\n".join(md)

    write_junit(cases, job_name)

    with open("results.md", "w") as out:
        out.write(text)
    if flaky:
        with open("flaky.txt", "w") as out:
            out.write("\n".join(f"{c['suite']}/{c['name']}" for c in flaky) + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
            out.write(text + "\n")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
