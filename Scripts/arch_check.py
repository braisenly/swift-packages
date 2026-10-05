#!/usr/bin/env python3
"""ARCH_CHECK reference implementation for SwiftPM repos in the drop-in architecture suite.

Reads `swift package dump-package` JSON and `architecture.json`, then enforces:
  1. declared-target parity        (manifest <-> architecture.json)
  2. layer dependency rules        (mayDependOn, uses, external)
  3. implicit imports              (imports of package targets/products must be direct deps)
  4. forbidden imports per layer   (e.g. SwiftUI in Core)
  5. acyclic capability graph      (capabilities[*].uses)
Optional: --mermaid FILE writes a capability graph.

Exit codes: 0 clean, 1 violations, 2 usage/config error. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"                 # attributes: @testable, @_exported, @preconcurrency
    r"(?:(?:public|package|internal|fileprivate|private)\s+)?"  # access-level imports (Swift 6)
    r"import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"CONFIG cannot read {path}: {exc}", file=sys.stderr)
        sys.exit(2)


def dep_name(dep: dict) -> tuple[str, str | None]:
    """Return (name, package) for a dump-package dependency entry."""
    for kind in ("byName", "target", "product"):
        if kind in dep and dep[kind]:
            value = dep[kind]
            name = value[0]
            package = value[1] if kind == "product" and len(value) > 1 else None
            return name, package
    return "", None


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", source)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dump", required=True, type=Path)
    ap.add_argument("--architecture", required=True, type=Path)
    ap.add_argument("--root", default=Path("."), type=Path)
    ap.add_argument("--mermaid", type=Path)
    args = ap.parse_args()

    dump = load_json(args.dump)
    arch = load_json(args.architecture)
    layers: dict = arch.get("layers", {})
    caps: dict = arch.get("capabilities", {})
    exceptions = {(e.get("from"), e.get("to")) for e in arch.get("exceptions", [])}

    # target -> (capability, layer)
    owner: dict[str, tuple[str, str]] = {}
    for cap, spec in caps.items():
        for target, layer in spec.get("targets", {}).items():
            if layer not in layers:
                print(f"CONFIG {target}: unknown layer '{layer}'", file=sys.stderr)
                return 2
            owner[target] = (cap, layer)

    targets = [t for t in dump.get("targets", []) if t.get("type") not in ("test", "plugin", "macro")]
    names = {t["name"] for t in targets}
    violations: list[str] = []

    for e in sorted(exceptions):
        print(f"EXCEPTION {e[0]} -> {e[1]} (approved exception; keep visible)")

    # 1. parity
    for n in sorted(names - owner.keys()):
        violations.append(f"UNDECLARED {n}: target missing from architecture.json")
    for n in sorted(owner.keys() - names):
        violations.append(f"MISSING {n}: declared in architecture.json but not in manifest")

    def allowed(src: str, dst: str, pkg: str | None) -> bool:
        if (src, dst) in exceptions:
            return True
        cap, layer = owner[src]
        rules = layers[layer].get("mayDependOn", [])
        uses = set(caps[cap].get("uses", []))
        if dst in owner:
            dcap, dlayer = owner[dst]
            if dcap == cap:
                return dlayer in rules
            if dcap not in uses:
                return False
            if f"foreign:{dlayer}" in rules:
                return True
            return f"capability:{dcap}" in rules and dlayer in ("Umbrella", "UI", "Interface")
        external = set(caps[cap].get("external", []))
        external_ok = "external:*" in rules or (pkg is not None and f"external:{pkg}" in rules)
        return external_ok and (dst in external or (pkg is not None and pkg in external))

    product_names: set[str] = set()
    for t in targets:
        for d in t.get("dependencies", []):
            name, pkg = dep_name(d)
            if pkg is not None:
                product_names.add(name)

    for t in targets:
        src = t["name"]
        if src not in owner:
            continue
        cap, layer = owner[src]
        direct: set[str] = set()
        # 2. layer rules
        for d in t.get("dependencies", []):
            name, pkg = dep_name(d)
            if not name:
                continue
            direct.add(name)
            if not allowed(src, name, pkg):
                dl = owner.get(name, ("external", "external"))
                violations.append(f"LAYER {src}: {layer} ({cap}) may not depend on {name} [{dl[1]} of {dl[0]}]")

        # 3 + 4. imports
        src_dir = args.root / (t.get("path") or f"Sources/{src}")
        forbidden = set(layers[layer].get("forbiddenImports", []))
        for swift in sorted(src_dir.rglob("*.swift")) if src_dir.exists() else []:
            text = strip_comments(swift.read_text(encoding="utf-8", errors="replace"))
            for m in IMPORT_RE.finditer(text):
                mod = m.group(1)
                rel = swift.relative_to(args.root)
                if mod in forbidden:
                    violations.append(f"FORBIDDEN {src}: {rel} imports {mod} (not allowed in {layer})")
                if (mod in names or mod in product_names) and mod != src and mod not in direct:
                    violations.append(f"IMPLICIT {src}: {rel} imports {mod} without a direct dependency")

    # 5. capability cycles
    graph = {c: set(s.get("uses", [])) for c, s in caps.items()}
    state: dict[str, int] = {}

    def visit(node: str, path: list[str]) -> None:
        state[node] = 1
        for nxt in sorted(graph.get(node, ())):
            if nxt not in graph:
                violations.append(f"USES {node}: unknown capability '{nxt}'")
            elif state.get(nxt) == 1:
                cycle = path[path.index(nxt):] + [nxt] if nxt in path else [node, nxt]
                violations.append("CYCLE " + " -> ".join(cycle))
            elif nxt not in state:
                visit(nxt, path + [nxt])
        state[node] = 2

    for c in sorted(graph):
        if c not in state:
            visit(c, [c])

    if args.mermaid:
        lines = ["```mermaid", "graph LR"]
        for c in sorted(graph):
            lines.append(f"  {c}")
            for u in sorted(graph[c]):
                lines.append(f"  {c} --> {u}")
        lines.append("```")
        args.mermaid.write_text("\n".join(lines) + "\n", encoding="utf-8")

    for v in violations:
        print(v)
    print(f"arch-check: {len(violations)} violation(s), {len(targets)} target(s), {len(caps)} capability(ies)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
