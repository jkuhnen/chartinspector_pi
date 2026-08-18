#ifndef CHARTINSPECTOR_S57_CATALOG_H
#define CHARTINSPECTOR_S57_CATALOG_H

#include <map>
#include <vector>

#include <wx/string.h>

class S57Catalog {
public:
  struct ObjectClassInfo {
    wxString acronym;
    wxString name;
  };

  bool Load(const wxString &sharedDataDirectory);

  bool IsLoaded() const { return m_loaded; }
  wxString ObjectName(const wxString &acronym) const;
  std::vector<ObjectClassInfo> ObjectClasses() const;
  wxString FormatAttributes(const wxString &rawAttributes,
                            wxString *technical = nullptr) const;
  wxString RawAttributeValue(const wxString &rawAttributes,
                             const wxString &acronym) const;
  wxString DecodeValue(const wxString &acronym,
                       const wxString &rawValue) const;

private:
  struct AttributeDefinition {
    long code = -1;
    wxString name;
    wxString type;
  };

  using DecodeTable = std::map<wxString, wxString>;

  static std::vector<wxString> ParseCsvLine(const wxString &line);
  static wxString Trimmed(wxString value);
  static wxString UppercaseFirst(const wxString &value);
  static wxString FriendlyLabel(const wxString &acronym,
                                const wxString &catalogLabel);
  static wxString FormatDate(const wxString &value);

  bool LoadObjectClasses(const wxString &path);
  bool LoadAttributes(const wxString &path);
  bool LoadAttributeDecodes(const wxString &path);
  bool LoadExpectedInput(const wxString &path);
  wxString DecodeAttributeValue(const wxString &acronym,
                                const wxString &rawValue,
                                bool *decodedAny = nullptr) const;

  std::map<wxString, wxString> m_objectNames;
  std::map<wxString, AttributeDefinition> m_attributes;
  std::map<long, wxString> m_attributeByCode;
  std::map<wxString, DecodeTable> m_decodes;
  bool m_loaded = false;
};

#endif  // CHARTINSPECTOR_S57_CATALOG_H
