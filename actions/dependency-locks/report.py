"""Reports what moved in a repo's Gradle lockfiles between two commits.

    python3 -I report.py <repo dir> <base commit> <output dir>

Writes report.json, for the dependency review, and report.md, for the pull request comment and
the job summary, to the output dir, and prints the number of changed modules. Also writes
insight-targets.txt: for each changed module still in use, the dependencyInsight task, module and
configuration that explain it, one per line. Lockfiles are
gradle.lockfile and buildscript-gradle.lockfile, written by embarrasdfWriteLocks from
gradle-plugins. A module is "declared" when gradle/libs.versions.toml names it, and "transitive"
otherwise. An override is a declared version that resolves to something else, usually because
another dependency asks for a higher one.
"""

import json
import re
import subprocess
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

LOCKFILE_NAMES = ("gradle.lockfile", "buildscript-gradle.lockfile")
CATALOG = "gradle/libs.versions.toml"
# Changes listed in the comment per table; report.json has them all.
TABLE_LIMIT = 60
# Suffixes of the per-platform modules a Kotlin Multiplatform library publishes beside its base
# module. The comment folds them into the base module's row.
PLATFORM_SUFFIX = re.compile(
    r"-(jvm|android|android-debug|desktop|js|wasm-js|wasm-wasi|"
    r"(ios|macos|tvos|watchos)(arm64|x64|simulatorarm64|arm32|devicearm64)|linux(x64|arm64)|mingwx64)$"
)


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout


def lockfile_paths(repo, commit):
    """Lockfile paths at a commit, or in the working tree when commit is None."""
    if commit is None:
        tracked = git(repo, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    else:
        tracked = git(repo, "ls-tree", "-r", "--name-only", commit).splitlines()
    return [path for path in tracked if path.rsplit("/", 1)[-1] in LOCKFILE_NAMES]


def read(repo, commit, path):
    if commit is None:
        file = Path(repo, path)
        return file.read_text() if file.is_file() else None
    try:
        return git(repo, "show", f"{commit}:{path}")
    except subprocess.CalledProcessError:
        return None


def project_path(lockfile):
    """The Gradle project path of a lockfile, such as :app:androidApp."""
    directory = lockfile.rsplit("/", 1)[0] if "/" in lockfile else ""
    return ":" + directory.replace("/", ":")


def scope(lockfile, configuration):
    """Where a configuration's dependencies end up: shipped code, tests, or the build itself."""
    if lockfile.endswith("buildscript-gradle.lockfile"):
        return "build"
    name = configuration.lower()
    if "test" in name or "benchmark" in name or "baselineprofile" in name:
        return "test"
    if "runtimeclasspath" in name or "compileclasspath" in name or "compileklibraries" in name:
        return "main"
    return "tooling"


def parse_locks(repo, commit):
    """{module: {version: [(project, configuration, scope)]}} across every lockfile."""
    modules = defaultdict(lambda: defaultdict(list))
    for path in lockfile_paths(repo, commit):
        text = read(repo, commit, path) or ""
        for line in text.splitlines():
            if not line or line.startswith("#") or line.startswith("empty="):
                continue
            coordinates, _, configurations = line.partition("=")
            group, name, version = coordinates.split(":", 2)
            label = project_path(path) + (" (buildscript)" if path.endswith("buildscript-gradle.lockfile") else "")
            for configuration in configurations.split(","):
                modules[f"{group}:{name}"][version].append((label, configuration, scope(path, configuration)))
    return modules


def parse_catalog(repo, commit):
    """{module: declared version or None} from the version catalog."""
    text = read(repo, commit, CATALOG)
    if not text:
        return {}
    catalog = tomllib.loads(text)
    versions = catalog.get("versions", {})

    def version_of(entry):
        version = entry.get("version")
        if isinstance(version, dict):
            if "ref" in version:
                return versions.get(version["ref"])
            version = version.get("strictly") or version.get("require") or version.get("prefer")
        return version if isinstance(version, str) else None

    declared = {}
    for entry in catalog.get("libraries", {}).values():
        if isinstance(entry, str):
            group, name, *rest = entry.split(":")
            declared[f"{group}:{name}"] = rest[0] if rest else None
            continue
        module = entry.get("module") or f"{entry.get('group')}:{entry.get('name')}"
        declared[module] = version_of(entry)
    for entry in catalog.get("plugins", {}).values():
        if isinstance(entry, str):
            plugin_id, _, version = entry.partition(":")
            declared[f"{plugin_id}:{plugin_id}.gradle.plugin"] = version or None
            continue
        plugin_id = entry["id"]
        declared[f"{plugin_id}:{plugin_id}.gradle.plugin"] = version_of(entry)
    return declared


def scopes_of(usages):
    order = ["main", "test", "tooling", "build"]
    found = {scope for _, _, scope in usages}
    return [scope for scope in order if scope in found]


def projects_of(usages):
    return sorted({project for project, _, _ in usages})


def describe(versions):
    return ", ".join(sorted(versions, key=version_key)) if versions else "none"


def changes(before, after, declared_before, declared_after):
    result = []
    for module in sorted(set(before) | set(after)):
        old, new = before.get(module, {}), after.get(module, {})
        if set(old) == set(new):
            continue
        # Where the versions that changed are used: the added ones, or the removed ones if none were.
        usages = [usage for version in set(new) - set(old) for usage in new[version]] or [
            usage for version in set(old) - set(new) for usage in old[version]
        ]
        is_declared = module in declared_after or module in declared_before
        result.append({
            "module": module,
            "before": sorted(old, key=version_key),
            "after": sorted(new, key=version_key),
            # The versions this change removes and adds; the rest stay as they were.
            "removed": sorted(set(old) - set(new), key=version_key),
            "added": sorted(set(new) - set(old), key=version_key),
            "kind": "declared" if is_declared else "transitive",
            "declared_before": declared_before.get(module),
            "declared_after": declared_after.get(module),
            "scopes": scopes_of(usages),
            "projects": projects_of(usages),
            # Where to run dependencyInsight for this module: a main configuration if there is one.
            "insight": next(
                ({"project": project, "configuration": configuration}
                 for scope_name in ("main", "test", "tooling")
                 for version in sorted(new)
                 for project, configuration, scope in new[version]
                 if scope == scope_name and "(buildscript)" not in project),
                None,
            ),
        })
    return result


def version_key(version):
    """Orders versions by their numeric release part, which is enough to tell higher from lower."""
    return [int(part) for part in re.findall(r"\d+", re.split(r"[-+]", version, maxsplit=1)[0])]


def overrides(after, declared):
    """Declared versions that something else raises.

    A lower version of a declared module is a project that doesn't declare it, so it isn't one.
    """
    result = []
    for module, version in sorted(declared.items()):
        if not version or module not in after:
            continue
        resolved = sorted((v for v in after[module] if version_key(v) > version_key(version)), key=version_key)
        if not resolved:
            continue
        usages = [usage for v in resolved for usage in after[module][v]]
        result.append({
            "module": module,
            "declared": version,
            "resolved": resolved,
            "scopes": scopes_of(usages),
            "projects": projects_of(usages),
        })
    return result


def fold_platforms(changes):
    """Rows for the comment: each multiplatform library's per-platform modules, such as -jvm and
    -iosarm64, folded into its base module's row when they moved the same way."""
    by_module = {change["module"]: dict(change, platforms=[]) for change in changes}
    rows = []
    for change in changes:
        base = PLATFORM_SUFFIX.sub("", change["module"])
        row = by_module.get(base)
        if (base != change["module"] and row is not None
                and (row["removed"], row["added"]) == (change["removed"], change["added"])):
            row["platforms"].append(change["module"][len(base) + 1:])
            continue
        rows.append(by_module[change["module"]])
    return rows


def markdown(report):
    lines = []
    changed = report["changes"]
    if not changed:
        lines.append("### No dependency changes")
        lines.append("")
        lines.append("The lockfiles resolve to the same versions as the base branch.")
    else:
        rows = fold_platforms(changed)
        declared = [row for row in rows if row["kind"] == "declared"]
        transitive = [row for row in rows if row["kind"] == "transitive"]
        lines.append(f"### Dependency changes: {len(declared)} declared, {len(transitive)} transitive")
        lines.append("")
        for title, rows in (("Declared in the version catalog", declared), ("Transitive", transitive)):
            if not rows:
                continue
            lines.append(f"**{title}**")
            lines.append("")
            lines.append("| Module | From | To | Used in |")
            lines.append("| --- | --- | --- | --- |")
            for change in rows[:TABLE_LIMIT]:
                platforms = f" (+{', '.join(sorted(change['platforms']))})" if change["platforms"] else ""
                lines.append(
                    f"| `{change['module']}`{platforms} | {describe(change['removed'])} "
                    f"| {describe(change['added'])} | {', '.join(change['scopes'])} |"
                )
            if len(rows) > TABLE_LIMIT:
                lines.append(f"| … {len(rows) - TABLE_LIMIT} more in the job summary artifact | | | |")
            lines.append("")
    new_overrides = [o for o in report["overrides"] if o["new"]]
    if new_overrides:
        lines.append("**Declared versions this change raises**")
        lines.append("")
        lines.extend(override_table(new_overrides))
        lines.append("")
    old_overrides = [o for o in report["overrides"] if not o["new"]]
    if old_overrides:
        lines.append("<details><summary>Declared versions already raised on the base branch</summary>")
        lines.append("")
        lines.extend(override_table(old_overrides))
        lines.append("")
        lines.append("</details>")
        lines.append("")
    lines.append(
        "_From and To list the versions that changed; other versions of a module stay. main: shipped "
        "code. test: tests and benchmarks. tooling: compiler plugins, lint and other build-time "
        "classpaths. build: Gradle plugins._"
    )
    return "\n".join(lines) + "\n"


def override_table(rows):
    lines = ["| Module | Declared | Resolves to | Used in |", "| --- | --- | --- | --- |"]
    for override in rows:
        lines.append(
            f"| `{override['module']}` | {override['declared']} | {describe(override['resolved'])} "
            f"| {', '.join(override['scopes'])} |"
        )
    return lines


def main():
    repo, base, output = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    before, after = parse_locks(repo, base), parse_locks(repo, None)
    declared_before, declared_after = parse_catalog(repo, base), parse_catalog(repo, None)

    previous = {(o["module"], tuple(o["resolved"])) for o in overrides(before, declared_before)}
    current = overrides(after, declared_after)
    for override in current:
        override["new"] = (override["module"], tuple(override["resolved"])) not in previous

    report = {
        "base": base,
        "changes": changes(before, after, declared_before, declared_after),
        "overrides": current,
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    (output / "report.md").write_text(markdown(report))
    # Transitive changes first: they're the ones whose cause isn't obvious. Per-platform modules
    # are left out when their base module changed too.
    changed = {change["module"] for change in report["changes"]}
    targets = []
    for change in sorted(report["changes"], key=lambda change: change["kind"] != "transitive"):
        insight = change["insight"]
        base = PLATFORM_SUFFIX.sub("", change["module"])
        if insight and change["added"] and (base == change["module"] or base not in changed):
            project = insight["project"].rstrip(":")
            targets.append(f"{project}:dependencyInsight {change['module']} {insight['configuration']}\n")
    (output / "insight-targets.txt").write_text("".join(targets))
    print(len(report["changes"]))


if __name__ == "__main__":
    main()
