#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

ROOT = Path(__file__).resolve().parents[2]


def load_yaml(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def normpath(value: str) -> str:
    return value.replace("\\", "/")


def repo_rel(path: Path) -> str:
    return normpath(os.path.relpath(path, ROOT))


def resolve_path(variant_path: Path, value: str) -> str:
    if not value:
        return value
    value = normpath(value)
    if value.startswith(("designs/", ".github/", "tools/", "docs/")):
        return value
    p = Path(value)
    if p.is_absolute():
        try:
            return repo_rel(p.resolve())
        except Exception:
            return normpath(str(p))
    return repo_rel((variant_path / value).resolve())


def map_safe_variant_to_path(safe_variant: str) -> Path:
    manifest = load_yaml(ROOT / "manifest.yaml")
    for exp in manifest.get("experiments", []) or []:
        variant = str(exp.get("variant", "")).strip()
        if variant and variant.replace("/", "_") == safe_variant:
            return ROOT / variant
    raise SystemExit(f"Cannot map variant '{safe_variant}' back to a designs/ path.")


def as_bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    s = str(value).strip().lower()
    if s in {"1", "true", "yes", "on"}:
        return True
    if s in {"0", "false", "no", "off", ""}:
        return False
    return default


def resolve_variant_path(variant_arg: Optional[str]) -> Path:
    if variant_arg:
        candidate = Path(variant_arg)
        if candidate.is_dir() and (candidate / "variant.yaml").exists():
            return candidate.resolve()
        return map_safe_variant_to_path(variant_arg).resolve()

    manifest = load_yaml(ROOT / "manifest.yaml")
    for exp in manifest.get("experiments", []) or []:
        if as_bool(exp.get("enabled"), False):
            variant = str(exp.get("variant", "")).strip()
            if variant:
                p = (ROOT / variant).resolve()
                if (p / "variant.yaml").exists():
                    return p
    raise SystemExit("No enabled experiment found in manifest.yaml")


def resolve_sources(variant_path: Path, source_patterns: List[str]) -> List[str]:
    resolved: List[str] = []
    for pattern in source_patterns:
        for path in glob.glob(str(variant_path / pattern), recursive=True):
            p = Path(path)
            if p.exists() and p.is_file():
                resolved.append(repo_rel(p.resolve()))
    out = sorted(set(resolved))
    return out


def default_tb_enabled(variant_path: Path) -> bool:
    return any((variant_path / "tb").glob("**/*.v")) or any((variant_path / "tb").glob("**/*.sv"))


def build_meta(variant_path: Path) -> Dict[str, Any]:
    variant_cfg = load_yaml(variant_path / "variant.yaml")
    if not variant_cfg:
        raise SystemExit(f"Could not load {variant_path / 'variant.yaml'}")

    safe_variant = repo_rel(variant_path).replace("/", "_")
    clock_cfg = variant_cfg.get("clock", {}) or {}
    ll_policy = variant_cfg.get("ll_policy", {}) or {}
    precheck = variant_cfg.get("precheck", {}) or {}
    icarus_cfg = precheck.get("icarus", {}) or {}
    yosys_cfg = precheck.get("yosys", {}) or {}

    rtl_patterns = list(variant_cfg.get("sources", []) or [])
    tb_patterns = list(icarus_cfg.get("testbench_sources", []) or ["tb/**/*.v", "tb/**/*.sv"])

    rtl_sources = resolve_sources(variant_path, rtl_patterns)
    tb_sources = resolve_sources(variant_path, tb_patterns)

    icarus_enabled = as_bool(icarus_cfg.get("enabled"), default_tb_enabled(variant_path))
    yosys_enabled = as_bool(yosys_cfg.get("enabled"), True)

    meta: Dict[str, Any] = {
        "variant_path": repo_rel(variant_path),
        "safe_variant": safe_variant,
        "variant_name": str(variant_cfg.get("name") or variant_path.name),
        "pdk": str(variant_cfg.get("pdk") or "sky130A"),
        "top_module": str(variant_cfg.get("top_module") or "").strip(),
        "clock_port": str(clock_cfg.get("port") or "clk"),
        "clock_mode": str(clock_cfg.get("mode") or "auto"),
        "clock_max_ns_cap": float(clock_cfg.get("max_ns_cap") or 200),
        "synth_strategy": str(ll_policy.get("synth_strategy") or "").strip(),
        "rtl_source_patterns": rtl_patterns,
        "rtl_sources": rtl_sources,
        "rtl_source_count": len(rtl_sources),
        "precheck": {
            "icarus": {
                "enabled": icarus_enabled,
                "testbench_top": str(icarus_cfg.get("testbench_top") or "").strip(),
                "testbench_source_patterns": tb_patterns,
                "testbench_sources": tb_sources,
                "testbench_source_count": len(tb_sources),
                "vcd_name": str(icarus_cfg.get("vcd_name") or "rtl_precheck.vcd").strip(),
                "stop_on_fail": as_bool(icarus_cfg.get("stop_on_fail"), True),
            },
            "yosys": {
                "enabled": yosys_enabled,
                "stop_on_fail": as_bool(yosys_cfg.get("stop_on_fail"), True),
                "mode": str(yosys_cfg.get("mode") or "structural").strip() or "structural",
            },
        },
    }

    if not meta["top_module"]:
        raise SystemExit(f"Missing top_module in {variant_path / 'variant.yaml'}")
    if not rtl_sources:
        raise SystemExit(f"No RTL sources resolved from {variant_path / 'variant.yaml'}")

    return meta


def emit_github_output(path: Path, payload: Dict[str, Any]) -> None:
    lines: List[str] = []
    simple_keys = {
        "variant_path": payload["variant_path"],
        "safe_variant": payload["safe_variant"],
        "variant_name": payload["variant_name"],
        "pdk": payload["pdk"],
        "top_module": payload["top_module"],
        "clock_port": payload["clock_port"],
        "clock_mode": payload["clock_mode"],
        "clock_max_ns_cap": payload["clock_max_ns_cap"],
        "synth_strategy": payload["synth_strategy"],
        "icarus_enabled": payload["precheck"]["icarus"]["enabled"],
        "tb_top": payload["precheck"]["icarus"]["testbench_top"],
        "vcd_name": payload["precheck"]["icarus"]["vcd_name"],
        "icarus_stop_on_fail": payload["precheck"]["icarus"]["stop_on_fail"],
        "yosys_enabled": payload["precheck"]["yosys"]["enabled"],
        "yosys_mode": payload["precheck"]["yosys"]["mode"],
        "yosys_stop_on_fail": payload["precheck"]["yosys"]["stop_on_fail"],
    }
    for key, value in simple_keys.items():
        lines.append(f"{key}={value}")

    json_keys = {
        "rtl_sources_json": payload["rtl_sources"],
        "tb_sources_json": payload["precheck"]["icarus"]["testbench_sources"],
        "resolved_meta_json": payload,
    }
    for key, value in json_keys.items():
        lines.append(f"{key}<<__JSON__")
        lines.append(json.dumps(value))
        lines.append("__JSON__")

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description="Resolve the active variant and its precheck metadata.")
    ap.add_argument("--variant", default="", help="Optional safe variant name or designs/<variant> path")
    ap.add_argument("--out", default="", help="Optional JSON output path")
    ap.add_argument("--github-output", default="", help="Optional GITHUB_OUTPUT path")
    args = ap.parse_args()

    variant_path = resolve_variant_path(str(args.variant or "").strip() or None)
    payload = build_meta(variant_path)

    text = json.dumps(payload, indent=2)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text, encoding="utf-8")
    else:
        print(text)

    if args.github_output:
        emit_github_output(Path(args.github_output), payload)


if __name__ == "__main__":
    main()
