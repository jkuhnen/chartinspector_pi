set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()
file(READ "${CPP}" C)

string(FIND "${C}" "CHARTINSPECTOR_VECTOR_HOVER_V1" BASE)
if(BASE EQUAL -1)
  message(FATAL_ERROR "Hover highlight v1 is not installed in src/chartinspector_pi.cpp")
endif()
string(FIND "${C}" "CHARTINSPECTOR_HOVER_NEAREST_V1" DONE)
if(NOT DONE EQUAL -1)
  message(STATUS "Nearest-geometry hover ranking already installed")
  return()
endif()

set(OLD_CAND [===[
struct CI_HoverCandidate {
  uint32_t geometry = 0;
  wxString feature;
  std::vector<CI_HoverPosition> points;
  std::vector<CI_HoverPart> parts;
  int score = -100000;
};
]===])
set(NEW_CAND [===[
// CHARTINSPECTOR_HOVER_NEAREST_V1
struct CI_HoverCandidate {
  uint32_t geometry = 0;
  wxString feature;
  std::vector<CI_HoverPosition> points;
  std::vector<CI_HoverPart> parts;
  int score = -100000;
  double cursorLat = 0.0;
  double cursorLon = 0.0;
  double distanceMetres = 1.0e100;
};

static double CI_DistancePointSegmentMetres(double qlat, double qlon,
                                             double alat, double alon,
                                             double blat, double blon) {
  const double kLatM = 111319.49079327357;
  const double cosLat = std::max(0.01, std::cos(qlat * 3.14159265358979323846 / 180.0));
  const double kLonM = kLatM * cosLat;
  const double ax = (alon - qlon) * kLonM;
  const double ay = (alat - qlat) * kLatM;
  const double bx = (blon - qlon) * kLonM;
  const double by = (blat - qlat) * kLatM;
  const double vx = bx - ax;
  const double vy = by - ay;
  const double vv = vx * vx + vy * vy;
  double t = vv > 1.0e-12 ? -(ax * vx + ay * vy) / vv : 0.0;
  t = std::max(0.0, std::min(1.0, t));
  const double x = ax + t * vx;
  const double y = ay + t * vy;
  return std::sqrt(x * x + y * y);
}

static double CI_ObjectDistanceMetres(const CI_VectorObjectV1 *o,
                                      double qlat, double qlon) {
  if (!o || !o->points || !o->point_count) return 1.0e100;
  if (o->geometry_type == 1 || o->point_count == 1) {
    const double dy = (o->points[0].lat - qlat) * 111319.49079327357;
    const double dx = (o->points[0].lon - qlon) * 111319.49079327357 *
                      std::max(0.01, std::cos(qlat * 3.14159265358979323846 / 180.0));
    return std::sqrt(dx * dx + dy * dy);
  }

  double best = 1.0e100;
  if (o->parts && o->part_count) {
    for (uint32_t p = 0; p < o->part_count; ++p) {
      const uint32_t first = o->parts[p].first_point;
      const uint32_t count = o->parts[p].point_count;
      if (count < 2 || first >= o->point_count) continue;
      const uint32_t end = std::min<uint32_t>(o->point_count, first + count);
      for (uint32_t i = first + 1; i < end; ++i) {
        best = std::min(best, CI_DistancePointSegmentMetres(
            qlat, qlon, o->points[i - 1].lat, o->points[i - 1].lon,
            o->points[i].lat, o->points[i].lon));
      }
    }
  } else {
    for (uint32_t i = 1; i < o->point_count; ++i) {
      best = std::min(best, CI_DistancePointSegmentMetres(
          qlat, qlon, o->points[i - 1].lat, o->points[i - 1].lon,
          o->points[i].lat, o->points[i].lon));
    }
  }
  return best;
}
]===])
string(FIND "${C}" "${OLD_CAND}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_HoverCandidate")
endif()
string(REPLACE "${OLD_CAND}" "${NEW_CAND}" C "${C}")

set(OLD_COLLECT [===[
  const wxString feature = wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "").Upper();
  const int score = CI_FeatureScore(feature, o->geometry_type);
  if (score <= best->score) return true;
  CI_HoverCandidate next;
  next.geometry = o->geometry_type; next.feature = feature; next.score = score;
]===])
set(NEW_COLLECT [===[
  const wxString feature = wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "").Upper();
  const int score = CI_FeatureScore(feature, o->geometry_type);
  const double distance = CI_ObjectDistanceMetres(o, best->cursorLat, best->cursorLon);
  // Semantic priority remains useful (buoys/lights/points before generic
  // areas), but candidates with equal priority are now ordered by the actual
  // distance from the cursor to their returned geometry rather than provider
  // iteration order.
  if (score < best->score ||
      (score == best->score && distance >= best->distanceMetres)) return true;
  CI_HoverCandidate next;
  next.geometry = o->geometry_type; next.feature = feature; next.score = score;
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
]===])
string(FIND "${C}" "${OLD_COLLECT}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_CollectHover ranking block")
endif()
string(REPLACE "${OLD_COLLECT}" "${NEW_COLLECT}" C "${C}")

set(OLD_BEST [===[
  CI_HoverCandidate best;
  queryFn(0, &q, CI_CollectHover, &best);
]===])
set(NEW_BEST [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  queryFn(0, &q, CI_CollectHover, &best);
]===])
string(FIND "${C}" "${OLD_BEST}" P)
if(P EQUAL -1)
  message(FATAL_ERROR "Could not locate hover query candidate setup")
endif()
string(REPLACE "${OLD_BEST}" "${NEW_BEST}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed nearest-geometry hover ranking v1")
message(STATUS "  equal-priority line/area candidates ranked by cursor-to-segment distance")
message(STATUS "  point candidates ranked by cursor-to-point distance")
message(STATUS "  provider iteration order no longer decides between nearby lines")
