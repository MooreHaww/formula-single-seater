# Community SolidWorks MCP servers: code safety and SolidWorks 2026 Student fit

Read-only review, 2026-11-16. Nothing was installed or cloned into the project; the sources were read from GitHub at the state of that day (the `Desktop\tools` folder holds only `matlab-agentic-toolkit`, none of these servers). The question: could one of them replace or speed up the hand-run `.bas` macros in `cad/macros/` for Ring 2, and would it be safe to put next to this repo on the owner's PC with SolidWorks 2026 Student Edition.

## Short answer

Do not install any of them yet. Every one of the five runs arbitrary code in or beside SolidWorks (Python `exec`, reflective COM calls, or inline VBA), none has been run against SolidWorks 2026 by anyone, and two of the three "run a macro" servers hard-code an older release. The only server with a clean security story (haunchen) makes drawings, not parts. For Ring 2 keep the plan as it is: the four `.bas` macros, the `cad/step/*.step` bodies from `cad/generate/build_parts.py`, and the parameter file linked through Equations. Revisit after the macros are verified in 2026; the candidate then is lildebil0 (dimension, rebuild, STEP export, mass properties over COM), with its `sw_run_vba` and `sw_call` tools removed from the tool list first.

## What was reviewed

| Server | Language, transport | Stars | Last push | Targets | Tool count |
|---|---|---|---|---|---|
| [alisamsam/solidworks-mcp](https://github.com/alisamsam/solidworks-mcp) | Python, pywin32, stdio | 206 | 2026-03-23 | SolidWorks 2023 to 2025 | 22 (parts, sketches, features) |
| [haunchen/solidworks-mcp](https://github.com/haunchen/solidworks-mcp) | Python FastMCP, Streamable HTTP over LAN | 12 | 2026-06-12 | SolidWorks 2021 only tested | 21 (drawings, views, dimensions, BOM, PDF) |
| [lildebil0/solidworks-mcp](https://github.com/lildebil0/solidworks-mcp) | Python FastMCP, stdio | 0 | 2026-06-14 | any (never run live) | 57 (6 build123d + 51 `sw_*`) |
| [vespo92/SolidworksMCP-TS](https://github.com/vespo92/SolidworksMCP-TS) | TypeScript, winax native COM, stdio | 255 | 2026-09-20 | 2021 to 2025 claimed, "alpha, mostly unvalidated" | many (modelling, drawing, export, VBA generation, macros) |
| [ladla90077-web/solidworks-mcp](https://github.com/ladla90077-web/solidworks-mcp) (the "run, test and auto-fix VBA" server listed on Glama) | Python, pywin32, stdio | 5 | 2026-07-02 | SolidWorks 2022 hard-coded | about 60 (run_macro, run_vba, run_and_verify, feature generators, docs lookup) |

All five are MIT licensed. espocorp/mcp-server-solidworks, also listed by search engines, no longer exists on GitHub.

## Per-server findings

### alisamsam/solidworks-mcp

Safety:

- `execute_python` runs model-written Python with `exec()` inside the server process, with `os`, `win32com` and `pythoncom` in the namespace (`solidworks_mcp/server.py` line 582). That is remote code execution by whatever text reaches the model, with no sandbox, and it runs as the logged-in user.
- A `.env` file is committed with what looks like a live OpenRouter key (`OPENAI_API_KEY="sk-or-..."`), a base URL and a model name. The package never reads it (no `dotenv` import anywhere in the Python), so it is a leftover from a chat-loop prototype, but a committed credential is a hygiene signal.
- Committed clutter: `scripts/history/*.vbs` (23 generated VBScript files), two `backup_2026...` copies of the server, an 80 kB roadmap. The VBScript is not executed by the current code.
- `requirements.txt` asks for `asyncio-compat>=0.1.0`, which is not a package this project needs and whose provenance should be checked before any `pip install -r`.

2026 Student fit: the installation finder reads the registry and takes the newest version, and the connection tries `GetObject`, `Dispatch` and `GetActiveObject` on the version-independent ProgID `SldWorks.Application`, so it would attach to a running 2026. The feature calls (`FeatureExtrusion3`, `FeatureCut4`, `SketchManager.CreateCircleByRadius`) have been stable since 2016 and should work. Nobody has tried it on 2026 and the README stops at 2025.

Use for this project: it builds blocks and cylinders from text; the car is lofts, revolves and equation-driven dimensions. Low value even if safe.

### haunchen/solidworks-mcp

Safety:

- No code-execution tool at all. Tools open, read and export documents and build drawing views; the only file writes are PDF and JPEG exports and `shutil.copy2` into a configured share folder.
- Binds `0.0.0.0:8080` by default with no authentication; the README says so plainly ("anyone who can reach the port can drive your SolidWorks instance and read/write files"). On a home network bind it to `127.0.0.1` instead.
- Cleanest code of the five: single STA COM worker thread with a 30 s timeout, early-binding with late-binding fallback, pytest suite, CI, design notes per feature.

2026 Student fit: version-agnostic COM (`EnsureDispatch` then `Dispatch`), but the author tested 2021 only and the drawing API (`DrawingDoc.CreateDrawViewFromModelView3`, balloons, BOM tables) is where SolidWorks changes signatures between releases, so expect some tool failures.

Use for this project: none until Ring 7 (drawings for the release). Worth remembering for that.

### lildebil0/solidworks-mcp

Safety:

- The build123d half runs model-written Python behind an AST whitelist sandbox (`sandbox.py`: allowed import roots, forbidden names, dunder-attribute block, trimmed builtins). The file's own docstring says it is "NOT a security boundary by itself", which is the right description.
- The SolidWorks half has `sw_run_vba` (writes a temp `.swb` and runs it) and `sw_call` (reflective access to any COM method on any object handle). The README states this is "arbitrary local code execution ... the same trust level as a user running a macro by hand". Honest, and still the whole COM surface.
- Status is stated with unusual honesty: the 51 `sw_*` tools have never been run on a live SolidWorks; only mock-COM tests (47 passing). The Tier-1 wrappers hard-code method signatures such as `FeatureExtrusion3` and say to fall back to `sw_call` if they fail.
- Pins `build123d>=0.10,<0.11`; this repo's generator was run on 0.13, so the two would need separate environments.

2026 Student fit: unknown, same as everyone (version-independent ProgID, late binding). The base tools (`sw_open`, `sw_set_dimension`, `sw_rebuild`, `sw_export_step`, `sw_get_dimension`, `sw_list_configurations`) are exactly the ones this project's parameter-file workflow would use, and they call only long-stable API members.

Use for this project: the best fit of the five, once it has been exercised on a real SolidWorks. If it is ever tried: run from a dedicated venv, stdio only, and strip `sw_run_vba` and `sw_call` from `sw_tools.py` / `sw_advanced_tools.py` before registering it.

### vespo92/SolidworksMCP-TS

Safety:

- `macro_set_security` lowers SolidWorks' macro security level through `SetUserPreferenceIntegerValue(77, ...)`, and `macro_get_security_info`, a tool whose name says "get", also calls `SetUserPreferenceToggle(197, true)` to switch VBA macros on as a side effect (`src/tools/macro-security.ts`). A server that changes the host's security settings on a read call is disqualifying on its own.
- Routes any API call with 13 or more parameters through generated VBA that SolidWorks executes, so the VBA path is the normal path, not an exception.
- Dependencies for a CAD bridge: `chromadb`, `mssql`, `pg` (two database clients and a vector store), plus `winax` compiled natively on the machine with node-gyp (needs Visual Studio build tools). Large install, large attack surface.
- `docs/VERSION_COMPATIBILITY.md` shows "Full support, integration tested" ticks for 2021 to 2025; the README on the same commit says "most tools have not been validated against a live SolidWorks instance" and marks export, drawing, analysis and macros "Untested". Treat the table as aspirational.

2026 Student fit: not claimed, not tested, and the native module build is the first thing that would break.

Use for this project: no.

### ladla90077-web/solidworks-mcp (run-and-verify)

What it does well: `run_and_verify` runs inline VBA from a temp `.swb` with `RunMacro2`, rebuilds, scans the feature tree for errors and returns one structured verdict, so the model can fix a macro and rerun it. Its `vba_lint.py` encodes two real `.swb` pitfalls that apply to this repo's own macros: in an on-the-fly `.swb` an API `VARIANT_BOOL` arrives as `+1`, so `If Not x` is true for a true result (write `If x = False`), and `CreateCornerRectangle` returns a Variant array, not an object. Both checks are worth running by eye over `cad/macros/*.bas` before the macro test.

Safety:

- `run_vba` and `run_and_verify` are arbitrary VBA execution by design.
- The dialog watchdog (`macro_runner.py`) runs on a second thread and posts `WM_CLOSE` to every visible window of class `#32770` (the standard dialog class) owned by the SolidWorks process after a short grace period. That will also close "Save changes?", "Overwrite?", licence and rebuild-error dialogs without anyone reading them. It can be switched off per call (`watchdog=False`), but it is on by default.
- `local_docs.py` spawns PowerShell to run `hh.exe -decompile` on the SolidWorks CHM help files; the docs pipeline needs Playwright plus a Chromium download to render `help.solidworks.com/2022` pages.
- The package bundles about 150 MB of a third-party "Cosmon" documentation payload (JSON files of 28 to 35 MB each that look like scraped SolidWorks API help) plus C# templates and a persistent-service source tree; licensing of that payload is not stated.
- `register-mcp.md` registers the server at user scope (every project) and says the server will launch SolidWorks itself on the first tool call.

2026 Student fit: `sw_connection.py` hard-codes `SldWorks.Application.30` (2022) and falls back to the version-independent ProgID, mapping year = 1992 + major, so it would attach to 2026 (major 34) and report the right year. Everything above that (the docs lookup, the lint rules, the feature generators) was written against the 2022 API and the author's README is 2022 only.

Use for this project: not as an installed server. The lint rules and the "silent log instead of MsgBox" pattern are worth copying into `cad/macros/` by hand.

## SolidWorks 2026 Student Edition notes that apply to all five

- All five connect through the version-independent COM ProgID, so attaching to 2026 should work. What breaks between releases is method signatures, and the basic ones used by the part-building servers have not changed in years. Nobody has tested any of them on 2026; the newest release any author names is 2025.
- The Student Edition licence is activated online and SolidWorks shows licence and "what's new" dialogs at start-up. Servers that launch SolidWorks themselves (alisamsam, ladla, lildebil0 with `launch_if_needed`) will hit those dialogs; ladla's watchdog would close them blind.
- Whether the Student Edition exposes the full API is to be **verified** on first use (Tools > Macro > New should open the VBA editor; the macro test in `docs/ring0_practice/08_macro_test_30min.md` is that check). The owner's installation has Simulation and Motion; none of the servers drives either.
- Every server that executes VBA or Python does so with the owner's Windows account rights. The MCP client's prompt-injection surface (any text the model reads) becomes a path to running code on the PC. That is the reason to prefer tools that only set dimensions and export files.

## Recommendation

1. Ring 0 to 2: no MCP server. Run the four `.bas` macros by hand per the macro test, import the generated STEP bodies, link `car_params.txt` through Equations.
2. Before the macro test, check `cad/macros/*.bas` for the two `.swb` pitfalls from ladla's lint (bitwise `If Not` on API booleans, `Set` on `CreateCornerRectangle`). The macros are `.bas` modules run from the VBA editor, where booleans are normal, but the check costs five minutes.
3. If an MCP bridge is wanted later for "change a parameter, rebuild, export STEP, read mass": try lildebil0 in its own venv with `sw_run_vba` and `sw_call` removed, after it has been shown to work on one part by hand. Log the outcome in `docs/log.md`.
4. Ring 7 drawings: look at haunchen again, bound to `127.0.0.1`.
5. Do not use alisamsam (`execute_python`, committed key) or vespo92 (security-setting tools, native build, database dependencies) on this machine.

Sources read: the five repositories above at their 2026-11-16 state (README, dependency files, server entry points, COM connection code, the code-execution and macro tools, version notes), and the Glama listing that identified the run-and-verify server ([glama.ai/mcp/servers/zy6wfs6d5w](https://glama.ai/mcp/servers/zy6wfs6d5w)).
