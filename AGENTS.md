# AGENTS.md

These instructions apply to all AI-assisted work in this repository.

## Shared DevKit guidance

`jkuhnen/opencpn-plugin-devkit`, checked out at `.devkit`, is the shared development baseline for this plugin. Before changes involving architecture, OpenCPN API behavior, Windows builds, packaging, CI, Git workflow, maritime HMI, or design-system work, read `.devkit/AGENTS.md` and the relevant documents under `.devkit/docs/`.

Chart Inspector's local `AGENTS.md`, `README.md`, `docs/MARITIME_HMI.md`, source code, and issue-specific requirements remain authoritative for Chart Inspector-specific behavior. When a local documented rule intentionally differs from a DevKit convention, the local rule wins in this repository and the difference must be called out in the pull request. Verified upstream OpenCPN and API behavior remains authoritative over both local and DevKit conventions.

Use this precedence order:

```text
verified upstream OpenCPN/API behavior
        ↓
issue/task-specific requirements
        ↓
Chart Inspector local documented rules
        ↓
shared DevKit conventions
        ↓
agent assumptions
```

Do not silently update the `.devkit` submodule pointer during unrelated feature work. If `.devkit` is uninitialized locally, run `git submodule update --init --recursive` before relying on its contents; do not fabricate missing guidance.

## Project context

- Chart Inspector is an OpenCPN plugin developed primarily on Windows 11 with MSVC, CMake, wxWidgets, and OpenGL.
- Keep the project at C++11 unless an intentional project-wide change explicitly requires another language standard.
- The plugin targets OpenCPN plugin API 1.18 and uses `opencpn-libs/api-18` together with the OpenCPN plugin conventions already present here.
- The current preview depends on an experimental, read-only vector-object query extension that is not yet part of upstream OpenCPN.
- Keep the plugin provider-independent where practical. It must not parse proprietary chart files itself.
- OpenCPN chart portrayal and official chart symbology are authoritative.
- Read and follow `README.md` and `docs/MARITIME_HMI.md`. Standards referenced by the project are design guidance; do not claim ECDIS, type approval, or regulatory compliance.

## Required workflow

1. Before changing code, read `README.md`, the relevant documentation, and the current implementation involved in the task.
2. Check `git status` and the current branch before editing.
3. Never perform feature work directly on `main`; create or use a dedicated feature or fix branch.
4. Keep changes scoped to the requested issue. Do not opportunistically refactor unrelated code.
5. Preserve API compatibility unless the task explicitly requires an API change.
6. Prefer small, generic OpenCPN API improvements over provider-specific workarounds.
7. Do not modify the `opencpn-libs` submodule or its pinned reference casually. Such a change requires an explicit task and an explanation.
8. Do not commit generated build output, packages, IDE state, or other ignored artifacts.
9. After relevant C++ or CMake changes, build with the repository's actual local Windows/MSVC workflow. If the exact command is not documented, inspect the existing build tree and configuration instead of inventing a new toolchain.
10. Treat a successful compile as necessary but not sufficient. Runtime behavior inside OpenCPN still requires maintainer testing where applicable.
11. Review `git diff` before committing. Summarize changed files, the build result, remaining warnings or risks, and any manual testing still required.
12. Use clear commit messages tied to the issue.
13. Push the feature branch and open a pull request against `main`. Do not merge the pull request unless the maintainer explicitly instructs you to do so.

## Code and design rules

- Keep UI concerns separate from chart-query and data logic where practical.
- Keep chart querying read-only. Hover and object queries must remain bounded and fast.
- Avoid unnecessary allocations or unbounded work in pointer-move and hover paths.
- Preserve OpenCPN DAY, DUSK, and NIGHT behavior and check new UI in all three schemes.
- Do not use red, amber/yellow, or green as generic interaction colours where they could conflict with maritime HMI semantics. Literal encoded navigation colours remain literal.
- Keep hover and persistent selection visually distinct from alerts and safety states.
- Preserve navigation-first information hierarchy and keep source or technical details subordinate.
- Prefer existing project patterns and APIs over new frameworks or dependencies. New dependencies require explicit justification.
- Write comments for non-obvious intent, particularly API lifetime, ownership, geometry, and navigation or HMI reasoning. Do not add comments that merely restate the code.

## Safety and repository hygiene

- Never force-push, rewrite shared history, delete branches, reset away user work, or perform destructive Git operations unless explicitly requested.
- Never upload secrets, credentials, signing material, private chart data, or machine-specific sensitive information.
- Before handing work off, verify that no unrelated files changed and clearly identify any runtime test that the maintainer must perform in OpenCPN.
