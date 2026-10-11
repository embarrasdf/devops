"""Collects detekt SARIF reports into one de-duplicated report and a Markdown summary.

    summarize.py <repo root> <output sarif> <output markdown> <blob url prefix>

In Kotlin Multiplatform modules, the JVM and Android type-resolved tasks both analyze commonMain,
so the same finding appears in two reports. A finding is identified by rule, file, line and column.
Prints the number of findings.
"""
import glob
import json
import os
import sys
from collections import defaultdict

root, out_sarif, out_markdown, blob_url = sys.argv[1:5]

reports = [
    path for path in glob.glob(os.path.join(root, "**/build/reports/detekt/*.sarif"), recursive=True)
    # The root project's merged report repeats every module's findings.
    if os.path.relpath(path, root) != os.path.join("build", "reports", "detekt", "static-analysis.sarif")
]

run = None
rules = {}
results = {}
for path in sorted(reports):
    with open(path) as file:
        for report_run in json.load(file).get("runs", []):
            if run is None:
                run = {key: value for key, value in report_run.items() if key != "results"}
            for rule in report_run.get("tool", {}).get("driver", {}).get("rules", []):
                rules[rule["id"]] = rule
            for result in report_run.get("results", []):
                location = result["locations"][0]["physicalLocation"]
                region = location.get("region", {})
                key = (
                    result.get("ruleId"),
                    location["artifactLocation"]["uri"],
                    region.get("startLine"),
                    region.get("startColumn"),
                )
                results.setdefault(key, result)

if run is not None:
    run["tool"]["driver"]["rules"] = sorted(rules.values(), key=lambda rule: rule["id"])
    run["results"] = list(results.values())
    with open(out_sarif, "w") as file:
        json.dump({"version": "2.1.0", "$schema": "https://json.schemastore.org/sarif-2.1.0.json", "runs": [run]}, file)

by_file = defaultdict(list)
for (rule_id, uri, line, _), result in sorted(results.items(), key=lambda item: (item[0][1], item[0][2] or 0)):
    by_file[uri].append((line, rule_id.split(".")[-1], result["message"]["text"]))

with open(out_markdown, "w") as file:
    for uri, findings in sorted(by_file.items()):
        file.write(f"**{uri}**\n\n| Line | Rule | Finding |\n| --- | --- | --- |\n")
        for line, rule, message in findings:
            message = message.replace("|", "\\|").replace("\n", " ")
            file.write(f"| [{line}]({blob_url}/{uri}#L{line}) | `{rule}` | {message} |\n")
        file.write("\n")

print(len(results))
