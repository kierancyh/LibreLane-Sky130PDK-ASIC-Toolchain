#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Tuple


ROOT = Path(__file__).resolve().parents[2]

ATTR_RE = re.compile(r"\(\*.*?\*\)", re.S)
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//.*?$", re.M)
MODULE_BLOCK_RE = re.compile(r"(?ms)\bmodule\s+([A-Za-z_]\w*)\b(.*?)\bendmodule\b")


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def strip_verilog_comments(text: str) -> str:
    text = ATTR_RE.sub(" ", text)
    text = BLOCK_COMMENT_RE.sub(" ", text)
    text = LINE_COMMENT_RE.sub("", text)
    return text


def extract_module_blocks(text: str) -> List[Tuple[str, str]]:
    stripped = strip_verilog_comments(text)
    blocks: List[Tuple[str, str]] = []
    for match in MODULE_BLOCK_RE.finditer(stripped):
        module_name = match.group(1)
        block = match.group(0)
        header_end = block.find(";")
        body = block[header_end + 1 :] if header_end >= 0 else ""
        blocks.append((module_name, body))
    return blocks


def discover_module_index(rtl_sources: List[str]) -> Tuple[Dict[str, List[str]], Dict[str, str]]:
    module_to_files: Dict[str, List[str]] = {}
    module_bodies: Dict[str, str] = {}

    for rel in rtl_sources:
        src_path = ROOT / rel
        if not src_path.exists():
            continue
        text = src_path.read_text(encoding="utf-8", errors="ignore")
        for module_name, body in extract_module_blocks(text):
            module_to_files.setdefault(module_name, []).append(rel)
            module_bodies.setdefault(module_name, body)

    return module_to_files, module_bodies


def find_module_dependencies(module_name: str, body: str, known_modules: List[str]) -> List[str]:
    deps: List[str] = []
    for candidate in sorted(known_modules, key=len, reverse=True):
        if candidate == module_name:
            continue
        pattern = re.compile(
            rf"(?<![\w$.]){re.escape(candidate)}\s*"
            rf"(?:#\s*\((?:[^()]|\([^()]*\)|\n)*?\)\s*)?"
            rf"[A-Za-z_]\w*\s*\(",
            re.M | re.S,
        )
        if pattern.search(body):
            deps.append(candidate)
    return sorted(set(deps))


def build_reachable_closure(top: str, rtl_sources: List[str]) -> Dict[str, Any]:
    module_to_files, module_bodies = discover_module_index(rtl_sources)
    known_modules = sorted(module_to_files.keys())
    dep_map = {
        module_name: find_module_dependencies(module_name, body, known_modules)
        for module_name, body in module_bodies.items()
    }

    if not top:
        return {
            "ok": False,
            "reason": "missing_top_module",
            "module_to_files": module_to_files,
            "dep_map": dep_map,
            "reachable_modules": [],
            "closure_sources": [],
            "duplicate_reachable_modules": {},
        }

    if top not in module_to_files:
        return {
            "ok": False,
            "reason": "top_not_found_in_rtl_sources",
            "module_to_files": module_to_files,
            "dep_map": dep_map,
            "reachable_modules": [],
            "closure_sources": [],
            "duplicate_reachable_modules": {},
        }

    reachable_modules: List[str] = []
    visited = set()
    stack = [top]
    while stack:
        current = stack.pop()
        if current in visited:
            continue
        visited.add(current)
        reachable_modules.append(current)
        for dep in reversed(dep_map.get(current, [])):
            if dep not in visited:
                stack.append(dep)

    duplicate_reachable_modules = {
        module_name: module_to_files[module_name]
        for module_name in reachable_modules
        if len(module_to_files.get(module_name, [])) > 1
    }

    closure_sources = sorted(
        {rel for module_name in reachable_modules for rel in module_to_files.get(module_name, [])}
    )
    return {
        "ok": len(duplicate_reachable_modules) == 0,
        "reason": "ok" if len(duplicate_reachable_modules) == 0 else "duplicate_reachable_modules",
        "module_to_files": module_to_files,
        "dep_map": dep_map,
        "reachable_modules": reachable_modules,
        "closure_sources": closure_sources,
        "duplicate_reachable_modules": duplicate_reachable_modules,
    }


def format_closure_report(closure: Dict[str, Any], top: str, rtl_sources: List[str]) -> str:
    lines = [
        "Yosys precheck source closure report",
        f"Top module: {top or '(missing)'}",
        f"All resolved RTL sources: {len(rtl_sources)}",
        f"Reachable closure sources: {len(closure.get('closure_sources', []))}",
        "",
    ]

    reachable = closure.get("reachable_modules", []) or []
    if reachable:
        lines.append("Reachable modules:")
        lines.extend(f"  - {name}" for name in reachable)
        lines.append("")

    closure_sources = closure.get("closure_sources", []) or []
    if closure_sources:
        lines.append("Reachable closure source files:")
        lines.extend(f"  - {rel}" for rel in closure_sources)
        lines.append("")

    duplicates = closure.get("duplicate_reachable_modules", {}) or {}
    if duplicates:
        lines.append("Duplicate reachable module definitions:")
        for module_name, files in sorted(duplicates.items()):
            lines.append(f"  - {module_name}: {', '.join(files)}")
        lines.append("")

    dep_map = closure.get("dep_map", {}) or {}
    if reachable:
        lines.append("Reachable dependency map:")
        for module_name in reachable:
            deps = dep_map.get(module_name, []) or []
            dep_text = ", ".join(deps) if deps else "(leaf)"
            lines.append(f"  - {module_name}: {dep_text}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def ys_quote(path: str) -> str:
    return '"' + path.replace('\\', '\\\\').replace('"', '\\"') + '"'


def main() -> None:
    ap = argparse.ArgumentParser(description="Run the Yosys structural precheck and emit status metadata.")
    ap.add_argument("--meta-json", required=True)
    ap.add_argument("--out-dir", default="precheck/yosys")
    args = ap.parse_args()

    meta = json.loads(Path(args.meta_json).read_text(encoding="utf-8"))
    cfg = meta.get("precheck", {}).get("yosys", {}) or {}

    out_dir_arg = Path(args.out_dir)
    out_dir = out_dir_arg if out_dir_arg.is_absolute() else (ROOT / out_dir_arg)
    out_dir = out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    log_path = out_dir / "yosys.log"
    stat_txt = out_dir / "stat.txt"
    stat_json = out_dir / "stat.json"
    status_path = out_dir / "status.json"
    meta_path = out_dir / "precheck_meta.json"
    top = str(meta.get("top_module") or "").strip()
    netlist_path = out_dir / f"{top}_synth.v"
    script_path = out_dir / "run.ys"

    enabled = bool(cfg.get("enabled", True))
    rtl_sources_all = list(meta.get("rtl_sources", []) or [])
    closure = build_reachable_closure(top, rtl_sources_all)
    rtl_sources_closure = list(closure.get("closure_sources", []) or [])

    precheck_meta = {
        "variant_path": meta.get("variant_path", ""),
        "safe_variant": meta.get("safe_variant", ""),
        "top_module": top,
        "rtl_sources_all": rtl_sources_all,
        "rtl_sources_closure": rtl_sources_closure,
        "reachable_modules": closure.get("reachable_modules", []),
        "duplicate_reachable_modules": closure.get("duplicate_reachable_modules", {}),
        "tool": "yosys",
        "mode": str(cfg.get("mode") or "structural"),
        "enabled": enabled,
    }

    if not enabled:
        log_path.write_text("Yosys precheck disabled by variant.yaml\n", encoding="utf-8")
        stat_txt.write_text("Yosys precheck disabled by variant.yaml\n", encoding="utf-8")
        stat_json.write_text("{}\n", encoding="utf-8")
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "yosys",
            "enabled": False,
            "status": "SKIP",
            "passed": True,
            "warning_count": 0,
            "reason": "disabled",
            "all_source_count": len(rtl_sources_all),
            "used_source_count": 0,
        })
        return

    if closure.get("reason") == "top_not_found_in_rtl_sources":
        log_path.write_text(
            format_closure_report(closure, top, rtl_sources_all)
            + f"\nERROR: top module '{top}' was not found in the resolved RTL sources.\n",
            encoding="utf-8",
        )
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "yosys",
            "enabled": True,
            "status": "FAIL",
            "passed": False,
            "warning_count": 0,
            "rc": None,
            "variant_path": meta.get("variant_path", ""),
            "safe_variant": meta.get("safe_variant", ""),
            "top_module": top,
            "netlist_present": False,
            "stat_txt_present": False,
            "stat_json_present": False,
            "reason": "top_not_found_in_rtl_sources",
            "all_source_count": len(rtl_sources_all),
            "used_source_count": 0,
        })
        return

    if closure.get("reason") == "duplicate_reachable_modules":
        log_path.write_text(
            format_closure_report(closure, top, rtl_sources_all)
            + "\nERROR: duplicate module definitions were found within the reachable closure of the selected top.\n",
            encoding="utf-8",
        )
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "yosys",
            "enabled": True,
            "status": "FAIL",
            "passed": False,
            "warning_count": 0,
            "rc": None,
            "variant_path": meta.get("variant_path", ""),
            "safe_variant": meta.get("safe_variant", ""),
            "top_module": top,
            "netlist_present": False,
            "stat_txt_present": False,
            "stat_json_present": False,
            "reason": "duplicate_reachable_modules",
            "all_source_count": len(rtl_sources_all),
            "used_source_count": len(rtl_sources_closure),
        })
        return

    if not rtl_sources_closure:
        log_path.write_text(
            format_closure_report(closure, top, rtl_sources_all)
            + "\nERROR: no reachable closure sources were found for the selected top.\n",
            encoding="utf-8",
        )
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "yosys",
            "enabled": True,
            "status": "FAIL",
            "passed": False,
            "warning_count": 0,
            "rc": None,
            "variant_path": meta.get("variant_path", ""),
            "safe_variant": meta.get("safe_variant", ""),
            "top_module": top,
            "netlist_present": False,
            "stat_txt_present": False,
            "stat_json_present": False,
            "reason": "empty_reachable_closure",
            "all_source_count": len(rtl_sources_all),
            "used_source_count": 0,
        })
        return

    read_files = " ".join(ys_quote(str((ROOT / rel).resolve())) for rel in rtl_sources_closure)
    # run.ys is executed from out_dir, so use plain output filenames here.
    script = f"""
read_verilog -sv -defer {read_files}
hierarchy -check -top {top}
check
proc
opt
fsm
opt
memory
techmap
opt
check
tee -o stat.txt stat
tee -o stat.json stat -json
write_verilog -noattr -noexpr {top}_synth.v
""".strip() + "\n"
    script_path.write_text(script, encoding="utf-8")

    result = subprocess.run(
        ["yosys", "-s", "run.ys"],
        cwd=str(out_dir),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log_path.write_text(
        format_closure_report(closure, top, rtl_sources_all) + "\n" + (result.stdout or ""),
        encoding="utf-8",
    )

    warnings = len(re.findall(r"(?im)^warning:", result.stdout or ""))
    passed = result.returncode == 0 and netlist_path.exists() and stat_txt.exists()
    status = "PASS" if passed and warnings == 0 else "WARN" if passed else "FAIL"
    reason = "ok" if passed else "yosys_failed"
    if passed and warnings:
        reason = "warnings_present"

    write_json(meta_path, precheck_meta)
    write_json(status_path, {
        "tool": "yosys",
        "enabled": True,
        "status": status,
        "passed": passed,
        "warning_count": warnings,
        "rc": result.returncode,
        "variant_path": meta.get("variant_path", ""),
        "safe_variant": meta.get("safe_variant", ""),
        "top_module": top,
        "netlist_present": netlist_path.exists(),
        "stat_txt_present": stat_txt.exists(),
        "stat_json_present": stat_json.exists(),
        "reason": reason,
        "all_source_count": len(rtl_sources_all),
        "used_source_count": len(rtl_sources_closure),
    })


if __name__ == "__main__":
    main()
