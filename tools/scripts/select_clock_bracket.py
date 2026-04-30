#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


PASS_STATUS = "SIGNOFF_PASS"
NONFLOW_FAIL_STATUSES = {
    "FLOW_COMPLETED_TIMING_FAIL",
    "FLOW_COMPLETED_ELECTRICAL_FAIL",
    "FLOW_COMPLETED_SIGNOFF_FAIL",
    "FLOW_COMPLETED_TIMING_AND_SIGNOFF_FAIL",
}
FLOWLIKE_STATUSES = {"FLOW_FAIL", "METRICS_MISSING", "INCOMPLETE"}


def to_float(value: Any) -> Optional[float]:
    try:
        if value in (None, "", "None"):
            return None
        return float(value)
    except Exception:
        return None


def fmt_num(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return str(round(value, 6))


def read_csv_row(path: Path) -> Optional[Dict[str, str]]:
    if not path.exists():
        return None
    with path.open("r", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return rows[0] if rows else None


def classify_status(row: Dict[str, str]) -> str:
    raw_status = str(row.get("status", "")).strip().upper()
    if raw_status in {PASS_STATUS, *NONFLOW_FAIL_STATUSES, *FLOWLIKE_STATUSES}:
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
    missing = [key for key in required if to_float(row.get(key)) is None]
    if missing:
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


def status_rank(status: str) -> int:
    order = {
        PASS_STATUS: 0,
        "FLOW_COMPLETED_ELECTRICAL_FAIL": 1,
        "FLOW_COMPLETED_SIGNOFF_FAIL": 2,
        "FLOW_COMPLETED_TIMING_FAIL": 3,
        "FLOW_COMPLETED_TIMING_AND_SIGNOFF_FAIL": 4,
        "METRICS_MISSING": 5,
        "FLOW_FAIL": 6,
        "INCOMPLETE": 6,
    }
    return order.get(status, 99)


def collect_by_clock(artifacts_root: Path) -> Dict[float, str]:
    best_by_clock: Dict[float, str] = {}

    for csv_path in sorted(artifacts_root.glob("**/metrics.csv")):
        row = read_csv_row(csv_path)
        if not row:
            continue

        clock_ns = to_float(row.get("clock_ns"))
        if clock_ns is None:
            continue

        status = classify_status(row)
        key = round(clock_ns, 6)
        current = best_by_clock.get(key)
        if current is None or status_rank(status) < status_rank(current):
            best_by_clock[key] = status

    return best_by_clock


def compute_bracket(best_by_clock: Dict[float, str]) -> Tuple[Optional[float], Optional[float], str]:
    pass_clocks = sorted(clock for clock, status in best_by_clock.items() if status == PASS_STATUS)
    if not pass_clocks:
        return None, None, "NONE"

    upper_pass = min(pass_clocks)

    classified_fails = sorted(
        clock for clock, status in best_by_clock.items()
        if status in NONFLOW_FAIL_STATUSES and clock < upper_pass
    )
    if classified_fails:
        lower_clock = max(classified_fails)
        return upper_pass, lower_clock, best_by_clock[lower_clock]

    metrics_missing = sorted(
        clock for clock, status in best_by_clock.items()
        if status == "METRICS_MISSING" and clock < upper_pass
    )
    if metrics_missing:
        lower_clock = max(metrics_missing)
        return upper_pass, lower_clock, "METRICS_MISSING"

    flow_fails = sorted(
        clock for clock, status in best_by_clock.items()
        if status in {"FLOW_FAIL", "INCOMPLETE"} and clock < upper_pass
    )
    if flow_fails:
        lower_clock = max(flow_fails)
        return upper_pass, lower_clock, "FLOW_FAIL"

    return upper_pass, None, "NONE"


def build_downward_matrix(
    upper_pass: float,
    lower_fail: float,
    step_ns: float,
    best_by_clock: Dict[float, str],
) -> List[float]:
    tested = {round(clock, 6) for clock in best_by_clock.keys()}
    values: List[float] = []
    candidate = round(upper_pass - step_ns, 6)

    while candidate > round(lower_fail, 6):
        if candidate not in tested:
            values.append(candidate)
        candidate = round(candidate - step_ns, 6)

    return values


def write_outputs(
    github_output: Path,
    *,
    upper_pass: Optional[float],
    lower_fail: Optional[float],
    lower_fail_kind: str,
    matrix: List[float],
    reason: str,
) -> None:
    payload = [
        int(v) if float(v).is_integer() else round(v, 6)
        for v in matrix
    ]

    with github_output.open("a", encoding="utf-8") as f:
        print(f"upper_pass_clock_ns={fmt_num(upper_pass) if upper_pass is not None else ''}", file=f)
        print(f"lower_fail_clock_ns={fmt_num(lower_fail) if lower_fail is not None else ''}", file=f)
        print(f"lower_fail_kind={lower_fail_kind}", file=f)
        print(f"matrix_json={json.dumps(payload)}", file=f)
        print(f"reason={reason}", file=f)


def write_bracket_summaries(
    *,
    summary_md: Optional[Path],
    summary_json: Optional[Path],
    stage_label: str,
    next_stage_label: str,
    next_step_ns: Optional[float],
    upper_pass: float,
    lower_fail: float,
    lower_fail_kind: str,
    matrix: List[float],
    best_by_clock: Dict[float, str],
) -> None:
    pass_clocks = sorted(clock for clock, status in best_by_clock.items() if status == PASS_STATUS)
    fail_clocks = sorted(clock for clock, status in best_by_clock.items() if status != PASS_STATUS)
    bracket_width = round(upper_pass - lower_fail, 6)
    matrix_payload = [
        int(v) if float(v).is_integer() else round(v, 6)
        for v in matrix
    ]

    payload = {
        "stage_label": stage_label,
        "next_stage_label": next_stage_label,
        "next_step_ns": next_step_ns,
        "upper_pass": upper_pass,
        "lower_fail": lower_fail,
        "lower_fail_kind": lower_fail_kind,
        "bracket_width": bracket_width,
        "planned_next_clocks": matrix_payload,
        "pass_clocks": pass_clocks,
        "fail_clocks": fail_clocks,
        "reason": (
            f"{fmt_num(upper_pass)} ns is the fastest SIGNOFF_PASS found so far and "
            f"{fmt_num(lower_fail)} ns is the nearest non-pass point below it ({lower_fail_kind})."
        ),
    }

    if summary_json is not None:
        summary_json.parent.mkdir(parents=True, exist_ok=True)
        summary_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    if summary_md is not None:
        summary_md.parent.mkdir(parents=True, exist_ok=True)
        pass_str = ", ".join(fmt_num(v) for v in pass_clocks) if pass_clocks else "(none)"
        fail_str = ", ".join(fmt_num(v) for v in fail_clocks) if fail_clocks else "(none)"
        planned_str = ", ".join(fmt_num(v) for v in matrix_payload) if matrix_payload else "(none)"
        next_step_str = fmt_num(next_step_ns) if next_step_ns is not None else "n/a"
        lines = [
            "# Bracket decision summary",
            "",
            "## Stage completed",
            f"- Stage: {stage_label}",
            f"- Lower-fail classification used: {lower_fail_kind}",
            "",
            "## Results",
            f"- SIGNOFF_PASS clocks: {pass_str}",
            f"- Non-pass clocks: {fail_str}",
            "",
            "## Selected bracket",
            f"- upper_pass = {fmt_num(upper_pass)} ns",
            f"- lower_fail = {fmt_num(lower_fail)} ns",
            f"- bracket_width = {fmt_num(bracket_width)} ns",
            "",
            "## Next action",
            f"- Next stage: {next_stage_label}",
            f"- Next step size: {next_step_str} ns",
            f"- Planned clocks: {planned_str}",
            "",
            "## Reasoning",
            f"{fmt_num(upper_pass)} ns is the fastest signoff-clean point found so far.",
            f"{fmt_num(lower_fail)} ns is the nearest non-pass point below it.",
            f"Therefore the optimum boundary lies inside ({fmt_num(lower_fail)}, {fmt_num(upper_pass)}].",
        ]
        summary_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Select the current fastest SIGNOFF_PASS and highest non-pass-below-pass bracket from downloaded artifacts."
    )
    ap.add_argument("--artifacts-root", type=Path, required=True)
    ap.add_argument("--next-step-ns", type=float, default=None, help="If provided, emit a downward matrix between the bracket endpoints.")
    ap.add_argument("--stage-label", default="unspecified")
    ap.add_argument("--next-stage-label", default="next")
    ap.add_argument("--summary-md", type=Path, default=None)
    ap.add_argument("--summary-json", type=Path, default=None)
    ap.add_argument("--github-output", type=Path, required=True)
    args = ap.parse_args()

    best_by_clock = collect_by_clock(args.artifacts_root)
    if not best_by_clock:
        raise SystemExit("No metrics.csv files with a valid clock_ns were found under the artifacts root.")

    upper_pass, lower_fail, lower_fail_kind = compute_bracket(best_by_clock)

    if upper_pass is None:
        raise SystemExit("No SIGNOFF_PASS result was found. Increase the clock cap from variant.yaml or inspect the failing timing/signoff metrics.")

    if lower_fail is None:
        raise SystemExit(
            f"No non-pass point was found below the fastest SIGNOFF_PASS {fmt_num(upper_pass)} ns. "
            f"Lower the floor or inspect whether 0 ns is still signoff-clean."
        )

    matrix: List[float] = []
    if args.next_step_ns is not None:
        if args.next_step_ns <= 0:
            raise SystemExit("--next-step-ns must be > 0 when provided")
        matrix = build_downward_matrix(upper_pass, lower_fail, args.next_step_ns, best_by_clock)

    reason = (
        f"Using upper_pass={fmt_num(upper_pass)} ns and lower_fail={fmt_num(lower_fail)} ns "
        f"({lower_fail_kind}) from collected results."
    )

    write_outputs(
        args.github_output,
        upper_pass=upper_pass,
        lower_fail=lower_fail,
        lower_fail_kind=lower_fail_kind,
        matrix=matrix,
        reason=reason,
    )

    write_bracket_summaries(
        summary_md=args.summary_md,
        summary_json=args.summary_json,
        stage_label=args.stage_label,
        next_stage_label=args.next_stage_label,
        next_step_ns=args.next_step_ns,
        upper_pass=upper_pass,
        lower_fail=lower_fail,
        lower_fail_kind=lower_fail_kind,
        matrix=matrix,
        best_by_clock=best_by_clock,
    )


if __name__ == "__main__":
    main()
