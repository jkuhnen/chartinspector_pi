#include "s57_catalog.h"

#include <wx/filename.h>
#include <wx/textfile.h>
#include <wx/tokenzr.h>

namespace {
wxString JoinPath(const wxString &base, const wxString &name) {
  wxFileName path(base, name);
  return path.GetFullPath();
}
}

bool S57Catalog::Load(const wxString &sharedDataDirectory) {
  m_objectNames.clear();
  m_attributes.clear();
  m_attributeByCode.clear();
  m_decodes.clear();
  m_loaded = false;

  wxFileName s57Dir(sharedDataDirectory, wxEmptyString);
  s57Dir.AppendDir("s57data");
  const wxString base = s57Dir.GetFullPath();

  const bool objectsOk = LoadObjectClasses(JoinPath(base, "s57objectclasses.csv"));
  const bool attributesOk = LoadAttributes(JoinPath(base, "s57attributes.csv"));
  const bool decodesOk = LoadAttributeDecodes(JoinPath(base, "attdecode.csv"));
  const bool expectedOk = LoadExpectedInput(JoinPath(base, "s57expectedinput.csv"));

  // attdecode is useful but s57expectedinput is the authoritative fallback
  // for enum values which are missing from attdecode in some installations.
  m_loaded = objectsOk && attributesOk && (decodesOk || expectedOk);
  return m_loaded;
}

wxString S57Catalog::ObjectName(const wxString &acronym) const {
  auto it = m_objectNames.find(acronym.Upper());
  return it == m_objectNames.end() ? acronym : it->second;
}

std::vector<S57Catalog::ObjectClassInfo> S57Catalog::ObjectClasses() const {
  std::vector<ObjectClassInfo> result;
  for (const auto &entry : m_objectNames) result.push_back({entry.first, entry.second});
  return result;
}

wxString S57Catalog::FormatAttributes(const wxString &rawAttributes,
                                      wxString *technical) const {
  wxString result;
  wxString raw;
  wxStringTokenizer lines(rawAttributes, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = Trimmed(lines.GetNextToken());
    if (line.IsEmpty()) continue;

    const int equals = line.Find('=');
    if (equals == wxNOT_FOUND) continue;

    const wxString acronym = Trimmed(line.Left(equals)).Upper();
    const wxString rawValue = Trimmed(line.Mid(equals + 1));

    // Technical renderer metadata is deliberately hidden from the readable UI.
    if (acronym.StartsWith("$")) {
      if (!raw.IsEmpty()) raw += "\n";
      raw += line;
      continue;
    }

    wxString catalogLabel = acronym;
    auto attr = m_attributes.find(acronym);
    if (attr != m_attributes.end() && !attr->second.name.IsEmpty())
      catalogLabel = attr->second.name;

    wxString decoded;
    bool decodedAny = false;
    if (acronym == "CATGEO") {
      if (rawValue == "1") decoded = "Point";
      else if (rawValue == "2") decoded = "Line";
      else if (rawValue == "3") decoded = "Area";
      else decoded = rawValue;
      decodedAny = decoded != rawValue;
    } else if (acronym == "DATSTA" || acronym == "DATEND" ||
               acronym == "PERSTA" || acronym == "PEREND" ||
               acronym == "RECDAT" || acronym == "SORDAT") {
      decoded = FormatDate(rawValue);
      decodedAny = decoded != rawValue;
    } else {
      decoded = DecodeAttributeValue(acronym, rawValue, &decodedAny);
    }

    // Keep undecoded raw metadata out of the primary readable view.
    // It remains available in the technical block.
    if (!decodedAny && attr == m_attributes.end()) {
      if (!raw.IsEmpty()) raw += "\n";
      raw += line;
      continue;
    }

    const wxString label = FriendlyLabel(acronym, catalogLabel);
    if (!result.IsEmpty()) result += "\n";
    result += label + ": " + decoded;

    if (!decodedAny) {
      if (!raw.IsEmpty()) raw += "\n";
      raw += line;
    }
  }

  if (technical) *technical = raw;
  return result;
}

std::vector<wxString> S57Catalog::ParseCsvLine(const wxString &line) {
  std::vector<wxString> fields;
  wxString field;
  bool quoted = false;
  for (size_t i = 0; i < line.length(); ++i) {
    const wxChar ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length() && line[i + 1] == '"') {
        field += '"';
        ++i;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      fields.push_back(field);
      field.clear();
    } else {
      field += ch;
    }
  }
  fields.push_back(field);
  return fields;
}

wxString S57Catalog::Trimmed(wxString value) {
  value.Trim(true);
  value.Trim(false);
  return value;
}

wxString S57Catalog::UppercaseFirst(const wxString &value) {
  if (value.IsEmpty()) return value;
  wxString result = value;
  result[0] = wxToupper(result[0]);
  return result;
}

wxString S57Catalog::FriendlyLabel(const wxString &acronym,
                                   const wxString &catalogLabel) {
  if (acronym == "CATGEO") return "Geometry";
  if (acronym == "SCAMIN") return "Minimum display scale";
  if (acronym == "SCAMAX") return "Maximum display scale";
  if (acronym == "OBJNAM") return "Name";
  if (acronym == "NOBJNM") return "National name";
  return UppercaseFirst(catalogLabel);
}

wxString S57Catalog::FormatDate(const wxString &value) {
  // Valid S-57 dates are YYYYMMDD; incomplete or malformed values are better
  // kept as technical data than presented as a misleading date.
  if (value.length() != 8) return value;
  long year = 0, month = 0, day = 0;
  if (!value.Left(4).ToLong(&year) || !value.Mid(4, 2).ToLong(&month) ||
      !value.Mid(6, 2).ToLong(&day) || year < 1 || month < 1 || month > 12 ||
      day < 1 || day > 31)
    return value;
  return wxString::Format("%04ld-%02ld-%02ld", year, month, day);
}

bool S57Catalog::LoadObjectClasses(const wxString &path) {
  wxTextFile file;
  if (!file.Open(path)) return false;
  for (size_t i = 1; i < file.GetLineCount(); ++i) {
    const auto fields = ParseCsvLine(file.GetLine(i));
    if (fields.size() < 3) continue;
    const wxString name = Trimmed(fields[1]);
    const wxString acronym = Trimmed(fields[2]).Upper();
    if (!acronym.IsEmpty() && !name.IsEmpty()) m_objectNames[acronym] = name;
  }
  return true;
}

bool S57Catalog::LoadAttributes(const wxString &path) {
  wxTextFile file;
  if (!file.Open(path)) return false;
  for (size_t i = 1; i < file.GetLineCount(); ++i) {
    const auto fields = ParseCsvLine(file.GetLine(i));
    if (fields.size() < 4) continue;
    long code = -1;
    Trimmed(fields[0]).ToLong(&code);
    const wxString name = Trimmed(fields[1]);
    const wxString acronym = Trimmed(fields[2]).Upper();
    const wxString type = Trimmed(fields[3]).Upper();
    if (!acronym.IsEmpty()) {
      m_attributes[acronym] = {code, name, type};
      if (code >= 0) m_attributeByCode[code] = acronym;
    }
  }
  return true;
}

bool S57Catalog::LoadAttributeDecodes(const wxString &path) {
  wxTextFile file;
  if (!file.Open(path)) return false;
  for (size_t i = 1; i < file.GetLineCount(); ++i) {
    const auto fields = ParseCsvLine(file.GetLine(i));
    if (fields.size() < 2) continue;
    const wxString acronym = Trimmed(fields[0]).Upper();
    if (acronym.IsEmpty()) continue;

    wxStringTokenizer tokens(fields[1], ";", wxTOKEN_RET_EMPTY_ALL);
    std::vector<wxString> parts;
    while (tokens.HasMoreTokens()) parts.push_back(tokens.GetNextToken());
    DecodeTable &table = m_decodes[acronym];
    for (size_t j = 0; j + 1 < parts.size(); j += 2) {
      const wxString key = Trimmed(parts[j]);
      const wxString value = Trimmed(parts[j + 1]);
      if (!key.IsEmpty() && !value.IsEmpty()) table[key] = value;
    }
  }
  return true;
}

bool S57Catalog::LoadExpectedInput(const wxString &path) {
  wxTextFile file;
  if (!file.Open(path)) return false;
  for (size_t i = 1; i < file.GetLineCount(); ++i) {
    const auto fields = ParseCsvLine(file.GetLine(i));
    if (fields.size() < 3) continue;
    long code = -1;
    if (!Trimmed(fields[0]).ToLong(&code)) continue;
    auto acronymIt = m_attributeByCode.find(code);
    if (acronymIt == m_attributeByCode.end()) continue;
    const wxString value = Trimmed(fields[1]);
    const wxString meaning = Trimmed(fields[2]);
    if (!value.IsEmpty() && !meaning.IsEmpty())
      m_decodes[acronymIt->second][value] = meaning;
  }
  return true;
}

wxString S57Catalog::DecodeAttributeValue(const wxString &acronym,
                                          const wxString &rawValue,
                                          bool *decodedAny) const {
  if (decodedAny) *decodedAny = false;
  auto tableIt = m_decodes.find(acronym);
  if (tableIt == m_decodes.end()) return rawValue;

  wxString result;
  wxStringTokenizer values(rawValue, ",", wxTOKEN_STRTOK);
  bool hadValue = false;
  bool decoded = false;
  while (values.HasMoreTokens()) {
    hadValue = true;
    const wxString token = Trimmed(values.GetNextToken());
    wxString text = token;
    auto valueIt = tableIt->second.find(token);
    if (valueIt != tableIt->second.end()) {
      text = valueIt->second;
      decoded = true;
    }
    text = UppercaseFirst(text);
    if (!result.IsEmpty()) result += ", ";
    result += text;
  }
  if (decodedAny) *decodedAny = decoded;
  return hadValue ? result : rawValue;
}
