#if SERVER
  import Foundation

  /// One facsimile and the reading of it: the image the page was transcribed
  /// from, and the lines that transcription holds.
  public struct TEIPage: Sendable {
    public let label: String
    public let facsimileURL: String
    public let lines: [TEILine]
    /// The page's own markup, for a reader who wants to see the tags.
    public let markup: String
    /// The document's zones (its `<facsimile>`'s, by `xml:id`): where the
    /// page's figures and decorated initials sit, which its markup names by
    /// `facs="#…"` but does not hold.
    public let zones: [String: TEIZone]

    public init(label: String, facsimileURL: String, lines: [TEILine], markup: String, zones: [String: TEIZone] = [:]) {
      self.label = label
      self.facsimileURL = facsimileURL
      self.lines = lines
      self.markup = markup
      self.zones = zones
    }
  }

  /// A line or structured block of a transcription, carrying what the markup said it was. Line
  /// breaks are kept because they are evidence—a diplomatic transcript says
  /// where the compositor broke the line.
  public struct TEILine: Sendable {
    /// `mark` is a page turn inside the image: a source that photographs
    /// openings puts two sides of the book on one facsimile. `forme` is the
    /// work's own apparatus—running head, catchword, signature, printed page
    /// number—which the page carries but the text does not.
    public enum Kind: Sendable {
      case text, heading, speaker, stage, mark
      /// Forme work, by the job it does on the page. A catchword sits at the
      /// foot under the last line and repeats the next page's first word; a
      /// signature is the binder's mark; a running head names the work. They
      /// are on the page, not in the work, and a reading that sets them in the
      /// flow makes the compositor's catchword look like a line of verse.
      case forme(FormeRole)
      /// Nothing was transcribed here, and the reason why: `<gap reason="blank"/>`
      /// for a surface with nothing on it, or a damaged one. It is a statement
      /// about the page, not a word on it.
      case gap(reason: String)
      /// Something drawn rather than set: an illustration, a printer's device,
      /// an ornament. `zone` is where it sits on the surface (the zone its
      /// `facs` names, `TEIZone`), so the region can be cut from the
      /// facsimile; nil where it names none. A decorated initial is not a
      /// figure: it is the first letter of its word (`<hi rend="initial">`,
      /// `Run.zone`).
      ///
      /// A figure is not a line of the text. Its `<figDesc>` describes the
      /// object—"gold-tooled dark leather binding"—and setting that in the
      /// reading says the cover bears those words, which it does not.
      case figure(type: String, zone: TEIZone?)
      /// Rows and cells must survive parsing; their order alone cannot recover
      /// the relationship between a heading and a value after flattening.
      case table(TEITable)
      case documentBoundary
      /// An original note, set apart from the text it annotates, and where
      /// the page puts it: TEI's `<note place="margin|foot|inline">`.
      case note(place: String)
    }

    public enum FormeRole: String, Sendable {
      case header, catchword, signature, pageNumber, other

      /// TEI writes these as `<fw type="…">`, and the abbreviations vary by
      /// transcriber: `catch` and `catchword`, `sig` and `signature`.
      public static func from(_ type: String) -> FormeRole {
        switch type.lowercased() {
        case "header", "head", "running-head", "runninghead": return .header
        case "catch", "catchword": return .catchword
        case "sig", "signature": return .signature
        case "pagenum", "pagenumber", "folio": return .pageNumber
        default: return .other
        }
      }
    }
    public let kind: Kind
    public let text: String
    /// How the type was set, when the transcription says: TEI's `rend`.
    ///
    /// A diplomatic transcription records what is on the surface, and how the
    /// compositor set it is part of that—a centered block on a title page is
    /// how an imprint statement or an epigraph is marked, and a reading that
    /// ranges it left has quietly dropped evidence.
    public let rend: String
    /// The line's runs, each with the setting the transcription gave it.
    ///
    /// `<hi rend="…">` is inline—small caps in an author statement, an
    /// italic speaker prefix—so it cannot be a property of the whole line.
    /// The renderer used to drop `<hi>` and keep its text, which turned
    /// "By WILLIAM SHAKESPEARE" and every italicised speaker into plain prose.
    public let runs: [Run]
    /// Whether the line opens a block—a paragraph, a verse line, a heading,
    /// anything set apart—rather than following an `<lb/>` inside one. A
    /// line break and a paragraph break are different evidence, and a diff
    /// that turned one into the other has changed the page.
    public let opensBlock: Bool
    /// Whether it follows the line before with no line break between them:
    /// furniture set on one line (a page number, then a running head).
    public let sharesLine: Bool
    /// Whether the line break before it falls inside a word
    /// (`<lb break="no"/>`), so that read as running text it joins the line
    /// before with no space.
    public let joinsPrevious: Bool
    /// The element it is, where a page read word by word (`marksWords`)
    /// opens it as a whole: a gap, a figure, a side mark—its place among
    /// the page's elements in document order (`TEIRenderer.encoding(of:element:)`).
    /// Nil for every other line.
    public let element: Int?

    /// A stretch of one line set one way.
    public struct Run: Sendable {
      public enum Kind: Sendable {
        case text
        /// A formula, as the page keeps it: Presentation MathML. The run's
        /// text is the symbols it prints, run together.
        case math(TEIMath)
      }

      public let text: String
      public let rend: String
      public let kind: Kind
      /// What the transcription gives beside the reading, never in its
      /// place: a `<choice>`'s regularized spelling, expansion or
      /// correction ("the" for "yͤ"). Empty when there is none.
      public let alternative: String
      /// The highlight it falls in, when the reading has one: a quotation's
      /// sentence, or its word (`TEIRenderer.quotation`).
      public let highlight: TEIHighlight.Kind?
      /// Where a decorated initial sits on the surface (the zone its `<hi
      /// rend="initial" facs="#…">` names), so its decoration can be cut from
      /// the facsimile as a figure's is. Nil for every other run, and for an
      /// initial that names no zone.
      public let zone: TEIZone?
      /// The word it is of, where the page is read word by word
      /// (`marksWords`): its place as an anchor counts it. Nil for what
      /// stands between words, and for every run of a page read whole.
      public let word: TEIWordPlace?
      /// The innermost element it is set in that is not a block, where it is
      /// of no word and the page is read word by word (`marksWords`): a
      /// number, a date, a running head's page number, opened as a whole
      /// (`TEIRenderer.encoding(of:element:)`). Nil for a word's runs.
      public let element: Int?
      /// Whether its white space is the source's own, kept exactly: inside
      /// `xml:space="preserve"`, or a `<space/>`'s width. Drawn as written
      /// (`white-space: pre-wrap`), never collapsed.
      public let preserved: Bool

      public init(
        text: String, rend: String = "", kind: Kind = .text, alternative: String = "",
        highlight: TEIHighlight.Kind? = nil, word: TEIWordPlace? = nil, zone: TEIZone? = nil, element: Int? = nil,
        preserved: Bool = false
      ) {
        self.preserved = preserved
        self.element = element
        self.text = text
        self.rend = rend
        self.kind = kind
        self.alternative = alternative
        self.highlight = highlight
        self.word = word
        self.zone = zone
      }
    }

    public init(
      kind: Kind, text: String, rend: String = "", runs: [Run] = [], opensBlock: Bool = true,
      sharesLine: Bool = false, joinsPrevious: Bool = false, element: Int? = nil
    ) {
      self.element = element
      self.kind = kind
      self.text = text
      self.rend = rend
      self.runs = runs.isEmpty ? [Run(text: text)] : runs
      self.opensBlock = opensBlock
      self.sharesLine = sharesLine
      self.joinsPrevious = joinsPrevious
    }
  }

  /// A formula as the page keeps it (gnorium-python recognition
  /// `formulas.py`): Presentation MathML, drawn as MathML Core, each symbol it
  /// prints a word of the page (`TEIProjection.symbols`), and the TeX it was
  /// written in beside it, never drawn.
  public struct TEIMath: Sendable {
    public enum Node: Sendable {
      /// A MathML element, its presentation attributes as written
      /// (`TEIMath.attributes`), and its children. An element outside
      /// MathML Core is read as an `mrow`.
      case element(name: String, attributes: [(name: String, value: String)], children: [Node])
      /// A token element (`mi`, `mn`, `mo`, `ms`, `mtext`), its text as runs,
      /// each with the word it is of and the highlight it falls in.
      case token(name: String, attributes: [(name: String, value: String)], runs: [TEILine.Run])
      /// A mark that could not be read: TEI's `<gap>` (its reason) in
      /// MathML's `<semantics>` (gnorium-python recognition `formulas.py`).
      /// Nothing was read there; no word.
      case gap(reason: String)

      /// Its tokens' runs, in reading order.
      public var runs: [TEILine.Run] {
        switch self {
        case .element(_, _, let children): return children.flatMap(\.runs)
        case .token(_, _, let runs): return runs
        case .gap: return []
        }
      }

      /// As MathML markup, its tokens' text escaped (`TEIMath.markup`).
      var markup: String {
        func opening(_ name: String, _ attributes: [(name: String, value: String)]) -> String {
          name + attributes.map { " \($0.name)=\"\(XMLFormatter.escapingAttribute($0.value))\"" }.joined()
        }
        switch self {
        case .element(let name, let attributes, let children):
          let inner = children.map(\.markup).joined()
          return inner.isEmpty ? "<\(opening(name, attributes))/>" : "<\(opening(name, attributes))>\(inner)</\(name)>"
        case .token(let name, let attributes, let runs):
          let text = runs.map(\.text).joined()
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
          return "<\(opening(name, attributes))>\(text)</\(name)>"
        case .gap(let reason):
          return #"<semantics><mrow/><annotation-xml encoding="application/tei+xml">"#
            + #"<gap xmlns="http://www.tei-c.org/ns/1.0" reason=""# + XMLFormatter.escapingAttribute(reason)
            + #""/></annotation-xml></semantics>"#
        }
      }
    }

    /// The formula as MathML, drawn content only (no annotation): what a
    /// diff compares it by and draws it from (`TEIRenderer.math(markup:)`
    /// reads it back). Two formulas that draw alike compare alike, however
    /// their TeX was written.
    public var markup: String {
      #"<math xmlns="http://www.w3.org/1998/Math/MathML" display=""# + (display ? "block" : "inline") + #"">"#
        + content.map(\.markup).joined() + "</math>"
    }

    public init(display: Bool, content: [Node], source: String = "") {
      self.display = display
      self.content = content
      self.source = source
    }

    /// Its tokens' runs, in reading order: the words it prints.
    public var runs: [TEILine.Run] { content.flatMap(\.runs) }

    /// Set on its own line (`display="block"`), not in the text's line.
    public let display: Bool
    /// What the `<math>` draws: its `<semantics>`' first child, never its
    /// annotations.
    public let content: [Node]
    /// The TeX it was written in (its `application/x-tex` annotation); ""
    /// where it has none.
    public let source: String

    /// MathML Core's elements; any other is read as an `mrow`.
    static let elements: Set<String> = [
      "mrow", "mi", "mn", "mo", "ms", "mtext", "mspace", "mfrac", "msqrt", "mroot", "mstyle", "merror",
      "mpadded", "mphantom", "msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts",
      "mprescripts", "none", "mtable", "mtr", "mtd",
    ]
    static let tokens: Set<String> = ["mi", "mn", "mo", "ms", "mtext"]
    /// The presentation attributes MathML Core reads; no other is kept.
    static let attributes: Set<String> = [
      "dir", "displaystyle", "scriptlevel", "mathvariant", "stretchy", "symmetric", "largeop", "movablelimits",
      "fence", "separator", "form", "lspace", "rspace", "minsize", "maxsize", "accent", "accentunder",
      "linethickness", "width", "height", "depth", "voffset", "columnspan", "rowspan",
    ]
  }

  public struct TEITable: Sendable {
    public struct Cell: Sendable {
      public let lines: [TEILine]
      public let isLabel: Bool
      public let rows: Int
      public let columns: Int
    }

    public struct Row: Sendable {
      public let cells: [Cell]
    }

    public let caption: [TEILine]
    public let rows: [Row]
  }

  /// Reads a TEI document as a document—pages, and the lines on them—rather
  /// than as a tree.
  ///
  /// The counterpart of `MarkdownRenderer`: where that one turns a source
  /// format into HTML, this one turns it into the pages a view draws, because
  /// a facsimile edition is read one opening at a time and no HTML fragment
  /// can carry that structure.
  public enum TEIRenderer {
    /// Split the body at the page breaks that carry a facsimile.
    ///
    /// A document holds two kinds of `<pb>`: one per image, labeled for the
    /// opening ("F1 verso – F2 recto") and carrying `facs`, and one per side of
    /// the leaf, carrying only a label. Counting both made a 64-image quarto
    /// read as 162 pages. A page here is an image; the side marks are lines
    /// within it, where they belong.
    /// With `marksWords`, each run says which word it is of (`Run.word`).
    public static func pages(
      in xml: String, highlights: [String: [TEIHighlight]] = [:], marksWords: Bool = false
    ) -> [TEIPage] {
      let zones = TEIFacsimile.zones(in: TEIFacsimile.blocks(in: xml))
      return pageSpans(in: xml).map { open, range in
        let markup = String(xml[range])
        return TEIPage(
          label: open.label,
          facsimileURL: open.facsimileURL,
          lines: lines(
            in: markup, highlights: highlights[serviceID(ofFacsimile: open.facsimileURL)] ?? [],
            marksWords: marksWords, zones: zones),
          markup: markup.trimmingCharacters(in: .whitespacesAndNewlines),
          zones: zones
        )
      }
    }

    /// Where each page's own content stands in the whole document, in the
    /// order `pages` gives them: from the end of its facsimile page break to
    /// the next one, within the outer `<text>`. The document's own closing
    /// structure after the last page break (`</front>`, `<body>`, `</body>`)
    /// belongs to no page (user, 2026-10-09): on a work laid in blank past
    /// its reading, the last resemblance would otherwise read as explicated. Each
    /// page's `markup` is its range's text, trimmed. The one definition a
    /// page is read, laid or spliced by: never a search for its text, which
    /// an empty page is not found by, and which finds identical markup on
    /// another page first (prod, 2026-10-10).
    public static func pageRanges(in xml: String) -> [Range<String.Index>] {
      pageSpans(in: xml).map(\.range)
    }

    private static func pageSpans(
      in xml: String
    ) -> [(open: (tag: Range<String.Index>, label: String, facsimileURL: String), range: Range<String.Index>)] {
      guard let text = XMLFormatter.textRange(of: xml) else { return [] }
      let breaks = pageBreaks(in: xml[text])
      return breaks.indices.map { index in
        let start = breaks[index].tag.upperBound
        guard index + 1 == breaks.count else { return (breaks[index], start..<breaks[index + 1].tag.lowerBound) }
        let kept = withoutTrailingStructure(String(xml[start..<text.upperBound]))
        return (breaks[index], start..<xml.utf8.index(start, offsetBy: kept.utf8.count))
      }
    }

    /// `xml` with page `index` (as `pageRanges` places it) holding `markup`
    /// in place of its own: its content between the white space at its
    /// edges replaced, or, on a page with none, set on the line after its
    /// page break. Nil when there is no such page.
    public static func replacingPage(_ index: Int, with markup: String, in xml: String) -> String? {
      let ranges = pageRanges(in: xml)
      guard ranges.indices.contains(index) else { return nil }
      let range = ranges[index]
      var out = xml
      if let first = xml[range].firstIndex(where: { !$0.isWhitespace }),
        let last = xml[range].lastIndex(where: { !$0.isWhitespace })
      {
        out.replaceSubrange(first...last, with: markup)
      } else {
        let at = xml[range].firstIndex(where: \.isNewline).map { xml.index(after: $0) } ?? range.lowerBound
        out.insert(contentsOf: markup, at: at)
      }
      return out
    }

    /// Each resemblance as a complete XML document, preserving front/body/back
    /// matter and containers crossing the page boundary. The leading page
    /// break is omitted, as the quotations service's page anchors require.
    public static func pageDocuments(in xml: String) -> [(facsimileURL: String, xml: String)] {
      guard let text = XMLFormatter.text(of: xml) else { return [] }
      let breaks = pageBreaks(in: text)
      let root = XMLFormatter.opening("TEI", in: xml) ?? #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"#
      let opening = XMLFormatter.opening("text", in: xml) ?? "<text>"
      let ranges = breaks.enumerated().map { index, page in
        page.tag.upperBound..<(index + 1 < breaks.count ? breaks[index + 1].tag.lowerBound : text.endIndex)
      }
      let fragments = XMLFormatter.balancedSlices(of: text, ranges: ranges)
      let facsimile = TEIFacsimile.blocks(in: xml)
      return zip(breaks, fragments).map { page, fragment in
        (page.facsimileURL, root + facsimile + opening + fragment + "</text></TEI>")
      }
    }

    /// The document's containers, whose bare open and close tags after a
    /// page's last content are the document's structure, not the page's.
    static let documentContainers: Set<String> = ["TEI", "text", "front", "body", "back", "group"]

    /// `markup` without the run of bare document-container tags (`</front>`,
    /// `<body>`, `</body>`, `</text>`) at its end, and the white space
    /// between them; empty when it held nothing else.
    public static func withoutTrailingStructure(_ markup: String) -> String {
      var text = Substring(markup)
      while true {
        let trimmed = text.drop(while: { _ in false })
        var end = trimmed.endIndex
        while end > trimmed.startIndex, trimmed[trimmed.index(before: end)].isWhitespace { end = trimmed.index(before: end) }
        guard end > trimmed.startIndex, trimmed[trimmed.index(before: end)] == ">",
          let open = trimmed[..<end].lastIndex(of: "<")
        else { return String(text) }
        let tag = trimmed[open..<end]
        guard !tag.hasSuffix("/>"), !tag.hasPrefix("<!"), !tag.hasPrefix("<?") else { return String(text) }
        let name = tag.dropFirst(tag.hasPrefix("</") ? 2 : 1).prefix { !$0.isWhitespace && $0 != ">" }
        guard documentContainers.contains(String(name)) else { return String(text) }
        text = trimmed[..<open]
      }
    }

    /// Whether a page's markup holds anything of its own: text outside its
    /// tags, or an element beyond bare container open and close tags (a
    /// `<gap/>`, a `<figure>`'s graphic)—never a page, line or column break
    /// alone, nor the containers a page laid in blank is wrapped in (user,
    /// 2026-10-09). A page with none is unexplicated.
    public static func hasMarkup(_ markup: String) -> Bool {
      var cursor = markup.startIndex
      while cursor < markup.endIndex {
        guard let open = markup[cursor...].firstIndex(of: "<") else {
          return markup[cursor...].contains { !$0.isWhitespace }
        }
        if markup[cursor..<open].contains(where: { !$0.isWhitespace }) { return true }
        guard let close = markup[open...].firstIndex(of: ">") else { return false }
        let tag = markup[open...close]
        if tag.hasSuffix("/>") {
          let name = tag.dropFirst().prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
          if !["pb", "lb", "cb", "milestone", "anchor"].contains(String(name)) { return true }
        }
        cursor = markup.index(after: close)
      }
      return false
    }

    /// The page breaks of a body that carry a facsimile, each with where its
    /// tag stands, its label and its image. A side mark (a `<pb>` with no
    /// `facs`) is left in its page, where `lines(in:)` turns it into a line.
    static func pageBreaks(in body: String) -> [(tag: Range<String.Index>, label: String, facsimileURL: String)] {
      pageBreaks(in: body[...])
    }

    /// The same, for a stretch of a larger string, its ranges in that string.
    static func pageBreaks(in body: Substring) -> [(tag: Range<String.Index>, label: String, facsimileURL: String)] {
      var breaks: [(tag: Range<String.Index>, label: String, facsimileURL: String)] = []
      var cursor = body.startIndex
      while let open = body.range(of: "<pb", range: cursor..<body.endIndex) {
        guard let close = body.range(of: ">", range: open.upperBound..<body.endIndex) else { break }
        let tag = String(body[open.lowerBound..<close.upperBound])
        let facs = XMLFormatter.attribute("facs", in: tag)
        cursor = close.upperBound
        guard !facs.isEmpty else { continue }
        breaks.append((open.lowerBound..<close.upperBound, expandedLeafLabel(XMLFormatter.attribute("n", in: tag)), facs))
      }
      return breaks
    }

    /// One page's markup as the lines a reader sees; with `highlights`
    /// (counted in the page's projection, `TEIProjection`), each run says
    /// which it falls in; with `marksWords`, which word it is of, as an
    /// anchor counts the page's words (`words(of:)`). `zones` are the
    /// document's (`TEIPage.zones`); nil reads the markup's own facsimile.
    /// Returns no lines for invalid or excessive `<space>` quantities:
    /// at most 4,096 characters or 128 lines per element, and 65,536
    /// characters or 1,024 lines over the reading. Source markup is unchanged.
    public static func lines(
      in markup: String, highlights: [TEIHighlight] = [], marksWords: Bool = false, zones: [String: TEIZone]? = nil
    ) -> [TEILine] {
      let zones = zones ?? TEIFacsimile.zones(in: TEIFacsimile.blocks(in: markup))
      let root = TEIMarkup.document(!highlights.isEmpty || marksWords ? TEIProjection.normalized(markup) : markup)
      // Check all expansions together before constructing any rendered
      // spaces or lines, including expansions in nested tables and figures.
      guard spacesAreBounded(in: root) else { return [] }
      guard !highlights.isEmpty || marksWords else {
        return rendering(from: root, zones: zones)
      }
      let projection = TEIProjection(root)
      return rendering(
        from: root, highlights: highlights, words: marksWords ? Words(projection.units, root: root) : nil,
        zones: zones)
    }

    /// Expansion limits apply to the complete reading, not separately to
    /// table cells. Oversized or invalid quantities reject the reading;
    /// the source markup remains available unchanged on its page.
    private static func spacesAreBounded(in root: TEIMarkup.Element) -> Bool {
      var charactersLeft = 65_536
      var linesLeft = 1_024
      func visit(_ element: TEIMarkup.Element) -> Bool {
        if element.name == "space" {
          let source = element.attribute("quantity")
          guard let quantity = source.isEmpty ? 1 : Int(source), quantity > 0 else { return false }
          let unit = element.attribute("unit")
          if unit == "lines" || element.attribute("dim") == "vertical" {
            guard quantity <= 128 else { return false }
            let count = unit == "lines" ? quantity : 1
            guard count <= linesLeft else { return false }
            linesLeft -= count
          } else {
            guard quantity <= 4_096, quantity <= charactersLeft else { return false }
            charactersLeft -= quantity
          }
        }
        return element.elements.allSatisfy(visit)
      }
      return visit(root)
    }

    /// A page's words by where they are in its projection: which word a
    /// point of the text is of.
    struct Words {
      let places: [TEIWordPlace]
      /// Each word's parts, by the word's index in `places`.
      let ranges: [[Range<Int>]]
      /// Each element of the page by its place in document order
      /// (`TEIRenderer.elements(of:)`): what a line or a run that is no word
      /// is opened by.
      let elements: [ObjectIdentifier: Int]

      init(_ units: [TEIProjection.Unit], root: TEIMarkup.Element) {
        places = units.map { .init(line: $0.line, word: $0.number) }
        ranges = units.map(\.ranges)
        var elements: [ObjectIdentifier: Int] = [:]
        for (index, element) in TEIRenderer.elements(of: root).enumerated() {
          elements[ObjectIdentifier(element.element)] = index
        }
        self.elements = elements
      }

      /// An element's place in document order.
      func index(of element: TEIMarkup.Element) -> Int? { elements[ObjectIdentifier(element)] }

      /// The word a counted point is of.
      func at(_ offset: Int) -> TEIWordPlace? {
        guard let index = ranges.firstIndex(where: { $0.contains { $0.contains(offset) } }) else { return nil }
        return places[index]
      }

      /// The word a text the projection leaves out stands inside (what an
      /// editor supplies in a word), not one it only borders.
      func inside(_ offset: Int) -> TEIWordPlace? {
        guard
          let index = ranges.firstIndex(where: { parts in
            parts.contains { $0.lowerBound < offset && offset < $0.upperBound }
          })
        else { return nil }
        return places[index]
      }
    }

    /// The highlight a point of the projection falls in, the word's before
    /// the sentence's.
    private static func highlight(at offset: Int, in highlights: [TEIHighlight]) -> TEIHighlight.Kind? {
      let holding = highlights.filter { $0.range.contains(offset) }
      return holding.contains { $0.kind == .title } ? .title : holding.first?.kind
    }

    /// A text node cut where a highlight or a word begins or ends. A text
    /// the projection leaves out (what an editor supplies) takes the
    /// highlight and the word it stands inside, not one it only borders.
    private static func pieces(
      of text: String, at position: TEIProjection.Position?, in highlights: [TEIHighlight], words: Words? = nil
    ) -> [(text: String, highlight: TEIHighlight.Kind?, word: TEIWordPlace?)] {
      guard let position, !highlights.isEmpty || words != nil else { return [(text, nil, nil)] }
      guard position.counted else {
        let inside = highlights.filter {
          $0.range.lowerBound < position.start && position.start < $0.range.upperBound
        }
        return [
          (
            text, inside.contains { $0.kind == .title } ? .title : inside.first?.kind,
            words?.inside(position.start)
          )
        ]
      }
      var pieces: [(text: String, highlight: TEIHighlight.Kind?, word: TEIWordPlace?)] = []
      var current = String.UnicodeScalarView()
      var currentKind: TEIHighlight.Kind?
      var currentWord: TEIWordPlace?
      for (offset, scalar) in text.unicodeScalars.enumerated() {
        let kind = highlight(at: position.start + offset, in: highlights)
        let word = words?.at(position.start + offset)
        if kind != currentKind || word != currentWord, !current.isEmpty {
          pieces.append((String(current), currentKind, currentWord))
          current = String.UnicodeScalarView()
        }
        currentKind = kind
        currentWord = word
        current.append(scalar)
      }
      if !current.isEmpty { pieces.append((String(current), currentKind, currentWord)) }
      return pieces
    }

    private static func rendering(
      from owner: TEIMarkup.Element, highlights: [TEIHighlight] = [], words: Words? = nil,
      zones: [String: TEIZone] = [:], inheritedPreservation: Bool = false
    ) -> [TEILine] {
      /// The zone an element names by `facs="#…"`.
      func zone(of element: TEIMarkup.Element) -> TEIZone? {
        let facs = element.attribute("facs")
        guard facs.hasPrefix("#") else { return nil }
        return zones[String(facs.dropFirst())]
      }
      // The elements whose white space is kept as written: inside an
      // `xml:space="preserve"`, until an `xml:space="default"` says otherwise.
      var preserving: Set<ObjectIdentifier> = []
      func mark(_ element: TEIMarkup.Element, _ inherited: Bool) {
        let declared = element.attribute("xml:space")
        let preserve = declared == "preserve" ? true : (declared == "default" ? false : inherited)
        if preserve { preserving.insert(ObjectIdentifier(element)) }
        for child in element.elements { mark(child, preserve) }
      }
      mark(owner, inheritedPreservation)
      var lines: [TEILine] = []
      var runs: [TEILine.Run] = []
      var currentKind: TEILine.Kind = .text
      var currentRend = ""
      // Whether the next line opens a block: true until a line is set, and
      // again at every block's edge; an `<lb/>` leaves it false.
      var blockPending = true
      // Whether a line break (`<lb/>`, `<cb/>`, `<pb/>`) came since the last
      // line was set, and whether it fell inside a word.
      var lineBroken = true
      var breakInWord = false

      func flush() {
        runs = TEIRenderer.spaced(runs)
        let text = runs.map(\.text).joined()
        if !text.isEmpty {
          lines.append(
            TEILine(
              kind: currentKind, text: text, rend: currentRend, runs: runs, opensBlock: blockPending,
              sharesLine: !lineBroken, joinsPrevious: breakInWord))
          blockPending = false
          lineBroken = false
          breakInWord = false
        }
        runs = []
      }

      func append(_ line: TEILine) {
        lines.append(line)
        blockPending = true
        lineBroken = true
        breakInWord = false
      }

      func walk(
        _ owner: TEIMarkup.Element, kind: TEILine.Kind = .text,
        rend: String = "", inlineRend: String = "", alternative: String = "", zone initialZone: TEIZone? = nil,
        gloss: Int? = nil, including: (TEIMarkup.Node) -> Bool = { _ in true }
      ) {
        /// What a run of no word inside `element` is opened by: the element,
        /// unless it is a block, whose runs keep the one around it.
        func glossing(_ element: TEIMarkup.Element) -> Int? {
          TEIRenderer.blocks.contains(element.name) ? gloss : words?.index(of: element) ?? gloss
        }
        /// A run's element: none for a word's runs.
        func runElement(of word: TEIWordPlace?) -> Int? { word == nil ? gloss : nil }
        func joined(_ extra: String) -> String {
          [inlineRend, extra].filter { !$0.isEmpty }.joined(separator: " ")
        }
        for (index, node) in owner.children.enumerated() where including(node) {
          switch node {
          case .text(let text):
            currentKind = kind
            currentRend = rend
            let preserved = preserving.contains(ObjectIdentifier(owner))
            if !text.isEmpty {
              if alternative.isEmpty {
                for piece in pieces(of: text, at: owner.projected[index], in: highlights, words: words) {
                  runs.append(
                    .init(
                      text: piece.text, rend: inlineRend, highlight: piece.highlight, word: piece.word,
                      zone: initialZone, element: runElement(of: piece.word), preserved: preserved))
                }
              } else {
                // A run with an alternative stays whole: it is read on hover
                // as one.
                let first = pieces(of: text, at: owner.projected[index], in: highlights, words: words).first
                runs.append(
                  .init(
                    text: text, rend: inlineRend, alternative: alternative, highlight: first?.highlight,
                    word: first?.word, zone: initialZone, element: runElement(of: first?.word), preserved: preserved))
              }
            }
          case .element(let element):
            let ownRend = element.attribute("rend")
            let blockRend = ownRend.isEmpty ? rend : ownRend
            switch element.name {
            case "formula" where element.elements.contains(where: { $0.name == "math" }):
              currentKind = kind
              currentRend = rend
              let formula = math(element, highlights: highlights, words: words)
              runs.append(.init(text: formula.text, rend: inlineRend, kind: .math(formula.math)))
            case "hi":
              // Passing the inherited setting down the tree restores it when
              // a nested span closes, including across physical line breaks.
              // A decorated initial is the first letter of its word, and its
              // zone, where it names one, rides on the letter's run.
              let initial = ownRend.split(whereSeparator: \.isWhitespace).contains("initial")
              walk(
                element, kind: kind, rend: rend, inlineRend: joined(ownRend),
                alternative: alternative, zone: initial ? zone(of: element) : initialZone, gloss: glossing(element))
            case "facsimile":
              // Where the page's figures sit, not what it reads.
              continue
            case "choice":
              // The surface reading (orig, sic, abbr) is the reading; the
              // regularized, corrected or expanded form rides beside it.
              let children = element.elements
              let surface =
                ["orig", "sic", "abbr"].lazy.compactMap { name in children.first { $0.name == name } }.first
                ?? children.first
              let beside = children.first { ["reg", "corr", "expan"].contains($0.name) }
              if let surface {
                walk(
                  surface, kind: kind, rend: rend, inlineRend: inlineRend,
                  alternative: beside.map { $0.textContent } ?? alternative, gloss: glossing(surface))
              }
            case "supplied":
              // Not on the surface: set apart in square brackets, as an
              // edition sets what it supplies.
              currentKind = kind
              currentRend = rend
              let bracket = pieces(
                of: "[", at: element.projectedStart.map { .init(start: $0, counted: false) }, in: highlights,
                words: words
              ).first
              let supplied = words?.index(of: element) ?? gloss
              runs.append(
                .init(
                  text: "[", rend: joined("supplied"), highlight: bracket?.highlight, word: bracket?.word,
                  element: bracket?.word == nil ? supplied : nil))
              walk(element, kind: kind, rend: rend, inlineRend: joined("supplied"), gloss: supplied)
              runs.append(
                .init(
                  text: "]", rend: joined("supplied"), highlight: bracket?.highlight, word: bracket?.word,
                  element: bracket?.word == nil ? supplied : nil))
            case "del", "add":
              // The makers' own deletions and additions, read in place.
              walk(
                element, kind: kind, rend: rend, inlineRend: joined(element.name),
                alternative: alternative, gloss: glossing(element))
            case "note":
              flush()
              blockPending = true
              walk(
                element, kind: .note(place: element.attribute("place")), rend: blockRend,
                inlineRend: inlineRend, gloss: glossing(element))
              flush()
              blockPending = true
            case "space":
              // Space the source leaves, as much as it says: so many
              // characters' width in the line, or so many blank lines.
              // Never collapsed.
              let quantity = max(1, Int(element.attribute("quantity")) ?? 1)
              let unit = element.attribute("unit")
              if unit == "lines" || element.attribute("dim") == "vertical" {
                flush()
                for _ in 0..<(unit == "lines" ? quantity : 1) {
                  append(.init(kind: kind, text: " ", runs: [.init(text: " ", preserved: true)]))
                }
              } else {
                currentKind = kind
                currentRend = rend
                runs.append(
                  .init(
                    text: String(repeating: " ", count: quantity), rend: joined("space"),
                    element: words?.index(of: element) ?? gloss, preserved: true))
              }
            case "lb", "cb":
              flush()
              lineBroken = true
              breakInWord = element.name == "lb" && element.attribute("break") == "no"
            case "pb":
              flush()
              lineBroken = true
              let label = expandedLeafLabel(element.attribute("n"))
              if !label.isEmpty { append(.init(kind: .mark, text: label, element: words?.index(of: element))) }
            case "gap":
              flush()
              let reason = element.attribute("reason")
              append(
                .init(
                  kind: .gap(reason: reason), text: reason.isEmpty ? "gap" : reason, element: words?.index(of: element)))
            case "milestone" where element.attribute("unit") == "document":
              flush()
              append(.init(kind: .documentBoundary, text: ""))
            case let name where ["docAuthor", "docDate", "docEdition"].contains(name)
              && !TEIRenderer.titlePageStructure.contains(owner.name):
              // Within a byline, an imprint or a title, a phrase of it.
              walk(
                element, kind: kind, rend: rend, inlineRend: inlineRend, alternative: alternative,
                zone: initialZone, gloss: glossing(element))
            case "p", "lg", "l", "head", "div", "speaker", "stage", "fw", "item", "docTitle", "titlePart",
              "docImprint", "byline", "docAuthor", "docDate", "docEdition", "epigraph", "argument", "imprimatur":
              flush()
              blockPending = true
              // A block begins a line of its own; only furniture set beside
              // furniture (a page number, then a running head) shares one.
              if element.name != "fw" { lineBroken = true }
              let blockKind: TEILine.Kind
              switch element.name {
              case "head": blockKind = .heading
              case "speaker": blockKind = .speaker
              case "stage": blockKind = .stage
              case "fw": blockKind = .forme(.from(element.attribute("type")))
              default: blockKind = kind
              }
              walk(element, kind: blockKind, rend: blockRend, inlineRend: inlineRend, gloss: glossing(element))
              flush()
              blockPending = true
              if element.name != "fw" { lineBroken = true }
            case "table":
              flush()
              let children = element.elements
              let caption = children.filter { $0.name == "head" }.flatMap {
                rendering(
                  from: $0, highlights: highlights, words: words, zones: zones,
                  inheritedPreservation: preserving.contains(ObjectIdentifier($0)))
              }
              let rows = children.filter { $0.name == "row" }.map { row in
                TEITable.Row(
                  cells: row.elements.filter { $0.name == "cell" }.map { cell in
                    TEITable.Cell(
                      lines: rendering(
                        from: cell, highlights: highlights, words: words, zones: zones,
                        inheritedPreservation: preserving.contains(ObjectIdentifier(cell))),
                      isLabel: row.attribute("role") == "label"
                        || cell.attribute("role") == "label",
                      rows: max(1, Int(cell.attribute("rows")) ?? 1),
                      columns: max(1, Int(cell.attribute("cols")) ?? 1)
                    )
                  })
              }
              let table = TEITable(caption: caption, rows: rows)
              let text = (caption + rows.flatMap { $0.cells.flatMap(\.lines) }).map(\.text).joined(
                separator: " ")
              append(.init(kind: .table(table), text: text, rend: blockRend))
            case "figure":
              flush()
              let descriptions = element.elements.filter {
                $0.name == "figDesc" || $0.name == "desc"
              }
              let description = descriptions.flatMap {
                rendering(from: $0, inheritedPreservation: preserving.contains(ObjectIdentifier($0)))
              }.map(\.text)
                .joined(separator: " ")
              append(
                .init(
                  kind: .figure(type: element.attribute("type"), zone: zone(of: element)),
                  text: description, element: words?.index(of: element)))
              // Captions, tables, and diagram labels remain readable even when
              // the graphic has no usable crop. figDesc is descriptive metadata.
              // Its caption's text that is no word opens the figure's gloss.
              walk(element, kind: kind, rend: rend, inlineRend: inlineRend, gloss: words?.index(of: element) ?? gloss) {
                node in
                if case .element(let child) = node {
                  return child.name != "figDesc" && child.name != "desc"
                }
                return true
              }
              flush()
              blockPending = true
            default:
              // Words, punctuation, sentences, glyphs, names, dates, numbers,
              // quotations and references add nothing to the reading but
              // their text. How an element around a block's text is set
              // (a title page's, a closer's: align, indent, hanging) is
              // its lines' setting; its inline rendition is none of it.
              let setting = TEIRenderer.blockSetting(of: ownRend)
              walk(
                element, kind: kind, rend: setting.isEmpty ? rend : setting, inlineRend: inlineRend,
                alternative: alternative, zone: initialZone, gloss: glossing(element))
            }
          }
        }
      }
      walk(owner)
      flush()
      return lines
    }

    /// A line's runs as XML text is displayed (HTML's `white-space:
    /// normal`, as TEI prose is read): each stretch of white space—space,
    /// tab, line feed, carriage return—one space, across the runs' edges
    /// too, and none at the line's start or end. A run that is white space
    /// alone after white space is gone. So markup laid out over lines and
    /// indented reads as the same markup on one line; a no-break space is
    /// no white space here, as it is none in HTML. Only what is drawn
    /// changes: a word's surface and the projection anchors count in
    /// (`TEIProjection`) are read from the markup, not from these runs.
    static func spaced(_ runs: [TEILine.Run]) -> [TEILine.Run] {
      func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
      }
      var out: [TEILine.Run] = []
      // Whether what was last kept ends in white space, or nothing was kept.
      var afterSpace = true
      for run in runs {
        guard case .text = run.kind else {
          out.append(run)
          afterSpace = false
          continue
        }
        // The source's own white space, kept as it is.
        if run.preserved {
          out.append(run)
          afterSpace = run.text.unicodeScalars.last.map(isSpace) ?? afterSpace
          continue
        }
        var text = String.UnicodeScalarView()
        for scalar in run.text.unicodeScalars {
          if isSpace(scalar) {
            if !afterSpace { text.append(" ") }
            afterSpace = true
          } else {
            text.append(scalar)
            afterSpace = false
          }
        }
        guard !text.isEmpty else { continue }
        out.append(
          .init(
            text: String(text), rend: run.rend, kind: run.kind, alternative: run.alternative,
            highlight: run.highlight, word: run.word, zone: run.zone, element: run.element))
      }
      // None at the end: the last text run's trailing space, unless it is
      // the source's own.
      if let index = out.lastIndex(where: { if case .text = $0.kind { return true } else { return false } }),
        index == out.count - 1, !out[index].preserved, out[index].text.unicodeScalars.last == " "
      {
        let run = out[index]
        var text = run.text.unicodeScalars
        text.removeLast()
        out.remove(at: index)
        if !text.isEmpty {
          out.insert(
            .init(
              text: String(text), rend: run.rend, kind: run.kind, alternative: run.alternative,
              highlight: run.highlight, word: run.word, zone: run.zone, element: run.element,
              preserved: run.preserved), at: index)
        }
      }
      return out
    }

    /// The block setting in a `rend`, TEI's rendition style as the
    /// explication writes it: `align(…)`, `indent(…)` and `hanging`, in
    /// the order written; nothing of an inline rendition (`italic`).
    public static func blockSetting(of rend: String) -> String {
      rend.split(whereSeparator: \.isWhitespace).filter {
        $0.hasPrefix("align(") || $0.hasPrefix("indent(") || $0 == "hanging"
      }.joined(separator: " ")
    }

    /// What a title page's parts can stand in as blocks of their own: a
    /// `docAuthor`, `docDate` or `docEdition` here starts its own line, and
    /// within a byline, an imprint or a title it is a phrase of it.
    static let titlePageStructure: Set<String> = [
      "root", "titlePage", "front", "back", "body", "div", "text",
    ]

    /// A `<formula>`'s MathML as a view draws it, and the symbols it prints
    /// run together (the run's text).
    private static func math(
      _ formula: TEIMarkup.Element, highlights: [TEIHighlight], words: Words?
    ) -> (math: TEIMath, text: String) {
      math(of: formula.elements.first { $0.name == "math" }, highlights: highlights, words: words)
    }

    /// A formula's MathML as `TEIMath.markup` writes it, read back to be
    /// drawn (a diff's formula); nil where it holds no `<math>`.
    public static func math(markup: String) -> TEIMath? {
      guard let element = TEIMarkup.document(markup).elements.first(where: { $0.name == "math" }) else { return nil }
      return math(of: element, highlights: [], words: nil).math
    }

    private static func math(
      of math: TEIMarkup.Element?, highlights: [TEIHighlight], words: Words?
    ) -> (math: TEIMath, text: String) {
      var text = ""
      var source = ""
      func node(_ element: TEIMarkup.Element) -> TEIMath.Node? {
        let attributes = element.attributes.filter { TEIMath.attributes.contains($0.key) }
          .sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        switch element.name {
        case "annotation", "annotation-xml":
          if element.attribute("encoding") == "application/x-tex" { source = element.textContent }
          return nil
        case "semantics" where TEIProjection.isMathGap(element):
          let gap = element.elements.first { $0.name == "annotation-xml" }?.elements.first { $0.name == "gap" }
          return .gap(reason: gap?.attribute("reason") ?? "")
        case "semantics":
          for annotation in element.elements.dropFirst() { _ = node(annotation) }
          return element.elements.first.flatMap(node)
        case let name where TEIMath.tokens.contains(name):
          var runs: [TEILine.Run] = []
          for (index, child) in element.children.enumerated() {
            guard case .text(let value) = child, !value.isEmpty else { continue }
            text += value
            for piece in pieces(of: value, at: element.projected[index], in: highlights, words: words) {
              runs.append(.init(text: piece.text, highlight: piece.highlight, word: piece.word))
            }
          }
          return .token(name: name, attributes: attributes, runs: runs)
        case let name:
          return .element(
            name: TEIMath.elements.contains(name) ? name : "mrow", attributes: attributes,
            children: element.elements.compactMap(node))
        }
      }
      let content = math?.elements.compactMap(node) ?? []
      return (
        TEIMath(display: math?.attribute("display") == "block", content: content, source: source), text
      )
    }

    /// The facsimile at the size the scan actually is.
    ///
    /// Documents carry their pages at `/full/1300,/`, which is what the first
    /// pass reads: a whole quarto page scaled to 1300 pixels puts a line of
    /// type at about fifteen pixels tall, and the last letters of a word are
    /// two or three of them. That is where "Ophelia." comes back as "Ophel."
    /// and "ſleepe" as "ſleep"—the model is not misreading, it cannot see
    /// them. Reading one page is cheap enough to do at native size.
    public static func fullResolutionURL(ofFacsimile url: String) -> String {
      let service = serviceID(ofFacsimile: url)
      guard !service.isEmpty else { return url }
      return "\(service)/full/max/0/default.jpg"
    }

    /// The region of a facsimile a zone names, as a IIIF Image API request.
    ///
    /// A zone is in its surface's coordinates, and IIIF takes a region as a
    /// percentage of the full image—so the two meet as a fraction of the
    /// surface (`TEIZone.percent`; the recognition's 0–1000 surface divides
    /// by ten), and nothing needs to know how many pixels wide the scan is.
    /// That matters: the pixel dimensions live in the manifest, which only
    /// the viewer loads, and a reading that had to wait for it could not be
    /// rendered on the server at all.
    ///
    /// Nil where the facsimile is not an image service.
    public static func regionURL(ofFacsimile url: String, zone: TEIZone, fitting: Int = 600) -> String? {
      let service = serviceID(ofFacsimile: url)
      guard !service.isEmpty else { return nil }
      // Best fit inside a square, not a fixed width. A spine ornament is a
      // narrow slice of a very tall scan, and asking for 600 wide returned it
      // 1500 high—a thumbnail taller than the column it sits in.
      return "\(service)/\(region(zone))/!\(fitting),\(fitting)/0/default.jpg"
    }

    /// A region at the size the scan actually is, for reading rather than
    /// showing. An argument about one word should carry the pixels that settle
    /// it, not a thumbnail of the page it sits on.
    public static func fullResolutionRegionURL(ofFacsimile url: String, zone: TEIZone) -> String? {
      let service = serviceID(ofFacsimile: url)
      guard !service.isEmpty else { return nil }
      return "\(service)/\(region(zone))/full/0/default.jpg"
    }

    /// A zone as a IIIF `pct:` region, each value to a thousandth.
    private static func region(_ zone: TEIZone) -> String {
      func pct(_ value: Double) -> String {
        let scaled = (value * 1000).rounded() / 1000
        return scaled == scaled.rounded() ? String(Int(scaled)) : String(scaled)
      }
      let box = zone.percent
      return "pct:\(pct(box.x)),\(pct(box.y)),\(pct(box.width)),\(pct(box.height))"
    }

    /// The image service a facsimile URL is a request against: everything
    /// before the IIIF Image API parameters. `…/iiif/2/<id>/full/1300,/0/default.jpg`
    /// and `…/iiif/2/<id>/full/max/0/default.jpg` are two requests for one
    /// image, and it is the image that identifies a resemblance.
    public static func serviceID(ofFacsimile url: String) -> String {
      guard let cut = url.range(of: "/full/") else { return url }
      return String(url[url.startIndex..<cut.lowerBound])
    }

    /// `A1v` is how a cataloger writes it and not how a reader reads it.
    /// A trailing r or v after a digit is the side of the leaf; spell it.
    public static func expandedLeafLabel(_ label: String) -> String {
      let lowered = label.lowercased()
      if lowered.hasSuffix(" recto") || lowered.hasSuffix(" verso") { return label }
      guard let last = label.last, last == "r" || last == "v" else { return label }
      let stem = String(label.dropLast())
      guard let previous = stem.last, previous.isNumber else { return label }
      return stem + (last == "r" ? " recto" : " verso")
    }
  }
#endif
