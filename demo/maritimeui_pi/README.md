# Maritime UI Demo

A deliberately small OpenCPN 1.18 plugin for evaluating the maritime HMI design language developed for Chart Inspector and a possible future OpenCPN interaction layer.

This is a visual/interaction demonstrator, not a navigation function and not an ECDIS.

## What it shows

- OpenCPN-controlled DAY / DUSK / NIGHT appearance
- navigation-first information hierarchy
- restrained blue/cyan focus colour for ordinary interaction
- red reserved for invalid/alarm state
- amber/yellow reserved for warning or reduced integrity
- green used only for an explicit valid/normal state example
- source and technical data visually subordinate to operational information
- compact bridge/instrument-like layout without decorative desktop UI styling

The window contains sample data on purpose, so the design can be judged without requiring a particular ENC object under the cursor.

## Build on Windows

From the `chartinspector_pi` repository root, ensure the `opencpn-libs` submodule is available. Then:

```bat
cd demo\maritimeui_pi
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A Win32
cmake --build . --config Release
cpack -C Release
```

The generated package is independent from Chart Inspector and has its own plugin name: `Maritime UI Demo`.

## Design reference

The demonstrator is informed by the presentation and usability principles in IMO MSC.191(79), IMO MSC.1/Circ.1609, IEC 62288 and IHO S-52. This statement describes design references only; it is not a claim of compliance, certification or type approval.
