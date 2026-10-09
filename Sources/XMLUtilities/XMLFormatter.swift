#if SERVER
  import Foundation

  /// XML as syntax, with no knowledge of any vocabulary: read one attribute,
  /// decode the five entities, lay a document out for a person to read.
  ///
  /// ``TEIRenderer`` reads TEI with these; anything else that has to look at
  /// markup can too.
  public enum XMLFormatter {
    /// XML as a person can read it, for display only: the stored text is
    /// never rewritten with it (a model's output stands as it was written).
    ///
    /// An element holding text—alone, or mixed with elements (`<w>AN</w>`,
    /// `<p>text <hi>x</hi> more</p>`)—stays on one line exactly as written,
    /// its white space with it. An element holding only elements (and white
    /// space) sets each child on a line of its own, two spaces deeper. The
    /// white space between such children is replaced by the line break: a
    /// reading collapses it, so the page reads the same. Where there was
    /// none, a break is put in only where it changes neither the reading nor
    /// any anchor's word (`PrettyItem.breakable`)—so `<w>word</w><pc>,</pc>`
    /// stays together: a break there would put a space before the comma.
    /// A word (`<w>`, `<m>`, `<pc>`) is always one line: its surface is what
    /// an anchor names. Comments, processing
    /// instructions, CDATA and entities are kept as written; a fragment cut
    /// out of a document (a page) keeps its stray closing tags and unclosed
    /// elements. `prettified(prettified(x)) == prettified(x)`.
    public static func prettified(_ markup: String) -> String {
      let root = PrettyNode.tree(of: markup)
      // Text at the top level: there is no element-only context to lay out.
      guard !root.holdsText else { return markup }
      var items: [PrettyItem] = []
      var pending = ""
      root.lay(at: -1, in: "root", into: &items, pending: &pending)
      guard !items.isEmpty else { return markup }
      var out = items[0].text
      for index in 1..<items.count {
        let item = items[index]
        if !item.space.isEmpty || PrettyItem.breakable(before: index, in: items) {
          out += "\n" + String(repeating: "  ", count: max(item.indent, 0))
        }
        out += item.text
      }
      return out
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
  /// A line of `XMLFormatter.prettified`'s layout, before it is joined: a
  /// tag or a whole element kept on one line, its depth, the white space
  /// that stood before it, and what stands at each of its edges for a
  /// reading (`TEIRenderer`) and for the projection anchors count words in
  /// (`TEIProjection`).
  struct PrettyItem {
    /// For a reading.
    enum Reading {
      /// A line starts here: a block's tag, a line break.
      case block
      /// Prints nothing: an inline element's tag, a comment.
      case silent
      /// Prints text.
      case text
    }

    /// For the projection: what the character beside the edge is.
    enum Projection {
      /// Not a letter: a line end (after a line-starting block, at a line
      /// break), a gap's mark.
      case separator
      /// Nothing.
      case silent
      /// A word's own (`<w>`, `<m>`): its letters are its word, whatever
      /// stands beside them.
      case word
      /// Text that may be a letter.
      case text
    }

    let text: String
    let indent: Int
    let space: String
    let reading: (left: Reading, right: Reading)
    let projection: (left: Projection, right: Projection)

    /// Whether a break may be put before `index` where the markup had no
    /// white space: only where it changes neither the reading nor any
    /// anchor's word. A reading starts a line on one side (a block, white
    /// space already there or the fragment's edge reached across what prints
    /// nothing), so the space is no space; and the projection has no letter
    /// on one side—or a word's own on both—so no word is split or joined.
    static func breakable(before index: Int, in items: [PrettyItem]) -> Bool {
      // Leftward, the right edges; rightward, the left edges. White space
      // already there, or the edge, counts as a line start and no letter.
      var readingLeft = Reading.block
      var projectionLeft = Projection.separator
      var resolvedReading = false
      var resolvedProjection = false
      var left = index - 1
      while left >= 0, !(resolvedReading && resolvedProjection) {
        let item = items[left]
        if !resolvedReading, item.reading.right != .silent {
          readingLeft = item.reading.right
          resolvedReading = true
        }
        if !resolvedProjection, item.projection.right != .silent {
          projectionLeft = item.projection.right
          resolvedProjection = true
        }
        if !item.space.isEmpty {
          if !resolvedReading { readingLeft = .block }
          if !resolvedProjection { projectionLeft = .separator }
          break
        }
        left -= 1
      }
      var readingRight = Reading.block
      var projectionRight = Projection.separator
      resolvedReading = false
      resolvedProjection = false
      var right = index
      while right < items.count, !(resolvedReading && resolvedProjection) {
        let item = items[right]
        if right > index, !item.space.isEmpty { break }
        if !resolvedReading, item.reading.left != .silent {
          readingRight = item.reading.left
          resolvedReading = true
        }
        if !resolvedProjection, item.projection.left != .silent {
          projectionRight = item.projection.left
          resolvedProjection = true
        }
        right += 1
      }
      let reading = readingLeft == .block || readingRight == .block
      let projection =
        projectionLeft == .separator || projectionRight == .separator
        || (projectionLeft == .word && projectionRight == .word)
      return reading && projection
    }
  }

  /// The markup as a tree for `XMLFormatter.prettified`, every token kept
  /// as written.
  final class PrettyNode {
    enum Kind {
      case element
      case text
      /// CDATA: text as a reader reads it.
      case cdata
      /// A comment, a processing instruction, a declaration.
      case other
    }

    /// Elements a reading starts a new line at (`TEIRenderer`'s blocks and
    /// line breaks), or reads apart (a table's cells, a figure's
    /// description), or does not read at all (the facsimile, the header).
    static let blocks: Set<String> = [
      "p", "lg", "l", "head", "div", "speaker", "stage", "fw", "item", "note", "lb", "cb", "pb", "gap", "table",
      "row", "cell", "figure", "figDesc", "desc", "facsimile", "teiHeader", "standOff", "docTitle", "titlePart",
      "docImprint", "byline", "epigraph", "argument", "imprimatur",
    ]
    /// A title page's parts that are blocks only standing in its structure
    /// (`TEIRenderer.titlePageStructure`), phrases within a byline or an
    /// imprint.
    static let titlePageParts: Set<String> = ["docAuthor", "docDate", "docEdition"]
    /// What the projection ends a line after (`TEIProjection.lineStarts`):
    /// after one closes, the next character is no letter.
    static let lineStarts: Set<String> = ["l", "p", "head", "item", "note", "fw", "cell", "ab"]
    /// What the projection leaves out: nothing in it is a word.
    static let unprojected: Set<String> = [
      "teiHeader", "facsimile", "standOff", "supplied", "reg", "expan", "corr", "ex", "figDesc", "desc",
    ]
    /// Elements the parser takes as empty even without `/>` (`TEIMarkup`).
    static let empty: Set<String> = ["pb", "cb", "lb", "gap", "milestone", "graphic"]
    /// Elements kept whole whatever they hold: a formula reads as its
    /// MathML, white space and all, and a word's surface is everything in
    /// it, white space too, as an anchor names it.
    static let whole: Set<String> = ["formula", "math", "w", "m", "pc"]

    let kind: Kind
    let name: String
    /// The text as written: a text node's, or an element's opening tag
    /// (empty for one whose opening the fragment cut off).
    let raw: String
    /// The closing tag; nil for an empty element or one left open.
    var close: String?
    var children: [PrettyNode] = []
    let selfClosing: Bool

    init(kind: Kind, name: String = "", raw: String, selfClosing: Bool = false) {
      self.kind = kind
      self.name = name
      self.raw = raw
      self.selfClosing = selfClosing
    }

    /// The name without its prefix (`tei:p` is `p`).
    var localName: String { name.split(separator: ":").last.map(String.init) ?? name }

    /// Whether this node holds text of its own, not only white space.
    var holdsText: Bool {
      children.contains {
        ($0.kind == .text && $0.raw.contains { !$0.isWhitespace }) || $0.kind == .cdata
      }
    }

    /// Whether it prints any text, white space included, anywhere in it.
    var printsText: Bool {
      children.contains { child in
        switch child.kind {
        case .text, .cdata: return true
        case .other: return false
        case .element: return child.printsText
        }
      }
    }

    /// Exactly as written.
    var verbatim: String {
      kind == .element ? raw + children.map(\.verbatim).joined() + (close ?? "") : raw
    }

    /// Whether a reading starts a line at it, standing in `parent`.
    func isBlock(in parent: String) -> Bool {
      PrettyNode.blocks.contains(localName)
        || (PrettyNode.titlePageParts.contains(localName) && TEIRenderer.titlePageStructure.contains(parent))
        || (localName == "milestone" && XMLFormatter.attribute("unit", in: raw) == "document")
    }

    /// A line break the projection ends a line at: not one inside a word.
    var breaksLine: Bool {
      ["lb", "pb"].contains(localName) && XMLFormatter.attribute("break", in: raw) != "no"
    }

    /// Kept exactly as written: it holds text, or nothing to lay out, or
    /// says its white space is its own (`xml:space="preserve"`).
    var isWhole: Bool {
      selfClosing || holdsText || PrettyNode.whole.contains(localName)
        || XMLFormatter.attribute("xml:space", in: raw) == "preserve"
        || !children.contains { $0.kind == .element || $0.kind == .other }
    }

    /// This node's lines, children one deeper; `pending` is the white space
    /// read since the last line; `parent` the local name of the element it
    /// stands in ("root" at the top, as `TEIMarkup` names it).
    func lay(
      at depth: Int, in parent: String, firstOfSpeech: Bool = false, into items: inout [PrettyItem],
      pending: inout String
    ) {
      func add(
        _ text: String, _ indent: Int, reading: (PrettyItem.Reading, PrettyItem.Reading),
        projection: (PrettyItem.Projection, PrettyItem.Projection)
      ) {
        items.append(.init(text: text, indent: indent, space: pending, reading: reading, projection: projection))
        pending = ""
      }
      switch kind {
      case .text: pending += raw
      case .cdata: add(raw, depth, reading: (.text, .text), projection: (.text, .text))
      case .other: add(raw, depth, reading: (.silent, .silent), projection: (.silent, .silent))
      case .element:
        let block = isBlock(in: parent)
        let name = localName
        let figure = name == "figure"
        let unprojected = PrettyNode.unprojected.contains(name)
        if isWhole {
          let prints = printsText
          let reading: PrettyItem.Reading = block ? .block : (prints ? .text : .silent)
          let edge: PrettyItem.Projection =
            unprojected || !prints ? .silent : (["w", "m"].contains(name) ? .word : .text)
          let projection: (PrettyItem.Projection, PrettyItem.Projection)
          if breaksLine || name == "gap" || figure {
            projection = (.separator, .separator)
          } else if PrettyNode.lineStarts.contains(name) || firstOfSpeech {
            projection = (edge, .separator)
          } else {
            projection = (edge, edge)
          }
          add(verbatim, depth, reading: (reading, reading), projection: projection)
          return
        }
        let reading: PrettyItem.Reading = block ? .block : .silent
        if !raw.isEmpty {
          let edge: PrettyItem.Projection = figure ? .separator : .silent
          add(raw, depth, reading: (reading, reading), projection: (edge, edge))
        }
        // A speech's first child ends a line too (`TEIProjection`).
        let first = name == "sp" ? children.firstIndex { $0.kind == .element } : nil
        for (index, child) in children.enumerated() {
          child.lay(
            at: depth + 1, in: name.isEmpty ? "root" : name, firstOfSpeech: index == first, into: &items,
            pending: &pending)
        }
        if let close {
          let edge: PrettyItem.Projection =
            figure || firstOfSpeech || PrettyNode.lineStarts.contains(name) ? .separator : .silent
          add(close, depth, reading: (reading, reading), projection: (edge, edge))
        }
      }
    }

    /// The markup's tree, under a root of no name. A closing tag of nothing
    /// open closes an element whose opening the fragment cut off: what came
    /// before it in its parent is its content.
    static func tree(of markup: String) -> PrettyNode {
      let root = PrettyNode(kind: .element, raw: "")
      var stack = [root]
      var cursor = markup.startIndex
      func until(_ end: String, from start: String.Index) -> String.Index {
        markup.range(of: end, range: start..<markup.endIndex)?.upperBound ?? markup.endIndex
      }
      while cursor < markup.endIndex {
        let parent = stack[stack.count - 1]
        guard markup[cursor] == "<" else {
          let end = markup[cursor...].firstIndex(of: "<") ?? markup.endIndex
          parent.children.append(PrettyNode(kind: .text, raw: String(markup[cursor..<end])))
          cursor = end
          continue
        }
        let rest = markup[cursor...]
        if rest.hasPrefix("<!--") || rest.hasPrefix("<?") || rest.hasPrefix("<![CDATA[") {
          let isCDATA = rest.hasPrefix("<![CDATA[")
          let end = until(rest.hasPrefix("<!--") ? "-->" : (isCDATA ? "]]>" : "?>"), from: cursor)
          parent.children.append(PrettyNode(kind: isCDATA ? .cdata : .other, raw: String(markup[cursor..<end])))
          cursor = end
          continue
        }
        // A tag runs to the first `>` outside a quoted value.
        var end = markup.index(after: cursor)
        var quote: Character?
        while end < markup.endIndex {
          let character = markup[end]
          if let open = quote {
            if character == open { quote = nil }
          } else if character == "\"" || character == "'" {
            quote = character
          } else if character == ">" {
            break
          }
          end = markup.index(after: end)
        }
        guard end < markup.endIndex else {
          // An unfinished tag is text, as written.
          parent.children.append(PrettyNode(kind: .text, raw: String(markup[cursor...])))
          break
        }
        end = markup.index(after: end)
        let tag = String(markup[cursor..<end])
        cursor = end
        if tag.hasPrefix("<!") {
          parent.children.append(PrettyNode(kind: .other, raw: tag))
          continue
        }
        let closing = tag.hasPrefix("</")
        let name = String(tag.dropFirst(closing ? 2 : 1).prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" })
        if closing {
          if let index = stack.lastIndex(where: { $0.name == name }), index > 0 {
            stack[index].close = tag
            stack.removeSubrange(index...)
          } else {
            let cut = PrettyNode(kind: .element, name: name, raw: "")
            cut.children = parent.children
            cut.close = tag
            parent.children = [cut]
          }
          continue
        }
        let local = name.split(separator: ":").last.map(String.init) ?? name
        let selfClosing = tag.hasSuffix("/>") || PrettyNode.empty.contains(local)
        let element = PrettyNode(kind: .element, name: name, raw: tag, selfClosing: selfClosing)
        parent.children.append(element)
        if !selfClosing { stack.append(element) }
      }
      return root
    }
  }
#endif
