#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[2]
AUTOFLOW = ROOT / "tools" / "scripts" / "autoflow.py"


def q(parts: Sequence[str]) -> str:
    return " ".join(shlex.quote(str(p)) for p in parts)


def run(cmd: List[str], extra_env: Dict[str, str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(extra_env)
    return subprocess.run(
        cmd,
        cwd=str(ROOT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def normalized_variant_dir(variant: str) -> str:
    value = str(variant or "").strip()
    if not value:
        raise SystemExit("Missing --variant")
    return value.replace("/", "_")


def out_root_for(variant: str) -> str:
    return f"ci_out/{normalized_variant_dir(variant)}"


def build_attempts(args: argparse.Namespace) -> List[Tuple[str, List[str]]]:
    common = [
        "--variant", args.variant,
        "--clock-ns", str(args.clock_ns),
        "--min-clock-ns", str(args.clock_ns),
        "--max-clock-ns", str(args.clock_ns),
        "--initial-step-ns", "1",
        "--tolerance-ns", "0.000001",
        "--max-iters", "1",
        "--out-root", out_root_for(args.variant),
        "--stage-label", args.stage_label,
    ]

    if args.pdk_root.strip():
        common.extend(["--pdk-root", args.pdk_root])
    if args.openlane_image.strip():
        common.extend(["--openlane-image", args.openlane_image])
    if args.synth_strategy.strip():
        common.extend(["--synth-strategy", args.synth_strategy])

    optional_pairs = [
        ("--run-antenna-repair", args.run_antenna_repair),
        ("--run-heuristic-diode-insertion", args.run_heuristic_diode_insertion),
        ("--run-post-grt-design-repair", args.run_post_grt_design_repair),
        ("--run-post-grt-resizer-timing", args.run_post_grt_resizer_timing),
        ("--gpl-cell-padding", args.gpl_cell_padding),
    ]
    for flag, value in optional_pairs:
        if str(value).strip() != "":
            common.extend([flag, str(value)])

    cmd = [sys.executable, str(AUTOFLOW), *common]
    return [
        ("dash", cmd),
    ]


def is_cli_contract_error(text: str) -> bool:
    lowered = text.lower()
    return (
        "unrecognized arguments" in lowered
        or lowered.startswith("usage:")
        or "error:" in lowered
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Compatibility wrapper around the existing autoflow.py CLI.")
    ap.add_argument("--variant", required=True)
    ap.add_argument("--clock-ns", required=True, dest="clock_ns")
    ap.add_argument("--pdk-root", default=os.environ.get("PDK_ROOT", os.environ.get("VOLARE_DIR", "")))
    ap.add_argument("--openlane-image", default=os.environ.get("OPENLANE_IMAGE", ""))
    ap.add_argument("--stage-label", default="coarse")
    ap.add_argument("--artifact-name", default="")
    ap.add_argument("--synth-strategy", default="")
    ap.add_argument("--run-antenna-repair", default="")
    ap.add_argument("--run-heuristic-diode-insertion", default="")
    ap.add_argument("--run-post-grt-design-repair", default="")
    ap.add_argument("--run-post-grt-resizer-timing", default="")
    ap.add_argument("--gpl-cell-padding", default="")
    args = ap.parse_args()

    if not AUTOFLOW.exists():
        raise SystemExit(f"Missing {AUTOFLOW}")
    if not str(args.openlane_image).strip():
        raise SystemExit("Missing --openlane-image (or OPENLANE_IMAGE environment variable).")
    if not str(args.pdk_root).strip():
        raise SystemExit("Missing --pdk-root (or PDK_ROOT / VOLARE_DIR environment variable).")

    out_root = out_root_for(args.variant)
    extra_env = {
        "AUTOFLOW_VARIANT": args.variant,
        "AUTOFLOW_CLOCK_NS": str(args.clock_ns),
        "AUTOFLOW_STAGE_LABEL": args.stage_label,
        "AUTOFLOW_ARTIFACT_NAME": args.artifact_name,
        "AUTOFLOW_PDK_ROOT": args.pdk_root,
        "AUTOFLOW_OPENLANE_IMAGE": args.openlane_image,
        "AUTOFLOW_OUT_ROOT": out_root,
    }

    attempts = build_attempts(args)
    last: subprocess.CompletedProcess[str] | None = None
    for idx, (profile_name, cmd) in enumerate(attempts, start=1):
        result = run(cmd, extra_env)
        sys.stdout.write(f"\n[run_autoflow_compat] Attempt {idx} ({profile_name}): {q(cmd)}\n")
        sys.stdout.write(result.stdout or "")
        if result.returncode == 0:
            return
        last = result
        if not is_cli_contract_error(result.stdout or ""):
            break

    raise SystemExit(last.returncode if last is not None else 1)


if __name__ == "__main__":
    main()
