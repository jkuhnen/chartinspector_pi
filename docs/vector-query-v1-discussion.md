# Vector object query API v1 —  draft

This is a draft for a possible OpenCPN plugin API.

The goal is simple: allow a plugin to ask OpenCPN which vector chart objects are near a given position and get back their class, attributes and geographic geometry.

## First version

I would keep v1 intentionally small:

- read-only
- provider-independent
- query by latitude/longitude plus a small search radius
- Point / Line / Area geometry
- return feature class, object name, raw attributes and geometry
- bounded result sizes
- versioned plain C/POD structures across the plugin ABI

Chart Inspector would do the final object choice, hover timing, highlighting and presentation itself. None of that should be part of the API.

## Rough API shape

```cpp
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

struct PI_VectorAttributeV1 {
  const char* name_utf8;
  const char* value_utf8;
};

struct PI_VectorObjectV1 {
  uint32_t struct_size;
  uint32_t geometry_type;   // point / line / area
  const char* feature_class_utf8;
  const char* object_name_utf8;
  const PI_VectorPositionV1* points;
  uint32_t point_count;
  const PI_VectorAttributeV1* attributes;
  uint32_t attribute_count;
};

typedef bool (*PI_VectorObjectSinkV1)(
    const PI_VectorObjectV1* object,
    void* user_data);

bool QueryVectorChartObjectsV1(
    int canvas_index,
    const PI_VectorQueryV1* query,
    PI_VectorObjectSinkV1 sink,
    void* user_data);
```

For multipart lines/areas a small `parts` array may also be needed, but I would rather keep that detail open for discussion than lock it in too early.

## Not in v1

I would leave these out of the first version:

- Chart Inspector-specific selection rules
- highlight colours or UI strings
- loading charts just to answer a query
- special lookup of SCAMIN-hidden objects
- provider-specific handles/pointers
- editing chart data

The idea is only to expose a small, safe, generic read-only query. If the basic shape makes sense, the implementation can be discussed afterwards.
