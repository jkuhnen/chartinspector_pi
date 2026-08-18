# OpenCPN Vector Object Query API proposal

Status: design draft for Chart Inspector / upstream discussion

## Goal

Provide plugins with a small, provider-neutral way to inspect vector-chart objects at a geographic position without exposing `S57Obj`, `PI_S57Obj`, render-rule objects, vertex buffers or provider-owned pointers.

The API is intentionally limited to **query + copied geometry + copied attributes**. Rendering, hover policy, hit-test ranking and UI remain the responsibility of the consuming plugin.

## Design requirements

1. Safe across plugin DLL boundaries.
2. No provider-owned pointers in returned data.
3. Works for native S-57 and plugin-provided vector charts such as o-charts.
4. Point, line and area geometry use the same representation.
5. Coordinates are WGS84 latitude/longitude in decimal degrees.
6. Area interiors are not special-cased by the API; consumers can choose boundary-only or interior hit testing.
7. Existing chart plugins remain compatible. A provider which does not implement the extension simply returns no geometry through the new path.
8. The API does not contain Chart Inspector-specific concepts such as cyan highlighting, tooltips or feature priorities.

## Public data types

```cpp
enum class PI_VectorGeometryType : uint8_t {
  Unknown = 0,
  Point = 1,
  Line = 2,
  Area = 3
};

struct PI_VectorPosition {
  double lat = 0.0;
  double lon = 0.0;
};

struct PI_VectorGeometryPart {
  // Index into PI_VectorObject::points.
  // A line normally has one part. Areas may have one exterior ring and
  // additional rings. Multi-part objects may contain several parts.
  uint32_t first_point = 0;
  uint32_t point_count = 0;
};

struct PI_VectorAttribute {
  // S-57/S-101 acronym or provider-neutral attribute identifier.
  // Examples: "OBJNAM", "COLOUR", "LITCHR".
  std::string name;
  std::string value;
};

struct PI_VectorObject {
  // Provider object class identifier, e.g. "BOYLAT", "RESARE", "FAIRWY".
  std::string feature_class;

  // Human-readable object name when supplied by the chart.
  std::string object_name;

  PI_VectorGeometryType geometry_type = PI_VectorGeometryType::Unknown;

  // Fully copied geographic geometry. No pointer references provider memory.
  std::vector<PI_VectorPosition> points;
  std::vector<PI_VectorGeometryPart> parts;

  // Fully copied raw attributes. Decoding remains a consumer responsibility.
  std::vector<PI_VectorAttribute> attributes;
};
```

## Query

```cpp
struct PI_VectorObjectQuery {
  double lat = 0.0;
  double lon = 0.0;

  // Search envelope in screen pixels. The provider/core may use this to
  // reduce candidate enumeration. It is not a request to perform the final
  // pixel-distance hit test.
  double search_radius_pixels = 8.0;

  // Optional comma-separated exact/wildcard filter. Empty means all classes.
  // Example: "BOY*,BCN*,LIGHTS,RESARE".
  std::string feature_filter;
};

// Returns candidate vector objects close enough to the query position to be
// useful to an interactive consumer. Returned objects and all nested data are
// owned by the caller.
DECL_IMP bool GetVectorChartObjects(
    int canvas_index,
    const PI_VectorObjectQuery& query,
    std::vector<PI_VectorObject>* objects);
```

`GetVectorChartObjects()` is the only function Chart Inspector needs from the OpenCPN side.

## Provider side

For native S-57 charts OpenCPN populates `PI_VectorObject` directly from its internal chart model.

Plugin chart providers get one optional extension point. The exact ABI mechanism should follow OpenCPN maintainer preference, but its semantic contract is deliberately small:

```cpp
class PlugInVectorObjectProvider {
public:
  virtual ~PlugInVectorObjectProvider() = default;

  virtual bool GetVectorObjects(
      const PI_VectorObjectQuery& query,
      const PlugIn_ViewPort& viewport,
      std::vector<PI_VectorObject>* objects) = 0;
};
```

Important: the provider returns copied geographic geometry, not rendering buffers or opaque handles.

If adding an optional C++ interface is considered too risky for the existing plugin ABI, the same contract can be exposed using a versioned C callback/extension registration mechanism. The data model above should stay unchanged.

## Ownership

All returned strings, vectors, positions, parts and attributes are owned by the caller after the query returns.

No returned value may contain:

- `S57Obj*`
- `PI_S57Obj*`
- `ObjRazRules*`
- `chart_context*`
- VBO offsets
- render-rule pointers
- provider-owned geometry pointers

This is the central safety requirement.

## Geometry semantics

### Point

`geometry_type == Point`

`points` normally contains one position. `parts` may be empty.

### Line

`geometry_type == Line`

`points` contains ordered vertices. Each `parts` entry identifies one independent polyline.

### Area

`geometry_type == Area`

Each part is a ring. The API does not require a winding convention for the first version. Providers should preserve their source order. A later API revision may add explicit exterior/hole roles if required.

For Chart Inspector, area selection is performed against ring boundaries, not by testing whether the cursor lies anywhere inside the polygon.

## Hit testing belongs to the consumer

OpenCPN/provider supplies candidates and geometry. Chart Inspector calculates the final screen-space distance using the active viewport:

- Point: cursor to point/symbol anchor.
- Line: minimum cursor-to-segment distance.
- Area: minimum cursor-to-ring-segment distance.

This keeps interaction policy outside the core and prevents a Chart Inspector-specific API.

## Candidate selection

The core/provider should return a small candidate set around the query position. It should not decide which object is the UI winner.

Chart Inspector can then rank candidates using:

1. actual pixel distance,
2. geometry type / navigational relevance,
3. display priority if such metadata is added later,
4. configured class filter.

The initial API deliberately does not expose S-52 rendering internals.

## Attributes

The API returns raw chart attributes as key/value strings. Examples:

```text
OBJNAM=Nord cardinal buoy
COLOUR=2,6
LITCHR=4
SIGGRP=(3)
SIGPER=10
```

Chart Inspector continues to decode these using the official S-57 catalogue. This prevents OpenCPN core from becoming responsible for Chart Inspector presentation strings.

## Scope deliberately excluded from v1

- Depth soundings / multipoint sounding arrays.
- Raster charts.
- S-52 symbol geometry.
- Text-label bounding boxes.
- Highlight colours or drawing instructions.
- UI strings.
- Provider-specific opaque identifiers.
- Editing chart data.

These can be considered separately if real use cases appear.

## Chart Inspector defaults

Chart Inspector will normally suppress low-value inspection targets such as individual soundings, depth areas/contours and chart metadata. This is a Chart Inspector policy and is not encoded in the OpenCPN API.

## Why this replaces the V1-V5 prototype exports

The experimental `OCPNChartInspectorHitTestV*` exports mixed candidate discovery, hit testing, provider internals and Chart Inspector policy. They proved the interaction concept but are not suitable as a public API.

The proposed API has one responsibility:

> Return safe, copied vector object data and geographic geometry near a requested position.

Everything else stays outside the core.

## Proposed implementation sequence

1. Add public data types and `GetVectorChartObjects()` to the OpenCPN plugin API on an experimental branch.
2. Implement native S-57 conversion in OpenCPN.
3. Add the optional provider extension mechanism.
4. Implement the provider extension in o-charts using its internal `S57Obj` geometry while copying all output.
5. Switch Chart Inspector from the private V5 export to `GetVectorChartObjects()`.
6. Test point, line, area and multi-part objects under Day/Dusk/Night and multiple zoom levels.
7. Remove the private `OCPNChartInspectorHitTestV*` prototype code.
8. Prepare an upstream OpenCPN proposal/PR with the generic API independent of Chart Inspector UI.
