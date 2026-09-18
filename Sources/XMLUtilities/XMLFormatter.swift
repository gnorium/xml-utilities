#if SERVER
  import Foundation

  /// XML as syntax, with no knowledge of any vocabulary: read one attribute,
  /// decode the five entities, lay a document out for a person to read.
  ///
  /// ``TEIRenderer`` reads TEI with these; anything else that has to look at
  /// markup can too.
  public enum XMLFormatter {
    /// XML as a person can read it: one element per line, indented by depth.
    ///
    /// A transcript arrives as one long line, which is fine for a parser and
    /// useless to a reader deciding whether the markup is right.
    public static func prettified(_ markup: String) -> String {
      var out: [String] = []
      var depth = 0
      var cursor = markup.startIndex
      while cursor < markup.endIndex {
        guard let open = markup.range(of: "<", range: cursor..<markup.endIndex) else {
          let text = String(markup[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty { out.append(String(repeating: "  ", count: depth) + text) }
          break
        }
        let text = String(markup[cursor..<open.lowerBound])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { out.append(String(repeating: "  ", count: depth) + text) }
        guard let close = markup.range(of: ">", range: open.upperBound..<markup.endIndex) else {
          break
        }
        let tag = String(markup[open.lowerBound..<close.upperBound])
        let isClosing = tag.hasPrefix("</")
        let isSelfClosing = tag.hasSuffix("/>")
        if isClosing { depth = max(depth - 1, 0) }
        out.append(String(repeating: "  ", count: depth) + tag)
        if !isClosing, !isSelfClosing { depth += 1 }
        cursor = close.upperBound
      }
      return out.joined(separator: "\n")
    }

    /// `n="A3 recto"` out of a `<pb …>` tag. Empty when the tag has no such
    /// attribute, which is a meaningful answer: a page break without `facs`
    /// is a different thing from one with it.
    public static func attribute(_ name: String, in tag: String) -> String {
      guard let key = tag.range(of: "\(name)=\"") else { return "" }
      guard let end = tag.range(of: "\"", range: key.upperBound..<tag.endIndex) else { return "" }
      return String(tag[key.upperBound..<end.lowerBound])
    }

    /// The five XML entities. Everything else is left as it stands — a long s
    /// is a long s, not an escape.
    public static func decodingEntities(_ text: String) -> String {
      text
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The body of a document, or the whole of it when there is no `<body>`.
    public static func body(of xml: String) -> String? {
      guard let start = xml.range(of: "<body>")?.upperBound else { return nil }
      let end = xml.range(of: "</body>")?.lowerBound ?? xml.endIndex
      guard start < end else { return nil }
      return String(xml[start..<end])
    }
  }
#endif
