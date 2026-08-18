# Chart Inspector

Chart Inspector is an OpenCPN plugin for direct and intuitive interaction with vector chart objects.

The project aims to make vector features easier to discover and inspect by adding hover highlighting, direct object selection, and quick access to feature metadata and attributes.

> **Project status:** Early development. The repository currently contains the initial plugin scaffold and architecture notes.

## Goals

- Highlight selectable vector chart objects when the pointer moves over them.
- Select the intended chart object directly with a click whenever possible.
- Show concise feature information without forcing the user through the existing multi-object query workflow.
- Provide access to the underlying object attributes and metadata.
- Work with standard ENC/S-57 charts and plugin-provided vector charts through OpenCPN's chart abstraction where possible.
- Stay independent of individual chart providers such as o-charts.

## Intended interaction

1. Move the pointer over a vector chart feature.
2. Chart Inspector identifies the most relevant selectable object near the pointer.
3. The object is visually highlighted without modifying the chart symbology itself.
4. A click selects the object and opens a compact information view.
5. If several relevant objects genuinely overlap, Chart Inspector can offer a small selection list.

Initial development will focus on aids to navigation such as buoys, beacons, and lights before expanding to other useful vector feature classes.

## Architecture

Chart Inspector is intended to remain a normal OpenCPN plugin. The preferred design is:

```text
OpenCPN chart canvas
        |
        | mouse position / events
        v
Chart Inspector
        |
        | read-only vector object query
        v
OpenCPN chart abstraction
        |
        +-- native S-57 / ENC charts
        +-- plugin-provided vector charts
```

OpenCPN already has internal mechanisms for querying vector objects near a geographic position. One of the first technical tasks is to determine whether the required hit-testing can be implemented entirely through the public plugin API. If not, the project may propose a small, generic, read-only extension to the OpenCPN plugin API rather than adding provider-specific code.

## Repository name

The visible plugin name is **Chart Inspector**. The repository uses the OpenCPN convention `chartinspector_pi`, where `_pi` means *plug-in*.

## Development principles

- Provider-independent wherever possible.
- Read-only access to chart features.
- Preserve official chart symbology; highlights are drawn as a separate overlay.
- Keep the core interaction fast enough for pointer-hover use.
- Prefer small, generic OpenCPN API improvements over workarounds tied to a specific chart provider.
- Source code, documentation, issues, and UI text are written in English.

## Roadmap

- [ ] Minimal OpenCPN plugin builds and loads.
- [ ] Receive chart-canvas mouse and cursor events.
- [ ] Draw a simple hover overlay.
- [ ] Prototype vector-object hit testing.
- [ ] Inspect object classes and attributes returned by ENC and plugin charts.
- [ ] Implement object prioritization for overlapping features.
- [ ] Add direct selection and compact feature information.
- [ ] Evaluate whether an OpenCPN core/API extension is required.

## Building

Build instructions will be added once the initial OpenCPN plugin build setup is finalized. The current source tree is intentionally minimal while the required plugin API surface is being validated.

## Contributing

Chart Inspector is intended as a community-oriented OpenCPN extension. Ideas, test results with different vector chart sources, API findings, bug reports, and code contributions are welcome as the project develops.

## License

GPL-2.0-or-later. See `LICENSE`.
