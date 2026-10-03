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

    /// The five XML entities. Everything else is left as it stands—a long s
    /// is a long s, not an escape.
    public static func decodingEntities(_ text: String) -> String {
      text
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Text made safe to stand in an attribute value: the five XML entities,
    /// the ampersand first.
    public static func escapingAttribute(_ text: String) -> String {
      text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Clip immutable markup without losing its structural ancestors. The
    /// selected characters are unchanged; only ancestor tags are repeated and
    /// closed at the boundary, so a page split inside a div remains XML.
    static func balancedSlice(of markup: String, range selected: Range<String.Index>) -> String {
      balancedSlices(of: markup, ranges: [selected])[0]
    }

    /// Ordered, disjoint slices share one tokenization and one ancestor walk,
    /// so indexing a large book does not parse the whole book once per page.
    static func balancedSlices(of markup: String, ranges selected: [Range<String.Index>]) -> [String] {
      let expression = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<(?:"[^"]*"|'[^']*'|[^'">])*>"#)
      let tokens = expression.matches(in: markup, range: NSRange(markup.startIndex..., in: markup))
        .compactMap { Range($0.range, in: markup) }
      var stack: [(name: String, tag: String)] = []
      func read(_ range: Range<String.Index>) {
        let tag = String(markup[range])
        guard !tag.hasPrefix("<!"), !tag.hasPrefix("<?"), !tag.hasSuffix("/>") else { return }
        let closing = tag.hasPrefix("</")
        let name = String(tag.dropFirst(closing ? 2 : 1).prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" })
        if closing {
          if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
        } else { stack.append((name, tag)) }
      }
      var index = 0
      return selected.map { range in
        while index < tokens.count && tokens[index].upperBound <= range.lowerBound {
          read(tokens[index])
          index += 1
        }
        let prefix = stack.map(\.tag).joined()
        while index < tokens.count && tokens[index].lowerBound < range.upperBound {
          read(tokens[index])
          index += 1
        }
        return prefix + markup[range] + stack.reversed().map { "</\($0.name)>" }.joined()
      }
    }

    static func opening(_ name: String, in markup: String) -> String? {
      guard let range = markup.range(of: "<\(name)(?=[\\s>])(?:\"[^\"]*\"|'[^']*'|[^'\">])*>", options: .regularExpression) else { return nil }
      return String(markup[range])
    }

    /// The outer text, including title pages and other front/back matter.
    /// Nested floating texts remain within their containing page.
    public static func text(of xml: String) -> String? {
      guard let opening = xml.range(of: "<text(?=[\\s>])[^>]*>", options: .regularExpression) else { return nil }
      let start = opening.upperBound
      let end = xml.range(of: "</text>", options: .backwards)?.lowerBound ?? xml.endIndex
      guard start < end else { return nil }
      return String(xml[start..<end])
    }
  }
#endif
