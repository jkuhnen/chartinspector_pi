# OpenCPN Vector Object Query API v1

Status: upstream-oriented API proposal

## Goal

Add a small, provider-neutral OpenCPN plugin API which lets ordinary plugins inspect nearby vector-chart objects without exposing `S57Obj`, `PI_S57Obj`, render rules, VBOs or provider-owned pointers.

The API has one responsibility:

> Enumerate safe vector-object candidates, including geographic geometry and raw attributes, near a requested position.

Selection policy, hover behaviour, highlighting and UI remain outside OpenCPN core.

## Upstream design decisions

The v1 proposal follows existing OpenCPN chart-provider extension patterns.

1. The consumer API is an exported OpenCPN function.
2. Native S-57 is implemented directly by OpenCPN core.
3. Plugin chart providers opt in using new derived `Plus3` chart-base classes.
4. Existing chart providers remain binary compatible because no virtual method is added to an existing base class.
5. The DLL boundary uses only versioned POD structures and callbacks.
6. No STL or wx container owns data across the DLL boundary.
7. Callback pointers are borrowed only for the duration of the callback.
8. All coordinates are WGS84 decimal degrees.
9. Point, line and area objects share one geometry representation.
10. The API contains no Chart Inspector-specific concepts.

Current OpenCPN master uses plugin API 1.21. The eventual upstream change should use the next minor API version according to maintainer convention; the working proposal assumes 1.22.

## Public ABI

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
  const char* name_utf8;
  const char* value_utf8;
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

typedef bool (*PI_VectorObjectSinkV1)(
    const PI_VectorObjectV1* object,
    void* user_data);

DECL_IMP bool QueryVectorChartObjectsV1(
    int canvas_index,
    const PI_VectorQueryV1* query,
    PI_VectorObjectSinkV1 sink,
    void* user_data);
```

`search_radius_pixels` is only a candidate-enumeration hint. The API does not choose the winning object for the UI.

## Provider extension

OpenCPN already discovers optional chart-provider capabilities using derived chart-base classes and `dynamic_cast`. v1 extends the same pattern rather than modifying existing vtables.

Two provider families are supported because OpenCPN already has both GL and Extended chart-provider hierarchies:

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

class DECL_EXP PlugInChartBaseExtendedPlus3
    : public PlugInChartBaseExtendedPlus2 {
public:
  PlugInChartBaseExtendedPlus3();
  virtual ~PlugInChartBaseExtendedPlus3();

  virtual bool QueryVectorObjectsV1(
      const PI_VectorQueryV1* query,
      const PlugIn_ViewPort* viewport,
      PI_VectorObjectSinkV1 sink,
      void* user_data);
};
```

Default implementations return `false`. Existing providers which remain on Plus2 are unaffected.

## Ownership and safety

All pointers supplied to `PI_VectorObjectSinkV1` are valid only until that callback returns. Consumers must copy any data they retain.

Forbidden across the ABI boundary:

- `std::vector` / `std::string`
- wx containers / `wxString`
- `S57Obj*` / `PI_S57Obj*`
- `ObjRazRules*`
- `chart_context*`
- VBO pointers or offsets
- provider-specific handles

Providers may use these internally while preparing one callback invocation.

Core should validate provider output and enforce defensive limits before forwarding it to ordinary plugins. Initial working limits are 256 candidates/query, 16384 points/object, 1024 parts/object, 512 attributes/object and 8192 UTF-8 bytes/string.

## Geometry semantics

### Point

`geometry_type == PI_VECTOR_GEOMETRY_POINT_V1`.

Normally one point and no parts.

### Line

One or more parts reference contiguous ranges in `points`. Parts are not implicitly closed.

### Area

One or more parts represent rings. Rings are implicitly closed; the first point does not have to be duplicated at the end. v1 deliberately does not encode exterior/hole roles.

## Candidate versus hit test

The core/provider returns nearby candidates and their true geographic geometry. The consuming plugin performs final screen-space hit testing:

- point: distance to point anchor,
- line: minimum point-to-segment distance,
- area: minimum point-to-ring-boundary distance.

This is important for generality: OpenCPN does not gain Chart Inspector-specific selection rules.

## Attributes

Attributes are raw UTF-8 name/value pairs, for example:

```text
OBJNAM=...
COLOUR=2,6
LITCHR=4
SIGGRP=(3)
SIGPER=10
```

Presentation and catalogue decoding stay in the consumer.

## Deliberately excluded from v1

- raster charts,
- UI strings,
- highlight colours,
- S-52 symbol geometry,
- text-label bounds,
- editing chart data,
- provider-specific opaque identifiers,
- Chart Inspector feature priorities,
- depth-sounding special handling.

## Reference implementations

The upstream proposal should contain native S-57 support in OpenCPN core. o-charts is the first external provider reference because its `eSENCChart` already owns the necessary S-57 object structures and candidate-query logic internally.

The final data path is:

```text
ordinary plugin
    |
    v
QueryVectorChartObjectsV1()
    |
    +-- native S-57 -> OpenCPN converts internal S57Obj
    |
    +-- plugin chart wrapper
            |
            +-- GLPlus3 provider
            |
            +-- ExtendedPlus3 provider (o-charts)
```

Chart Inspector therefore never needs to know whether the active ENC is native or supplied by o-charts.

## Upstream implementation sequence

1. Develop against current OpenCPN master, not the old private Chart Inspector hit-test patches.
2. Add API 1.22 POD declarations, callback and Plus3 provider classes.
3. Add `QueryVectorChartObjectsV1()` with native S-57 conversion.
4. Add provider dispatch with both Plus3 hierarchies.
5. Add focused OpenCPN tests for ABI validation and malformed provider results where practical.
6. Implement ExtendedPlus3 in an o-charts development branch.
7. Test Point, Line, Area and multipart geometry on the same ENC positions against OpenCPN's existing object query.
8. Switch Chart Inspector to the public API.
9. Remove the private `OCPNChartInspectorHitTestV*` prototype path.
10. Prepare an OpenCPN PR containing only generic API/core code and tests; keep Chart Inspector and o-charts changes in separate PRs.

## Upstream PR framing

The problem statement for OpenCPN should be generic:

> Plugins currently cannot safely query geometry and raw attributes for arbitrary nearby vector-chart objects independent of the active chart provider. This API adds a versioned, ABI-safe enumeration mechanism while preserving provider and consumer binary compatibility.

Chart Inspector is a motivating consumer and test client, not part of the OpenCPN API contract.
