# Upstream plan: Vector Object Query API

This document separates the upstream work from the historical Chart Inspector prototype patches.

## Repository split

### OpenCPN/OpenCPN

Proposed generic core/API change only:

- versioned POD query/result structures,
- `QueryVectorChartObjectsV1`,
- native S-57 adapter,
- `PlugInChartBaseGLPlus3`,
- `PlugInChartBaseExtendedPlus3`,
- provider dispatch,
- validation/safety limits,
- tests and API documentation.

No Chart Inspector UI code belongs in this change.

### bdbcat/o-charts_pi

Separate provider implementation:

- derive the appropriate eSENC chart class from `PlugInChartBaseExtendedPlus3`,
- implement `QueryVectorObjectsV1`,
- reuse existing internal object/candidate machinery,
- copy feature class, object name, geometry and attributes into callback-lifetime POD buffers,
- never expose internal S-57/render pointers.

### kuhnentrion/chartinspector_pi

Consumer/reference client:

- use `QueryVectorChartObjectsV1`,
- copy callback data immediately,
- perform screen-space Point/Line/Area hit testing,
- retain S-57 catalogue decoding and UI presentation,
- remove private V1-V5 hit-test exports after public API validation.

## Upstream acceptance criteria

The OpenCPN patch is ready to propose when all of the following are true:

1. Current OpenCPN master builds unchanged when no Plus3 provider is installed.
2. Existing Plus2 chart providers continue to load without recompilation.
3. Native unencrypted S-57 returns Point, Line and Area objects.
4. A Plus3 test provider returns the same three geometry categories.
5. A malformed provider object cannot crash the consumer path.
6. Returning zero candidates is distinguishable from unsupported/error (`true` with zero callbacks versus `false`).
7. No provider-owned pointer survives a callback.
8. No STL/wx ownership crosses the provider ABI.
9. The API contains no Chart Inspector UI policy.
10. The public documentation specifies lifetime, geometry and error semantics.

## Development rule

Do not extend the historical `OCPNChartInspectorHitTestV*` path further. It remains only as a temporary local comparison/fallback until the generic API is proven.

All new core work should target the upstream-shaped `QueryVectorChartObjectsV1` design.

## First implementation slice

The first upstream-shaped OpenCPN patch should deliberately be small:

1. public POD declarations,
2. Plus3 class declarations/default implementations,
3. exported query entry point,
4. native S-57 path,
5. plugin-wrapper dispatch,
6. no feature filtering in the provider ABI for v1,
7. no UI or rendering changes.

After this builds and native S-57 is validated, add o-charts provider support in its own branch/repository.

## Test matrix

| Source | Point | Line | Area | Attributes | Multipart |
|---|---|---|---|---|---|
| Native S-57 | required | required | required | required | required |
| o-charts/eSENC | required | required | required | required | required |
| Unsupported plugin chart | false | false | false | n/a | n/a |

For each supported source, compare candidate identity and raw attributes with OpenCPN's existing Object Query at the same geographic position.

## PR strategy

Before opening a full OpenCPN PR, prepare a concise design discussion/issue or draft PR describing the missing generic capability and ABI approach. Maintainers may prefer naming or placement changes. Keep the implementation easy to reshape by avoiding consumer-specific dependencies.

Suggested OpenCPN PR title:

`Add provider-neutral vector chart object query API`

Suggested summary:

`Adds a versioned callback API allowing plugins to enumerate nearby vector-chart objects with copied WGS84 geometry and raw attributes. Native S-57 is supported in core; plugin chart providers can opt in through new Plus3 chart-base extensions without changing existing provider vtables.`
