#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shlex
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Sequence


ROOT = Path(__file__).resolve().parents[2]


def quote_cmd(parts: Sequence[str]) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def unique_include_dirs(paths: List[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for rel in paths:
        parent = str((ROOT / rel).parent.resolve())
        if parent not in seen:
            seen.add(parent)
            out.append(parent)
    return out


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def run_command(cmd: Sequence[str], *, cwd: Path, log_path: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        list(cmd),
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log_path.write_text(result.stdout or "", encoding="utf-8")
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description="Run the Icarus RTL precheck and emit status metadata.")
    ap.add_argument("--meta-json", required=True)
    ap.add_argument("--out-dir", default="precheck/rtl")
    args = ap.parse_args()

    meta = json.loads(Path(args.meta_json).read_text(encoding="utf-8"))
    cfg = meta.get("precheck", {}).get("icarus", {}) or {}

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    compile_log = out_dir / "compile.log"
    run_log = out_dir / "run.log"
    status_path = out_dir / "status.json"
    meta_path = out_dir / "precheck_meta.json"
    simv_path = out_dir / "simv"

    enabled = bool(cfg.get("enabled", False))
    tb_top = str(cfg.get("testbench_top") or "").strip()
    rtl_sources = list(meta.get("rtl_sources", []) or [])
    tb_sources = list(cfg.get("testbench_sources", []) or [])
    vcd_name = str(cfg.get("vcd_name") or "rtl_precheck.vcd").strip() or "rtl_precheck.vcd"
    vcd_path = out_dir / Path(vcd_name).name

    precheck_meta = {
        "variant_path": meta.get("variant_path", ""),
        "safe_variant": meta.get("safe_variant", ""),
        "top_module": meta.get("top_module", ""),
        "testbench_top": tb_top,
        "rtl_sources": rtl_sources,
        "testbench_sources": tb_sources,
        "vcd_name": Path(vcd_name).name,
        "tool": "icarus",
        "enabled": enabled,
    }

    if not enabled:
        compile_log.write_text("Icarus precheck disabled by variant.yaml\n", encoding="utf-8")
        run_log.write_text("Icarus precheck disabled by variant.yaml\n", encoding="utf-8")
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "icarus",
            "enabled": False,
            "status": "SKIP",
            "passed": True,
            "compile_pass": False,
            "run_pass": False,
            "vcd_present": False,
            "reason": "disabled",
        })
        return

    if not tb_top:
        compile_log.write_text("Missing precheck.icarus.testbench_top in variant.yaml\n", encoding="utf-8")
        run_log.write_text("Simulation not started because the testbench top is missing.\n", encoding="utf-8")
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "icarus",
            "enabled": True,
            "status": "FAIL",
            "passed": False,
            "compile_pass": False,
            "run_pass": False,
            "vcd_present": False,
            "reason": "missing_testbench_top",
        })
        return

    if not tb_sources:
        compile_log.write_text("No testbench sources resolved from precheck.icarus.testbench_sources\n", encoding="utf-8")
        run_log.write_text("Simulation not started because no TB sources were resolved.\n", encoding="utf-8")
        write_json(meta_path, precheck_meta)
        write_json(status_path, {
            "tool": "icarus",
            "enabled": True,
            "status": "FAIL",
            "passed": False,
            "compile_pass": False,
            "run_pass": False,
            "vcd_present": False,
            "reason": "missing_testbench_sources",
        })
        return

    include_dirs = unique_include_dirs(rtl_sources + tb_sources)
    compile_cmd: List[str] = ["iverilog", "-g2012", "-o", str(simv_path), "-s", tb_top]
    for inc in include_dirs:
        compile_cmd.extend(["-I", inc])
    compile_cmd.extend(str(ROOT / rel) for rel in rtl_sources)
    compile_cmd.extend(str(ROOT / rel) for rel in tb_sources)

    compile_result = run_command(compile_cmd, cwd=ROOT, log_path=compile_log)

    # IMPORTANT FIX:
    # run from out_dir, so execute the local simv binary directly
    run_cmd = ["vvp", "simv"]
    if compile_result.returncode == 0:
        run_result = run_command(run_cmd, cwd=out_dir, log_path=run_log)
        run_rc = run_result.returncode
        run_pass = run_rc == 0
    else:
        run_log.write_text("Simulation skipped because compile failed.\n", encoding="utf-8")
        run_rc = None
        run_pass = False

    vcd_present = vcd_path.exists()
    passed = compile_result.returncode == 0 and run_pass and vcd_present
    reason = "ok"
    if compile_result.returncode != 0:
        reason = "compile_failed"
    elif not run_pass:
        reason = "run_failed"
    elif not vcd_present:
        reason = "missing_vcd"

    precheck_meta.update({
        "compile_cmd": quote_cmd(compile_cmd),
        "run_cmd": quote_cmd(run_cmd),
        "compile_log": str(compile_log),
        "run_log": str(run_log),
        "vcd_path": str(vcd_path),
    })

    write_json(meta_path, precheck_meta)
    write_json(status_path, {
        "tool": "icarus",
        "enabled": True,
        "status": "PASS" if passed else "FAIL",
        "passed": passed,
        "compile_pass": compile_result.returncode == 0,
        "compile_rc": compile_result.returncode,
        "run_pass": run_pass,
        "run_rc": run_rc,
        "vcd_present": vcd_present,
        "vcd_name": Path(vcd_name).name,
        "variant_path": meta.get("variant_path", ""),
        "safe_variant": meta.get("safe_variant", ""),
        "top_module": meta.get("top_module", ""),
        "testbench_top": tb_top,
        "reason": reason,
    })


if __name__ == "__main__":
    main()