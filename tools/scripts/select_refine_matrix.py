#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


PASS_STATUS = "SIGNOFF_PASS"
PASS_STATUSES = {PASS_STATUS}
FLOWLIKE_STATUSES = {"FLOW_FAIL", "METRICS_MISSING", "INCOMPLETE"}
CLASSIFIED_FAIL_STATUSES = {
    "FLOW_COMPLETED_TIMING_FAIL",
    "FLOW_COMPLETED_ELECTRICAL_FAIL",
    "FLOW_COMPLETED_SIGNOFF_FAIL",
    "FLOW_COMPLETED_TIMING_AND_SIGNOFF_FAIL",
}


def to_float(v: Any) -> Optional[float]:
    try:
        if v in (None, "", "None"):
            return None
        return float(v)
    except Exception:
        return None


def fmt(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else str(round(v, 6))


def read_csv_row(path: Path) -> Optional[Dict[str, str]]:
    if not path.exists():
        return None
    with path.open("r", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return rows[0] if rows else None


def classify_status(row: Dict[str, str]) -> str:
    raw_status = str(row.get("status", "")).strip().upper()
    if raw_status in {PASS_STATUS, *FLOWLIKE_STATUSES, *CLASSIFIED_FAIL_STATUSES}:
        return raw_status

    required = (
        "setup_wns_ns",
        "setup_tns_ns",
        "hold_wns_ns",
        "hold_tns_ns",
        "setup_vio_count",
        "hold_vio_count",
        "max_slew_violation_count",
        "max_cap_violation_count",
        "drc_errors",
        "lvs_errors",
        "antenna_violations",
    )
    if any(to_float(row.get(key)) is None for key in required):
        return "METRICS_MISSING"

    setup_wns = to_float(row.get("setup_wns_ns"))
    setup_tns = to_float(row.get("setup_tns_ns"))
    hold_wns = to_float(row.get("hold_wns_ns"))
    hold_tns = to_float(row.get("hold_tns_ns"))
    setup_vio = to_float(row.get("setup_vio_count"))
    hold_vio = to_float(row.get("hold_vio_count"))
    max_slew = to_float(row.get("max_slew_violation_count"))
    max_cap = to_float(row.get("max_cap_violation_count"))
    drc = to_float(row.get("drc_errors"))
    lvs = to_float(row.get("lvs_errors"))
    ant = to_float(row.get("antenna_violations"))

    timing_setup_pass = setup_wns >= 0.0 and setup_tns >= 0.0 and setup_vio == 0.0
    timing_hold_pass = hold_wns >= 0.0 and hold_tns >= 0.0 and hold_vio == 0.0
    electrical_pass = max_slew == 0.0 and max_cap == 0.0
    physical_pass = drc == 0.0 and lvs == 0.0 and ant == 0.0

    if timing_setup_pass and timing_hold_pass and electrical_pass and physical_pass:
        return PASS_STATUS
    if (not timing_setup_pass or not timing_hold_pass) and (not electrical_pass or not physical_pass):
        return "FLOW_COMPLETED_TIMING_AND_SIGNOFF_FAIL"
    if not timing_setup_pass or not timing_hold_pass:
        return "FLOW_COMPLETED_TIMING_FAIL"
    if not electrical_pass:
        return "FLOW_COMPLETED_ELECTRICAL_FAIL"
    return "FLOW_COMPLETED_SIGNOFF_FAIL"


def collect_rows(artifacts_root: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    seen: Set[Tuple[float, str]] = set()
    patterns = [
        "**/clk_*ns_attempt_*/metrics.csv",
        "**/ci_out/*/clk_*ns_attempt_*/metrics.csv",
        "**/*/clk_*ns_attempt_*/metrics.csv",
    ]

    for pattern in patterns:
        for csv_path in sorted(artifacts_root.glob(pattern)):
            row = read_csv_row(csv_path)
            if not row:
                continue

            clock_ns = to_float(row.get("clock_ns"))
            if clock_ns is None:
                continue

            key = (round(clock_ns, 6), str(csv_path))
            if key in seen:
                continue
            seen.add(key)

            rows.append(
                {
                    "clock_ns": round(clock_ns, 6),
                    "status": classify_status(row),
                    "raw_status": str(row.get("status", "")).strip().upper(),
                    "path": str(csv_path),
                }
            )

    return rows


def unique_sorted_desc(values: List[float]) -> List[float]:
    return sorted({round(v, 6) for v in values}, reverse=True)


def unique_sorted_asc(values: List[float]) -> List[float]:
    return sorted({round(v, 6) for v in values})


def write_output(matrix: List[float], reason: str, github_output: Optional[Path]) -> None:
    matrix_json = json.dumps(matrix)
    print(matrix_json)
    print(reason)
    if github_output is not None:
        with github_output.open("a", encoding="utf-8") as f:
            print(f"matrix_json={matrix_json}", file=f)
            print(f"reason={reason}", file=f)


def build_between(lower_fail: float, upper_pass: float, step_ns: float, existing: Set[float], batch_size: int) -> List[float]:
    candidates: List[float] = []
    current = upper_pass - step_ns
    while current > lower_fail and len(candidates) < batch_size:
        c = round(current, 6)
        if c not in existing:
            candidates.append(c)
        current -= step_ns
    return unique_sorted_desc(candidates)


def extend_downward(lowest_pass: float, step_ns: float, min_clock_ns: float, existing: Set[float], batch_size: int) -> List[float]:
    candidates: List[float] = []
    current = lowest_pass - step_ns
    while current >= min_clock_ns and len(candidates) < batch_size:
        c = round(current, 6)
        if c not in existing:
            candidates.append(c)
        current -= step_ns
    return unique_sorted_desc(candidates)


def extend_upward(highest_tested: float, step_ns: float, max_clock_ns: float, existing: Set[float], batch_size: int) -> List[float]:
    candidates: List[float] = []
    current = highest_tested + step_ns
    while current <= max_clock_ns and len(candidates) < batch_size:
        c = round(current, 6)
        if c not in existing:
            candidates.append(c)
        current += step_ns
    return unique_sorted_asc(candidates)


def analyze(rows: List[Dict[str, Any]]) -> Tuple[List[float], List[float], Optional[float], Optional[float]]:
    existing = sorted({row["clock_ns"] for row in rows})
    passes = sorted(row["clock_ns"] for row in rows if row["status"] in PASS_STATUSES)
    non_flow = sorted(row["clock_ns"] for row in rows if row["status"] not in FLOWLIKE_STATUSES)

    lowest_pass = min(passes) if passes else None
    highest_fail_below_pass = None
    if lowest_pass is not None:
        classified_fails = [
            row["clock_ns"]
            for row in rows
            if row["status"] in CLASSIFIED_FAIL_STATUSES and row["clock_ns"] < lowest_pass
        ]
        if classified_fails:
            highest_fail_below_pass = max(classified_fails)

    return existing, non_flow, lowest_pass, highest_fail_below_pass


def main() -> None:
    ap = argparse.ArgumentParser(description="Select next clock matrix for refine or extension stages")
    ap.add_argument("--artifacts-root", type=Path, required=True)
    ap.add_argument("--mode", choices=["extend", "refine"], required=True)
    ap.add_argument("--step-ns", type=float, required=True)
    ap.add_argument("--min-clock-ns", type=float, required=True)
    ap.add_argument("--max-clock-ns", type=float, required=True)
    ap.add_argument("--tolerance-ns", type=float, required=True)
    ap.add_argument("--batch-size", type=int, default=4)
    ap.add_argument("--github-output", type=Path, default=None)
    args = ap.parse_args()

    rows = collect_rows(args.artifacts_root)
    if not rows:
        write_output([], "No metrics artifacts found yet.", args.github_output)
        return

    existing, non_flow, lowest_pass, highest_fail_below_pass = analyze(rows)
    existing_set = {round(v, 6) for v in existing}

    if not non_flow:
        write_output([], "All observed results are FLOW_FAIL or METRICS_MISSING, so refinement stops instead of expanding upward.", args.github_output)
        return

    if args.mode == "extend":
        if lowest_pass is not None and highest_fail_below_pass is not None:
            interval = lowest_pass - highest_fail_below_pass
            if interval <= args.tolerance_ns:
                write_output([], f"Existing pass/fail bracket [{fmt(highest_fail_below_pass)}, {fmt(lowest_pass)}] is already within tolerance.", args.github_output)
                return

            matrix = build_between(highest_fail_below_pass, lowest_pass, args.step_ns, existing_set, args.batch_size)
            write_output(matrix, f"Same-step extension/refinement at {fmt(args.step_ns)} ns inside existing bracket [{fmt(highest_fail_below_pass)}, {fmt(lowest_pass)}].", args.github_output)
            return

        if lowest_pass is not None:
            matrix = extend_downward(lowest_pass, args.step_ns, args.min_clock_ns, existing_set, args.batch_size)
            write_output(matrix, f"All true signoff passes still hold down to {fmt(lowest_pass)} ns, so extend downward at the same {fmt(args.step_ns)} ns step.", args.github_output)
            return

        highest_tested = max(non_flow)
        if highest_tested >= args.max_clock_ns:
            write_output([], f"No SIGNOFF_PASS point found and the highest tested classified point {fmt(highest_tested)} ns already reached the variant cap {fmt(args.max_clock_ns)} ns.", args.github_output)
            return

        matrix = extend_upward(highest_tested, args.step_ns, args.max_clock_ns, existing_set, args.batch_size)
        write_output(matrix, f"No SIGNOFF_PASS point found yet, so extend upward at the same {fmt(args.step_ns)} ns step from {fmt(highest_tested)} ns toward the cap.", args.github_output)
        return

    if lowest_pass is None or highest_fail_below_pass is None:
        if lowest_pass is not None:
            write_output([], f"Refine stage at {fmt(args.step_ns)} ns is skipped because there is no classified fail below the current lowest SIGNOFF_PASS {fmt(lowest_pass)} ns yet.", args.github_output)
        else:
            write_output([], f"Refine stage at {fmt(args.step_ns)} ns is skipped because no SIGNOFF_PASS point exists yet.", args.github_output)
        return

    interval = lowest_pass - highest_fail_below_pass
    if interval <= args.tolerance_ns:
        write_output([], f"Existing pass/fail bracket [{fmt(highest_fail_below_pass)}, {fmt(lowest_pass)}] is already within tolerance.", args.github_output)
        return

    matrix = build_between(highest_fail_below_pass, lowest_pass, args.step_ns, existing_set, args.batch_size)
    write_output(matrix, f"Refining inside bracket [{fmt(highest_fail_below_pass)}, {fmt(lowest_pass)}] with {fmt(args.step_ns)} ns step.", args.github_output)


if __name__ == "__main__":
    main()
