#if SERVER
import Foundation

/// A bounded subset of standard TEI CSS rendition, describing source layout.
/// No positioning, text coordinates, URLs, arbitrary selectors or fonts.
public enum TEIRendition {
  public static let properties = ["font-size", "line-height", "letter-spacing", "word-spacing", "text-indent", "margin-top", "margin-bottom", "margin-left", "margin-right", "margin-block-start", "margin-block-end", "margin-inline-start", "margin-inline-end", "text-align", "font-weight", "font-style", "font-variant-caps"]

  public static func valid(property: String, value: String) -> Bool {
    if property == "text-align" { return ["left", "right", "center", "justify", "start", "end"].contains(value) }
    if property == "font-weight" { return ["normal", "bold", "400", "600", "700"].contains(value) }
    if property == "font-style" { return ["normal", "italic"].contains(value) }
    if property == "font-variant-caps" { return ["normal", "small-caps"].contains(value) }
    guard properties.contains(property) else { return false }
    let pattern = #"^(-?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+))(em|rem|%|px|pt|mm|cm|in|pc)?$"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
      let range = Range(match.range(at: 1), in: value), let number = Double(value[range]), number.isFinite else { return false }
    let unit = Range(match.range(at: 2), in: value).map { String(value[$0]) } ?? ""
    switch property {
    case "font-size":
      if unit == "%" { return (50...400).contains(number) }
      if unit == "em" || unit == "rem" { return (0.5...4).contains(number) }
      if unit == "px" { return (8...64).contains(number) }
      if unit == "pt" { return (6...48).contains(number) }
      return false
    case "line-height":
      if unit == "" || unit == "em" { return (0.75...3).contains(number) }
      if unit == "%" { return (75...300).contains(number) }
      return false
    default:
      if unit == "" { return number == 0 }
      let bound = unit == "px" || unit == "pt" ? 512.0 : 32.0
      return abs(number) <= bound && (number >= 0 || ["text-indent", "letter-spacing", "word-spacing"].contains(property))
    }
  }

  public static func tokens(_ css: String) -> String {
    css.split(separator: ";").compactMap { declaration -> String? in
      let pair = declaration.split(separator: ":", maxSplits: 1)
      guard pair.count == 2 else { return nil }
      let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard valid(property: name, value: value) else { return nil }
      return "css:\(name)=\(value)"
    }.joined(separator: " ")
  }

  public static func css(from rend: String) -> String {
    rend.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
      guard token.hasPrefix("css:") else { return nil }
      let pair = token.dropFirst(4).split(separator: "=", maxSplits: 1)
      guard pair.count == 2, valid(property: String(pair[0]), value: String(pair[1])) else { return nil }
      return "\(pair[0]):\(pair[1]);"
    }.joined()
  }

  public static func header(_ definitions: [String: String]) -> String {
    guard !definitions.isEmpty else { return "" }
    let entries = definitions.keys.sorted().map { id in
      "<rendition xml:id=\"\(XMLFormatter.escapingAttribute(id))\" scheme=\"css\">\(XMLFormatter.escapingAttribute(css(from: definitions[id] ?? "")))</rendition>"
    }.joined()
    return "<teiHeader><encodingDesc><tagsDecl>" + entries + "</tagsDecl></encodingDesc></teiHeader>"
  }

  static func declarations(in root: TEIMarkup.Element) -> [String: String] {
    var result: [String: String] = [:]
    func visit(_ node: TEIMarkup.Element) {
      if node.name == "rendition", ["", "css"].contains(node.attribute("scheme")), !node.attribute("xml:id").isEmpty {
        result[node.attribute("xml:id")] = tokens(node.textContent)
      }
      for child in node.elements { visit(child) }
    }
    visit(root)
    return result
  }
}
#endif
