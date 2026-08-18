# ABI-safe provider extension for vector object queries

Status: design draft

## Conclusion

For a publishable OpenCPN API, do **not** add new virtual methods to the existing `PlugInChartBaseGL` class and do **not** exchange STL containers across DLL boundaries.

Use the same extension pattern OpenCPN already uses for chart-provider capabilities: define a new derived class, tentatively `PlugInChartBaseGLPlus3`, and let OpenCPN discover it using `dynamic_cast`.

OpenCPN already uses this pattern with `PlugInChartBaseGLPlus2` for light-object queries. This keeps old chart plugins binary-compatible because existing providers continue deriving from the older base classes and are never forced to implement the new method.

The new virtual method itself should use only fixed-layout POD structures, caller-owned buffers and callbacks. No `std::vector`, `std::string`, wx containers, or provider-owned pointers cross the provider/core boundary.

## Why a new derived class

Existing pattern:

```cpp
class PlugInChartBaseGLPlus2 : public PlugInChartBaseGL {
public:
  virtual ListOfPI_S57Obj* GetLightsObjRuleListVisibleAtLatLon(...);
};
```

OpenCPN discovers support at runtime:

```cpp
auto* provider = dynamic_cast<PlugInChartBaseGLPlus2*>(chart);
if (provider) {
  // extension supported
}
```

We should continue this model:

```cpp
class PlugInChartBaseGLPlus3 : public PlugInChartBaseGLPlus2 {
public:
  virtual bool QueryVectorObjects(
      const PI_VectorQueryV1* query,
      PI_VectorObjectSinkV1 sink,
      void* user_data);
};
```

Old providers remain unchanged. New providers opt in by deriving from Plus3.

## ABI boundary rules

The following are forbidden in the Plus3 method signature and all structures passed through it:

- `std::vector`
- `std::string`
- `wxString`
- `wxArray*`
- owning C++ objects
- `S57Obj*`
- `PI_S57Obj*`
- `ObjRazRules*`
- `chart_context*`
- VBO pointers or offsets as public geometry
- provider-specific handles

The provider may use any of these internally while preparing the response, but only copied POD data is delivered to OpenCPN.

## Versioned POD structures

All structures carry a `struct_size` field. This allows future OpenCPN releases to append fields without changing the meaning of the existing prefix.

```cpp
enum PI_VectorGeometryTypeV1 : uint32_t {
  PI_VECTOR_GEOMETRY_UNKNOWN_V1 = 0,
  PI_VECTOR_GEOMETRY_POINT_V1 = 1,
  PI_VECTOR_GEOMETRY_LINE_V1 = 2,
  PI_VECTOR_GEOMETRY_AREA_V1 = 3
};

struct PI_VectorQueryV1 {
  uint32_t struct_size;
  double lat;
  double lon;
  double search_radius_pixels;
  const char* feature_filter_utf8;  // borrowed, valid for call duration
};

struct PI_VectorPositionV1 {
  double lat;
  double lon;
};

struct PI_VectorPartV1 {
  uint32_t first_point;
  uint32_t point_count;
};

struct PI_VectorAttributeV1 {
  const char* name_utf8;   // borrowed for callback duration only
  const char* value_utf8;  // borrowed for callback duration only
};

struct PI_VectorObjectV1 {
  uint32_t struct_size;
  uint32_t geometry_type;

  const char* feature_class_utf8;
  const char* object_name_utf8;

  const PI_VectorPositionV1* points;
  uint32_t point_count;

  const PI_VectorPartV1* parts;
  uint32_t part_count;

  const PI_VectorAttributeV1* attributes;
  uint32_t attribute_count;
};
```

## Callback ownership model

The provider owns all pointers while invoking the callback. They are valid only until the callback returns.

```cpp
typedef bool (*PI_VectorObjectSinkV1)(
    const PI_VectorObjectV1* object,
    void* user_data);
```

The callback returns `true` to continue enumeration and `false` to stop early.

OpenCPN copies any object it wants to retain into core-owned storage inside the callback. This eliminates cross-DLL allocation/deallocation entirely.

The provider implementation can therefore use local vectors/strings internally, as long as their `.data()`/`.c_str()` pointers remain valid for the duration of the callback.

## Proposed provider class

```cpp
class DECL_EXP PlugInChartBaseGLPlus3 : public PlugInChartBaseGLPlus2 {
public:
  PlugInChartBaseGLPlus3();
  virtual ~PlugInChartBaseGLPlus3();

  virtual bool QueryVectorObjectsV1(
      const PI_VectorQueryV1* query,
      const PlugIn_ViewPort* viewport,
      PI_VectorObjectSinkV1 sink,
      void* user_data);
};
```

The default OpenCPN implementation returns `false`, although in practice only providers deriving from Plus3 are queried.

## Core-facing API

The provider ABI above is not necessarily the public API consumed by ordinary plugins such as Chart Inspector.

Inside OpenCPN, the callback data is immediately copied to a core representation. The consumer-facing OpenCPN plugin API can then expose a similarly versioned callback query:

```cpp
typedef bool (*PI_VectorObjectResultSinkV1)(
    const PI_VectorObjectV1* object,
    void* user_data);

DECL_IMP bool QueryVectorChartObjectsV1(
    int canvas_index,
    const PI_VectorQueryV1* query,
    PI_VectorObjectResultSinkV1 sink,
    void* user_data);
```

For native S-57 charts, OpenCPN enumerates internal `S57Obj` candidates and converts them to `PI_VectorObjectV1` directly.

For plugin charts, OpenCPN checks:

```cpp
auto* provider =
    dynamic_cast<PlugInChartBaseGLPlus3*>(target->GetPlugInChart());
```

and calls `QueryVectorObjectsV1()` when available.

The Chart Inspector therefore does not know or care whether the active chart is native S-57 or o-charts.

## Why callbacks instead of caller-sized flat arrays

A two-pass `count -> allocate -> fill` API is also ABI-safe, but it becomes awkward because each object has variable numbers of:

- points,
- rings/parts,
- attributes,
- strings.

A callback keeps the ABI tiny and requires no cross-module allocator contract.

It also supports early termination and natural candidate streaming.

## String rules

All strings are UTF-8, NUL terminated.

Pointers are borrowed for callback duration only.

No consumer may retain the pointers after the callback returns.

Empty optional strings are represented by either `nullptr` or `""`; the API documentation should recommend `nullptr` for absent values.

## Geometry rules

Coordinates are WGS84 decimal-degree latitude/longitude.

`Point`:
- normally `point_count == 1`
- `part_count == 0`

`Line`:
- one or more parts
- parts reference contiguous ranges in `points`
- parts are not implicitly closed

`Area`:
- one or more ring parts
- each part is implicitly closed; providers do not need to duplicate the first point at the end
- v1 does not identify exterior versus hole rings

A later structure version may append a ring-role field without changing v1 layout prefixes.

## Query semantics

`search_radius_pixels` is a candidate-search hint, not final UI hit testing.

A provider should return nearby objects whose geometry could plausibly be relevant within the requested radius. It should not implement Chart Inspector selection policy.

Chart Inspector performs final screen-space distance calculations itself:

- point -> distance to anchor,
- line -> distance to line segments,
- area -> distance to ring boundaries.

## Feature filtering

`feature_filter_utf8` is optional.

For v1 it may use the same comma-separated exact/wildcard syntax already prototyped by Chart Inspector, for example:

```text
BOY*,BCN*,LIGHTS,RESARE,FAIRWY
```

An empty/null filter means all provider-visible vector objects.

Whether wildcard parsing belongs in OpenCPN or providers should be resolved during upstream review. A simple alternative is to omit filtering from the provider contract and let OpenCPN/consumer filter candidates after enumeration.

For the first upstream proposal, omitting provider-side filtering may be cleaner and more generic.

## Error behavior

`QueryVectorObjectsV1()` returns:

- `true`: query executed, including the valid case where zero objects were emitted,
- `false`: provider does not support the query or could not execute it.

The sink may return `false` to stop enumeration; this is not an error.

Malformed provider objects are skipped by OpenCPN after sanity checks:

- non-finite coordinates,
- invalid part ranges,
- excessive point/attribute counts,
- null mandatory feature-class string.

OpenCPN should impose defensive upper limits before copying data.

## Suggested defensive limits in core

Initial conservative defaults:

```text
max candidates per query:     256
max points per object:       16384
max parts per object:         1024
max attributes per object:     512
max UTF-8 string length:      8192 bytes
```

These are safety limits, not chart-model constraints, and can be adjusted after real-world testing.

## API version

This should be introduced as a new OpenCPN plugin API minor version rather than a private Chart Inspector export.

Current upstream master defines API version 1.21. The eventual PR would increment the minor version according to OpenCPN maintainer conventions.

Chart Inspector can feature-detect the exported `QueryVectorChartObjectsV1()` symbol at runtime while development occurs. Once the API is released, it can use the normal API version/compatibility mechanism.

## Migration from the prototype

Development path:

1. Keep stable V5 prototype only as a temporary fallback.
2. Implement the POD structures and `PlugInChartBaseGLPlus3` in the experimental OpenCPN tree.
3. Implement `QueryVectorChartObjectsV1()` for native S-57 first.
4. Verify Point/Line/Area behavior using unencrypted native ENC.
5. Add Plus3 support to o-charts and copy geometry directly from its internal objects during the callback.
6. Switch Chart Inspector to the public query API.
7. Remove all `OCPNChartInspectorHitTestV*` exports.
8. Prepare an upstream PR which contains only the generic API and tests, not Chart Inspector-specific code.

## Why this is a better upstream proposal

The API solves a generic limitation:

> plugins cannot safely inspect geometry and attributes of arbitrary vector-chart objects independent of the chart provider.

It does not mention hover colours, info cards, buoy animation, or other Chart Inspector UI details.

That separation makes the proposal useful to other plugin authors and keeps OpenCPN core responsibilities small.
