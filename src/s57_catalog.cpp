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
  m_decodes.clear();
  m_loaded = false;

  wxFileName s57Dir(sharedDataDirectory, wxEmptyString);
  s57Dir.AppendDir("s57data");
  const wxString base = s57Dir.GetFullPath();

  const bool objectsOk =
      LoadObjectClasses(JoinPath(base, "s57objectclasses.csv"));
  const bool attributesOk =
      LoadAttributes(JoinPath(base, "s57attributes.csv"));
  const bool decodesOk = LoadAttributeDecodes(JoinPath(base, "attdecode.csv"));

  m_loaded = objectsOk && attributesOk && decodesOk;
  return m_loaded;
}

wxString S57Catalog::ObjectName(const wxString &acronym) const {
  auto it = m_objectNames.find(acronym.Upper());
  if (it == m_objectNames.end()) return acronym;
  return it->second;
}

wxString S57Catalog::FormatAttributes(const wxString &rawAttributes) const {
  wxString result;
  wxStringTokenizer lines(rawAttributes, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = Trimmed(lines.GetNextToken());
    if (line.IsEmpty()) continue;

    const int equals = line.Find('=');
    if (equals == wxNOT_FOUND) continue;

    const wxString acronym = Trimmed(line.Left(equals)).Upper();
    const wxString rawValue = Trimmed(line.Mid(equals + 1));

    wxString label = acronym;
    auto attr = m_attributes.find(acronym);
    if (attr != m_attributes.end() && !attr->second.name.IsEmpty()) {
      label = attr->second.name;
    }

    const wxString decoded = DecodeAttributeValue(acronym, rawValue);
    if (!result.IsEmpty()) result += "\n";
    result += label + ": " + decoded;
  }
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
    const wxString name = Trimmed(fields[1]);
    const wxString acronym = Trimmed(fields[2]).Upper();
    const wxString type = Trimmed(fields[3]).Upper();
    if (!acronym.IsEmpty()) m_attributes[acronym] = {name, type};
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

    DecodeTable table;
    for (size_t j = 0; j + 1 < parts.size(); j += 2) {
      const wxString key = Trimmed(parts[j]);
      const wxString value = Trimmed(parts[j + 1]);
      if (!key.IsEmpty() && !value.IsEmpty()) table[key] = value;
    }
    if (!table.empty()) m_decodes[acronym] = table;
  }
  return true;
}

wxString S57Catalog::DecodeAttributeValue(const wxString &acronym,
                                          const wxString &rawValue) const {
  auto tableIt = m_decodes.find(acronym);
  if (tableIt == m_decodes.end()) return rawValue;

  wxString result;
  wxStringTokenizer values(rawValue, ",", wxTOKEN_STRTOK);
  bool hadValue = false;
  while (values.HasMoreTokens()) {
    hadValue = true;
    const wxString token = Trimmed(values.GetNextToken());
    wxString decoded = token;
    auto valueIt = tableIt->second.find(token);
    if (valueIt != tableIt->second.end()) decoded = valueIt->second;
    decoded = UppercaseFirst(decoded);
    if (!result.IsEmpty()) result += ", ";
    result += decoded;
  }

  return hadValue ? result : rawValue;
}
