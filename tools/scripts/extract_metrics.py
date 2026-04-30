#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Dict, Optional


REQUIRED_SIGNOFF_FIELDS = (
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


def load_json(p: Path) -> Dict[str, Any]:
    return json.loads(p.read_text(encoding="utf-8"))


def read_csv_row(path: Path) -> Optional[Dict[str, str]]:
    if not path.exists():
        return None
    with path.open("r", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return rows[0] if rows else None


def load_metrics(run: Path) -> Dict[str, Any]:
    candidates = [
        run / "final" / "metrics.json",
        run / "final" / "metrics_raw.json",
        run / "final" / "metrics.csv",
    ]
    for path in candidates:
        if not path.exists():
            continue
        try:
            if path.suffix == ".csv":
                return read_csv_row(path) or {}
            return load_json(path)
        except Exception:
            continue
    return {}


def first(metrics: Dict[str, Any], *keys: str) -> Any:
    for k in keys:
        if k in metrics and metrics[k] not in (None, ""):
            return metrics[k]
    return None


def to_float(value: Any) -> Optional[float]:
    try:
        if value in (None, "", "None"):
            return None
        return float(value)
    except Exception:
        return None


def to_count(value: Any) -> Optional[int]:
    parsed = to_float(value)
    if parsed is None:
        return None
    return int(parsed)


def max_present(*values: Any) -> Any:
    present = [to_float(v) for v in values if to_float(v) is not None]
    if not present:
        return None
    best = max(present)
    return int(best) if float(best).is_integer() else best


def parse_openroad_power_rpt(p: Path) -> Optional[Dict[str, float]]:
    lines = p.read_text(errors="ignore").splitlines()
    for line in lines:
        s = line.strip()
        if s.startswith("Total"):
            parts = s.split()
            if len(parts) >= 5:
                try:
                    return {
                        "internal_W": float(parts[1]),
                        "switching_W": float(parts[2]),
                        "leakage_W": float(parts[3]),
                        "total_W": float(parts[4]),
                    }
                except Exception:
                    return None
    return None


def sanitize_power_value(value: Any) -> Optional[float]:
    parsed = to_float(value)
    if parsed is None:
        return None
    if parsed < 0.0 or abs(parsed) > 1_000_000.0:
        return None
    return parsed


def sanitize_ir_value(value: Any) -> Optional[float]:
    parsed = to_float(value)
    if parsed is None:
        return None
    if parsed < 0.0 or parsed > 10.0:
        return None
    return parsed


def missing_required_fields(row: Dict[str, Any]) -> list[str]:
    return [field for field in REQUIRED_SIGNOFF_FIELDS if to_float(row.get(field)) is None]


def status_from_row(row: Dict[str, Any]) -> str:
    missing = missing_required_fields(row)
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
    physical_signoff_pass = drc == 0.0 and lvs == 0.0 and ant == 0.0

    if timing_setup_pass and timing_hold_pass and electrical_pass and physical_signoff_pass:
        return "SIGNOFF_PASS"
    if (not timing_setup_pass or not timing_hold_pass) and (not electrical_pass or not physical_signoff_pass):
        return "FLOW_COMPLETED_TIMING_AND_SIGNOFF_FAIL"
    if not timing_setup_pass or not timing_hold_pass:
        return "FLOW_COMPLETED_TIMING_FAIL"
    if not electrical_pass:
        return "FLOW_COMPLETED_ELECTRICAL_FAIL"
    return "FLOW_COMPLETED_SIGNOFF_FAIL"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run", type=Path, help="Run folder containing final metrics")
    ap.add_argument("--out", type=Path, required=True, help="Output directory")
    ap.add_argument("--clock-ns", type=float, default=None, help="Requested clock period from workflow")
    args = ap.parse_args()

    run = args.run
    out = args.out
    out.mkdir(parents=True, exist_ok=True)

    metrics_path = (
        run / "final" / "metrics.json"
        if (run / "final" / "metrics.json").exists()
        else (run / "final" / "metrics_raw.json" if (run / "final" / "metrics_raw.json").exists() else (run / "final" / "metrics.csv"))
    )
    power_rpt = run / "power" / "power.rpt"
    fair_rpt = run / "power" / "power_fair_sta.rpt"

    metrics = load_metrics(run)

    clock_from_metrics = first(
        metrics,
        "clock__period",
        "clock__period__corner:nom_tt_025C_1v80",
    )

    drc_route = first(metrics, "route__drc_errors")
    drc_klayout = first(metrics, "klayout__drc_error__count")
    drc_magic = first(metrics, "magic__drc_error__count")
    lvs_errors = first(metrics, "design__lvs_error__count", "netgen__lvs_error__count")
    antenna_route = first(metrics, "route__antenna_violation__count")
    antenna_nets = first(metrics, "antenna__violating__nets")
    antenna_pins = first(metrics, "antenna__violating__pins")

    row: Dict[str, Any] = {
        "clock_ns": args.clock_ns if args.clock_ns is not None else clock_from_metrics,
        "clock_ns_reported": clock_from_metrics,
        "setup_wns_ns": first(
            metrics,
            "timing__setup__wns",
            "timing__setup__wns__worst",
            "timing__setup__wns__corner:nom_tt_025C_1v80",
        ),
        "setup_tns_ns": first(
            metrics,
            "timing__setup__tns",
            "timing__setup__tns__worst",
            "timing__setup__tns__corner:nom_tt_025C_1v80",
        ),
        "hold_wns_ns": first(
            metrics,
            "timing__hold__wns",
            "timing__hold__wns__worst",
            "timing__hold__wns__corner:nom_tt_025C_1v80",
        ),
        "hold_tns_ns": first(
            metrics,
            "timing__hold__tns",
            "timing__hold__tns__worst",
            "timing__hold__tns__corner:nom_tt_025C_1v80",
        ),
        "setup_vio_count": first(metrics, "timing__setup_vio__count"),
        "hold_vio_count": first(metrics, "timing__hold_vio__count"),
        "max_slew_violation_count": first(metrics, "design__max_slew_violation__count"),
        "max_cap_violation_count": first(metrics, "design__max_cap_violation__count"),
        "core_area_um2": first(metrics, "design__core__area", "floorplan__core__area"),
        "die_area_um2": first(metrics, "design__die__area", "floorplan__die__area"),
        "instance_count": first(metrics, "design__instance__count"),
        "utilization_pct": first(
            metrics,
            "design__instance__utilization",
            "design__utilization",
            "floorplan__utilization",
        ),
        "wire_length_um": first(
            metrics,
            "route__wirelength",
            "detailedroute__wirelength",
            "globalroute__wirelength",
        ),
        "vias_count": first(
            metrics,
            "route__vias",
            "detailedroute__via__count",
            "globalroute__via__count",
        ),
        "drc_errors": max_present(drc_route, drc_klayout, drc_magic),
        "drc_errors_route": drc_route,
        "drc_errors_klayout": drc_klayout,
        "drc_errors_magic": drc_magic,
        "lvs_errors": lvs_errors,
        "antenna_violations": max_present(antenna_route, antenna_nets, antenna_pins),
        "antenna_violations_route": antenna_route,
        "antenna_violating_nets": antenna_nets,
        "antenna_violating_pins": antenna_pins,
        "ir_drop_worst_V": sanitize_ir_value(first(metrics, "ir__drop__worst")),
        "ir_status": "OK" if sanitize_ir_value(first(metrics, "ir__drop__worst")) is not None or first(metrics, "ir__drop__worst") in (None, "", "None") else "INVALID",
    }

    p = parse_openroad_power_rpt(power_rpt) if power_rpt.exists() else None
    if p:
        row["power_total_W"] = sanitize_power_value(p["total_W"])
        row["power_internal_W"] = sanitize_power_value(p["internal_W"])
        row["power_switching_W"] = sanitize_power_value(p["switching_W"])
        row["power_leakage_W"] = sanitize_power_value(p["leakage_W"])
        row["power_source"] = str(power_rpt)
        row["power_status"] = (
            "OK"
            if all(
                sanitize_power_value(p[key]) is not None
                for key in ("total_W", "internal_W", "switching_W", "leakage_W")
            )
            else "INVALID"
        )
    else:
        total = sanitize_power_value(first(metrics, "power__total"))
        internal = sanitize_power_value(first(metrics, "power__internal"))
        switching = sanitize_power_value(first(metrics, "power__switching"))
        leakage = sanitize_power_value(first(metrics, "power__leakage"))
        row["power_total_W"] = total
        row["power_internal_W"] = internal
        row["power_switching_W"] = switching
        row["power_leakage_W"] = leakage
        row["power_source"] = "metrics.json" if metrics else None
        raw_power_values = [first(metrics, "power__total"), first(metrics, "power__internal"), first(metrics, "power__switching"), first(metrics, "power__leakage")]
        row["power_status"] = (
            "OK"
            if any(v not in (None, "", "None") for v in raw_power_values) and all(
                sanitize_power_value(v) is not None for v in raw_power_values if v not in (None, "", "None")
            )
            else ("INVALID" if any(v not in (None, "", "None") for v in raw_power_values) else None)
        )

    row["power_fair_sta_rpt"] = str(fair_rpt) if fair_rpt.exists() else None
    row["status"] = status_from_row(row)

    field_order = [
        "clock_ns",
        "clock_ns_reported",
        "setup_wns_ns",
        "setup_tns_ns",
        "hold_wns_ns",
        "hold_tns_ns",
        "setup_vio_count",
        "hold_vio_count",
        "max_slew_violation_count",
        "max_cap_violation_count",
        "core_area_um2",
        "die_area_um2",
        "instance_count",
        "utilization_pct",
        "wire_length_um",
        "vias_count",
        "power_total_W",
        "power_internal_W",
        "power_switching_W",
        "power_leakage_W",
        "power_source",
        "power_status",
        "drc_errors",
        "drc_errors_route",
        "drc_errors_klayout",
        "drc_errors_magic",
        "lvs_errors",
        "antenna_violations",
        "antenna_violations_route",
        "antenna_violating_nets",
        "antenna_violating_pins",
        "ir_drop_worst_V",
        "ir_status",
        "power_fair_sta_rpt",
        "status",
    ]

    csv_path = out / "metrics.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=field_order)
        w.writeheader()
        w.writerow({k: row.get(k) for k in field_order})

    def fmt(v: Any) -> str:
        return "" if v is None else str(v)

    md_lines = [
        "| " + " | ".join(field_order) + " |",
        "|" + "|".join(["---"] * len(field_order)) + "|",
        "| " + " | ".join(fmt(row.get(k)) for k in field_order) + " |",
        "",
    ]
    (out / "metrics.md").write_text("\n".join(md_lines), encoding="utf-8")

    prov = [
        f"run={run}",
        f"metrics={metrics_path if metrics_path.exists() else '(missing)'}",
        f"power_rpt={power_rpt if power_rpt.exists() else '(missing)'}",
        f"fair_sta={fair_rpt if fair_rpt.exists() else '(none)'}",
        f"clock_ns_requested={args.clock_ns}",
    ]
    (out / "provenance.txt").write_text("\n".join(prov) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
