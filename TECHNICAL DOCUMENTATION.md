# LibreLane Sky130PDK ASIC Toolchain — Technical Documentation

## 1. Introduction

This repository is a **variant-driven GitHub ASIC flow and run explorer** built for **Sky130 + OpenLane2 / LibreLane**. 

This repository is designed so that a user can:

- Place ASIC RTL inside a named design variant
- Keep testbench files separate from synthesis RTL
- Select the active experiment through `manifest.yaml`
- Let CI run prechecks and backend sweeps automatically
- Review the results through a lightweight static dashboard

---

## 2. Purpose of Repository

This repository is intended to be:

- **Variant-driven ASIC research workflow**
- **Repeatable GitHub Actions pipeline** for OpenLane2 / LibreLane on Sky130
- **Matrix-based timing exploration framework**
- **Run Explorer generator** for comparing results across timing points
- **Documentation-friendly evidence system** 


## 3. Design Philosophy

The underlying philosophy of the repo can be summarised in five ideas.

### 3.1 Variant-driven by design

Every design lives under its own folder in `designs/<variant_name>/` and is configured by its own `variant.yaml`. The repository is therefore organised around **named experiments**, not around ad hoc uploads.

### 3.2 User contract is simple and stable

The intended user-facing contract is:

- Put ASIC RTL into `src/`
- Put simulation/testbench sources into `tb/`
- Edit `variant.yaml`
- Select the active design in `manifest.yaml`
- Let CI do the rest

This keeps the repo clean and makes it easier to reuse across multiple designs.

### 3.3 Precheck is separate from backend ASIC flow

RTL simulation and structural synthesis sanity checks are treated as **prechecks**, not as the same thing as backend hardening. This keeps the flow conceptually clean:

- **Icarus** checks whether the RTL and testbench behave sufficiently to produce a VCD
- **Yosys** checks whether the ASIC RTL can be structurally elaborated and synthesised from the top module closure
- **OpenLane / LibreLane** handles the actual backend ASIC attempt

### 3.4 Matrix sweeps should remain visible

Timing exploration is deliberately kept **matrix-based and explicit**. Rather than using a hidden serial controller that silently mutates one run into the next, the flow preserves individual timing points as separate jobs and artifacts. That is far better for traceability and dissertation evidence.

### 3.5 Pages should be lightweight and honest

GitHub Pages is used for the **Run Explorer**, not as a dumping ground for the full backend implementation tree. The published site is intentionally lightweight, while large and detailed backend outputs remain in GitHub Actions artifacts.

---

## 4. Repository Structure

A typical structure is expected to look like this:

```text
.
├─ .github/
│  └─ workflows/
│     └─ aisc_flow.yml
├─ designs/
│  ├─ _shared/
│  │  └─ ll_policy/
│  │     ├─ constraints.sdc
│  │     ├─ power_fair.tcl
│  │     └─ power_activity.tcl
│  ├─ <variant_name>/
│  │  ├─ variant.yaml
│  │  ├─ src/
│  │  │  └─ ... RTL files ...
│  │  └─ tb/
│  │     └─ ... testbench files ...
├─ tools/
│  └─ scripts/
│     ├─ autoflow.py
│     ├─ compare_runs.py
│     ├─ gen_config.py
│     ├─ make_clock_matrix.py
│     ├─ read_start_clock.py
│     ├─ resolve_variant_meta.py
│     ├─ run_autoflow_compat.py
│     ├─ run_icarus_precheck.py
│     ├─ run_yosys_precheck.py
│     ├─ select_clock_bracket.py
│     └─ select_refine_matrix.py
├─ manifest.yaml
├─ README.md
├─ TECHNICAL DOCUMENTATION.md
└─ requirements.txt
```

Notes:

- `designs/<variant>/src/` is for **ASIC RTL only**
- `designs/<variant>/tb/` is for **simulation-only testbench sources**
- `_shared/ll_policy/` is the natural place for shared SDC or power-policy files
- `manifest.yaml` is the switchboard that selects the active experiment

---

## 5. Core Architecture and File Responsibilities

The repository can be separated it into three layers.

### 5.1 Configuration layer

Defines **what design is active** and **how it should be treated**.

- `manifest.yaml` chooses the active experiment
- `designs/<variant>/variant.yaml` defines design-specific behaviour

### 5.2 Execution layer

Decides **what CI does**.

- `.github/workflows/aisc_flow.yml` orchestrates the entire pipeline
- Precheck scripts handle simulation and structural synthesis sanity
- `autoflow.py` remains the backend ASIC attempt engine
- `run_autoflow_compat.py` acts as the safe workflow-facing wrapper

### 5.3 Presentation layer

Decides **how results are surfaced**.

- `compare_runs.py` downloads artifacts, classifies runs, builds summary tables, writes per-run pages, and generates the static Run Explorer site
- GitHub Pages publishes a lightweight snapshot for the current run and a `latest/` shortcut

---

## 6. Variant Contract

Each design variant is defined inside `designs/<variant_name>/variant.yaml`.

A representative modern example is:

```yaml
name: my_variant
pdk: sky130A

top_module: my_top

clock:
  port: clk
  mode: auto
  max_ns_cap: 200

sources:
  - src/**/*.v

precheck:
  icarus:
    enabled: true
    testbench_top: tb_my_top
    testbench_sources:
      - tb/**/*.v
      - tb/**/*.sv
    vcd_name: rtl_precheck.vcd
    stop_on_fail: true

  yosys:
    enabled: true
    stop_on_fail: true
    mode: structural

ll_policy:
  sdc: ../_shared/ll_policy/constraints.sdc
  power_fair_tcl: ../_shared/ll_policy/power_fair.tcl
  power_activity_tcl: ../_shared/ll_policy/power_activity.tcl
```

### 6.1 Required fields

#### `name`
A human-readable label for the variant.

#### `pdk`
The target PDK. For this flow, that is typically `sky130A`.

#### `top_module`
The exact top-level module to synthesise and harden.

#### `clock.port`
The clock input port name used by the RTL.

#### `clock.mode`
For this workflow, the intended setting is `auto`, meaning the clock period is explored by staged sweeps.

#### `clock.max_ns_cap`
The real upper search ceiling for timing exploration.

#### `sources`
A list of RTL globs relative to the variant directory. These must describe **ASIC synthesis RTL only**.

### 6.2 Precheck fields

#### `precheck.icarus`
Controls RTL simulation sanity checking.

- `enabled` enables or disables the simulation precheck.
- `testbench_top` names the simulation top.
- `testbench_sources` points to testbench files under `tb/`.
- `vcd_name` sets the expected VCD filename.
- `stop_on_fail` expresses whether this precheck is intended to gate the flow.

#### `precheck.yosys`
Controls structural synthesis sanity checking.

- `enabled` enables or disables the structural precheck.
- `stop_on_fail` expresses whether this precheck is intended to gate the flow.
- `mode` is currently intended as `structural`.

### 6.3 LibreLane / OpenLane policy fields

The `ll_policy` section is where variant-level backend policy belongs.

Typical examples include:

- `sdc`
- `power_fair_tcl`
- `power_activity_tcl`
- `synth_strategy`
- repair-related toggles when intentionally overridden

The guiding principle is simple: use variant-level policy when it genuinely belongs to the design, but do not overcomplicate the user contract.

### 6.4 Floorplanning fields

The `fp` section may be used for floorplanning settings such as:

```yaml
fp:
  core_util: 10
```

---

## 7. Manifest Contract

`manifest.yaml` selects the active design for CI.

A minimal example looks like this:

```yaml
project:
  title: "Variant ASIC Explorer"
  author: "Kieran"
  notes: "Variant-driven Sky130/OpenLane2 research workflow"

experiments:
  - variant: designs/my_variant
    enabled: true
```

### Important rules

- `variant` points to the **design directory**, not to individual files.
- Workflow resolves the first enabled experiment if no manual override is supplied,
- Workflow converts the path into a safe CI-friendly variant name when needed.

In practice, this means the manifest acts as the **front door** to the whole flow.

---

## 8. Source Separation Rules

### 8.1 ASIC RTL goes in `src/`

Everything in `sources:` should be real synthesis RTL that belongs in the ASIC backend flow.

### 8.2 Testbench code goes in `tb/`

Simulation-only files should live in `tb/` and should be referenced only by `precheck.icarus.testbench_sources`.

### 8.3 Why this matters

Mixing testbench code into synthesis inputs causes avoidable problems:

- Structural precheck becomes misleading
- Synthesis may see `$display`, delays, force/release, or simulation-only constructs
- Backend flow becomes less trustworthy

The clean separation between `src/` and `tb/` is therefore one of the most important architectural rules in the repository.

---

## 9. End-to-End CI Flow

The intended high-level flow is:

```text
plan
-> rtl-precheck
-> yosys-precheck
-> coarse-sweep
-> select-coarse-bracket
-> mid-refine-sweep
-> select-mid-bracket
-> refine-sweep-1
-> select-refine-1
-> refine-sweep-2
-> select-refine-2
-> refine-sweep-3
-> compare-runs
-> deploy-run-explorer
```

### 9.1 `plan`

This stage resolves the active variant, loads its metadata, builds the initial coarse matrix, and captures summary labels for the explorer.

The key outputs include:

- Safe variant name
- Actual variant path
- Top module
- Precheck enable flags
- VCD name
- Clock cap
- Coarse matrix JSON

### 9.2 `rtl-precheck`

This stage runs `run_icarus_precheck.py`.

Its role is to answer a practical question:

> Can this design, together with its testbench, compile and run cleanly enough to produce the expected VCD?

It uploads a dedicated precheck artifact and emits gate signals so later backend jobs know whether it is safe to continue.

### 9.3 `yosys-precheck`

This stage runs `run_yosys_precheck.py`.

Its role is to check whether the ASIC RTL is structurally sane from the selected top module and whether a clean reachable module closure can be built without duplicate reachable definitions.

Like RTL precheck, it produces a dedicated artifact and gate outputs.

### 9.4 `coarse-sweep`

The first backend sweep spans the whole timing search space explicitly as a matrix.

Current policy:

- minimum floor: `0 ns`
- maximum: `clock.max_ns_cap`
- default step: `20 ns`

Every point is kept visible as an individual run.

### 9.5 `select-coarse-bracket`

This stage analyses the coarse results and picks a bracket using:

- `upper_pass`: the lowest passing clock period
- `lower_fail`: the highest failing point below that pass

### 9.6 `mid-refine-sweep`

This stage performs a downward-only matrix sweep across the coarse bracket using a default step of `5 ns`.

### 9.7 `select-mid-bracket`

This stage narrows the bracket further in preparation for the finer `1 ns` exploration.

### 9.8 `refine-sweep-1`

This stage sweeps the narrowed region at `1.0 ns` granularity.

### 9.9 `select-refine-1`

This stage selects the next matrix for the `0.5 ns` refinement stage.

### 9.10 `refine-sweep-2`

This stage sweeps the narrowed region at `0.5 ns` granularity.

### 9.11 `select-refine-2`

This stage selects the final matrix for the `0.125 ns` stage.

### 9.12 `refine-sweep-3`

This stage performs the finest intended sweep at `0.125 ns` resolution.

### 9.13 `compare-runs`

This stage downloads all artifacts, classifies the runs using extracted final timing and signoff evidence, builds summary outputs, chooses the best run according to the strict explorer rule, and generates the static Run Explorer site.

In particular, the best run is selected only from `SIGNOFF_PASS` results, while completed but failing runs remain visible for debugging and comparison.

### 9.14 `deploy-run-explorer`

This stage publishes the generated site to `gh-pages`, keeps a per-run snapshot under `runs/<run_id>/`, and updates `latest/` so the newest explorer is easy to access.

---

## 10. Gating Behaviour

The backend sweep jobs are intentionally gated.

The workflow only proceeds into the ASIC attempt stages when the prechecks are considered safe enough to continue. In practice, the precheck jobs export gate outputs such as:

- `gate_ok = true` when the precheck passed or when the precheck status is `SKIP`

That behaviour is useful because it distinguishes between:

- Genuine design that is ready for backend exploration,
- Deliberately skipped precheck,
- Variant that is not even ready for backend execution.

---

## 11. Script Responsibilities

The repository works best when each script keeps a clear, limited role.

### `resolve_variant_meta.py`
Resolves the active variant from either:

- Safe variant name
- Direct variant path
- First enabled manifest entry

It expands RTL and testbench globs, builds structured metadata, and can export values for GitHub Actions.

### `run_icarus_precheck.py`
Performs the RTL simulation precheck by:

- Compiling with `iverilog`
- Running the simulation with `vvp`
- Checking for the expected VCD
- Writing logs plus `status.json`

This is where the repo enforces the separation between RTL sources and testbench sources.

### `run_yosys_precheck.py`
Performs the structural synthesis precheck by:

- Building the reachable module closure from the selected top
- Detecting duplicate reachable module definitions
- Running Yosys on the closure
- Emitting logs, stats, and structured status

### `make_clock_matrix.py`
Generates the explicit matrix of clock values for a sweep stage.

### `select_clock_bracket.py`
Chooses a pass/fail bracket from completed runs and emits summary artifacts.

### `select_refine_matrix.py`
Generates the next refine matrix for the smaller-step stages.

### `run_autoflow_compat.py`
Acts as the workflow-facing wrapper that passes only the supported arguments into the backend attempt flow.

### `autoflow.py`
Remains the actual ASIC attempt engine. It should stay focused on backend execution, not on precheck duties.

### `compare_runs.py`
Builds the summary CSV/Markdown outputs, classifies results, chooses the best run, builds the static site, writes per-run pages, and prepares the bundle used by Pages.

That separation of responsibilities is one of the reasons the repo remains maintainable.

---

## 12. RTL Precheck Details

The RTL precheck is based on Icarus Verilog.

### Purpose

Its job is not to “prove” the design correct. Its job is to confirm that the design and its intended testbench are at least healthy enough to:

- Compile
- Simulate
- Generate the expected VCD

### Expected outputs

A typical precheck artifact includes:

- `compile.log`
- `run.log`
- `status.json`
- `precheck_meta.json`
- Generated VCD (if successful)
- Compiled simulation binary (where relevant)

### Typical failure reasons

- Missing `testbench_top`
- Missing testbench sources
- Compile failure
- Simulation runtime failure
- Missing VCD despite successful compile/run

---

## 13. Yosys Structural Precheck Details

The Yosys precheck is deliberately **top-closure-aware**.

That matters because simply throwing all RTL files at Yosys can create misleading behaviour when the design tree is large or when unrelated modules happen to coexist in the repository.

What it does: 

- Finds the selected top module
- Extracts reachable module dependencies
- Vuilds the reachable source closure
- Detects duplicate reachable module definitions
- Runs Yosys on that closure
- Records useful synthesis statistics

---

## 14. Timing Search Strategy

The timing search strategy is one of the central ideas of the repository.

### 14.1 Why matrix sweeps are used

A matrix sweep has two big advantages:

1. Each tested timing point is visible as its own job and artifact,
2. Refinement logic remains explainable in reports and writeups.

### 14.2 Coarse to fine structure

The intended schedule is:

- coarse sweep: `20 ns`
- mid refine: `5 ns`
- refine 1: `1.0 ns`
- refine 2: `0.5 ns`
- refine 3: `0.125 ns`

### 14.3 Why a cap is necessary

`clock.max_ns_cap` is not cosmetic. It prevents the search from drifting into unrealistic or wasteful timing regions.

A good cap should be:

- High enough to find a passing region,
- Not so high that CI spends time exploring obviously uninteresting points.

### 14.4 Why refinement is bracket-based

Refinement is driven by observed pass/fail evidence. That is more honest than simply tightening around a guess, and it produces a paper trail that is useful in both debugging and dissertation writing.

---

## 15. Run Classification and Status Model

TThe explorer uses status classes that are intended to be academically honest and consistent with extracted final metrics.

### `SIGNOFF_PASS`

The run completed and the required exported timing, electrical, and physical signoff evidence supports acceptance.

### `FLOW_COMPLETED_TIMING_FAIL`

The backend completed, but worst-case setup and/or hold timing still failed.

### `FLOW_COMPLETED_ELECTRICAL_FAIL`

The backend completed, but electrical integrity checks such as max slew or max capacitance still failed.

### `FLOW_COMPLETED_SIGNOFF_FAIL`

The backend completed, but physical/signoff checks such as DRC, LVS, or antenna still failed.

### `FLOW_COMPLETED_TIMING_AND_SIGNOFF_FAIL`

The backend completed, but both timing and signoff evidence still failed.

### `METRICS_MISSING`

The backend completed, but required final metrics were missing or incomplete, so safe signoff classification could not be determined.

### `FLOW_FAIL`

Reserved for runtime, tooling, configuration, or evidence-integrity failures such as:

- missing usable run directory,
- missing final metrics files,
- incomplete artifact state,
- backend failure before valid evidence is produced.

This model matters because a completed-but-failing implementation result should not be confused with a runtime failure, and missing evidence should not be silently treated as clean.

---

## 16. Best-Run Selection Logic

The selected best run is not just the lowest requested clock period.

The intended rule is:

1. Only runs classified as `SIGNOFF_PASS` are eligible to be selected as the true best run.
2. Among those runs, the lower requested clock period is preferred.
3. Setup and hold WNS/TNS may be used only as tie-breakers among otherwise valid signoff passes.

If no `SIGNOFF_PASS` run exists, the flow should report that no signoff-clean timing point was found.

A completed but failing run may still be surfaced for inspection, but it must not be presented as the best passing timing point.
---

## 17. Artifact Philosophy

Artifacts are intentionally rich. The point is to preserve enough evidence to support debugging, comparison, and writeup.

### 17.1 Attempt artifacts

Typical backend artifacts may include:

- `metrics.csv`
- `metrics.md`
- `metrics_raw.json`
- `run_meta.json`
- `attempt_started.txt`
- `attempt_manifest.json`
- `renders/`
- `final/gds/`
- backend run trees where available

### 17.2 Precheck artifacts

Precheck artifacts include logs, status JSON, metadata, and—when successful—the RTL VCD.

### 17.3 Bracket summary artifacts

Bracket selection stages may emit:

- `bracket_summary.md`
- `bracket_summary.json`

These help explain why a new refine matrix was chosen.

### 17.4 Failure diagnostics

When a run lands in `FLOW_FAIL`, the flow is intended to preserve a useful diagnostic summary rather than simply collapsing into a vague failure state.

That is especially valuable during development, because it helps distinguish:

- Script/configuration failure
- Backend tool failure
- Missing outputs
- Design or timing issues

---

## 18. GitHub Pages and Site Publishing Policy

GitHub Pages is used for the **Run Explorer**.

### What gets published

The published site is intended to include:

- Homepage overview
- Run comparison table
- Per-run detail pages
- Lightweight copies of selected outputs
- Run snapshots under `runs/<run_id>/`

### What does not get published

Large backend trees and bulky implementation outputs should stay in GitHub Actions artifacts rather than being mirrored in full to Pages.

This keeps the published site faster, lighter, and easier to maintain.

---

## 19. Run Explorer Design

The explorer is meant to be a practical engineering dashboard rather than a decorative landing page.

### Homepage responsibilities

The homepage is intended to present:

- Run overview
- Summary settings
- All-runs comparison table
- Honest status classification
- Best-run selection based only on true signoff passes

The comparison table is where timing points are compared clearly across status, timing, electrical integrity, physical signoff, power, and artifact availability.

### Per-run page responsibilities

Each run page is intended to show:

- Clean run metadata
- Grouped metrics by category
- Useful buttons and output links
- Failure diagnostic detail when a run is not clean
- Additional integrity evidence such as setup/hold violation counts, max slew, max capacitance, route DRC, route antenna, and power / IR validity where available

### External tools

The explorer may link outward to:

- External waveform viewer for VCD inspection (Surfer)
- External GDS viewer homepage (TinyTapeout GDS Viewer)

---

## 20. Metrics and Units

The Run Explorer should use explicit units consistently.

### Timing

- **WNS** = `ns` = nanoseconds
- **TNS** = `ns` = nanoseconds
- requested clock period = `ns`
- reported clock period = `ns`

### Physical

- **Core Area** = `μm²` = square micrometres
- die area = typically `μm²`
- utilisation = percentage or ratio depending on source metric

### Power

- **Total Power** = `W` = watts

### Signoff and integrity

- **IR Drop** = `V` = volts
- DRC/LVS/Antenna counts = count-based integrity metrics

Being explicit about units is not a minor formatting issue. It improves clarity for engineering review and for dissertation screenshots.

---

## 21. How to Add a New Design

### Step 1: Create a new variant folder

Example:

```text
designs/my_alu/
├─ variant.yaml
├─ src/
│  ├─ top.v
│  ├─ datapath.v
│  └─ control.v
└─ tb/
   └─ tb_my_alu.v
```

### Step 2: Place synthesis RTL under `src/`

Only real ASIC RTL should go here.

### Step 3: Place simulation files under `tb/`

Keep testbench and verification-only code here.

### Step 4: Fill in `variant.yaml`

At minimum, make sure these are correct:

- `top_module`
- `clock.port`
- `clock.max_ns_cap`
- `sources`
- `precheck.icarus.testbench_top`
- `precheck.icarus.testbench_sources`

### Step 5: Register the variant in `manifest.yaml`

Enable the new experiment.

### Step 6: Commit and push

The normal usage model is to push to `main` and let the workflow run automatically.

---

## 22. How to Run the Flow

### Automatic run on push

This is the normal mode:

1. Edit the design files
2. Update `variant.yaml`
3. Select the variant in `manifest.yaml`
4. Push to `main`

### Manual run from GitHub Actions

Manual dispatch is useful when you want to rerun the flow without creating a new commit, or when you want to supply optional summary labels or image overrides.

In the current workflow, manual inputs are intentionally light and include items such as:

- Safe variant override
- OpenLane image override
- Summary labels for explorer presentation

This keeps the workflow focused and reduces accidental misuse.

---

## 23. How to Interpret Results

### If backend fails

That usually means the repository selected the design correctly, but the ASIC flow still encountered a tooling, configuration, or backend execution problem before valid final evidence was produced.

### If timing fails

That is a real implementation result, not a repo failure. It means worst-case setup and/or hold timing did not close at that timing point.

### If electrical checks fail

That usually means checks such as max slew or max capacitance still violated limits. This often points to load, buffering, fanout, or routing-quality issues rather than clock period alone.

### If signoff checks fail

That means physical closure is still incomplete. Typical examples include DRC, LVS, or antenna violations.

### If metrics are missing

That means the run may have completed, but final evidence was incomplete. It should be treated as incomplete, not silently counted as a pass.

### If no signoff-clean point exists

The correct engineering conclusion is that no true passing timing point was found in the explored region, even if some runs completed and produced useful partial evidence.

---

## 24. Final Summary

`LibreLane Sky130PDK ASIC Toolchain` is a structured, variant-driven GitHub ASIC workflow built for real engineering use, not just demonstration. It combines:

- Clear design ownership through `manifest.yaml` and `variant.yaml`
- Disciplined RTL/TB separation
- Icarus and Yosys prechecks before backend execution
- Staged matrix-based timing exploration
- Artifact preservation for debugging and evidence
- Static Run Explorer published through GitHub Pages

The repository is at its best when used exactly as intended: as a reproducible, dissertation-friendly flow where each timing point remains visible, each status is classified honestly, and each design variant is treated as a first-class research experiment.
