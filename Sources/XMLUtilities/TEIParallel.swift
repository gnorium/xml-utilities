#if SERVER
  import Foundation

  /// A transcript and its translation as TEI parallel texts: the translation
  /// is a TEI document of its own whose body is the source body's skeleton —
  /// every element, attribute and page break, in order — with only its text
  /// replaced, and every element pointing back at the one it clones with
  /// `@corresp`. The source is never touched.
  ///
  /// A page is read as segments: its text-bearing blocks (a heading, a
  /// paragraph, a verse line, a cell), each as plain text in which every
  /// element inside the block — a line break, a highlight, an abbreviation, a
  /// formula kept as it is, a nested block — stands as a numbered
  /// placeholder, `⟦1⟧`, `⟦2⟧`… A translation of a segment must keep its
  /// placeholders, all of them, in order; its text between them goes back
  /// into the clone where the source's text was. Text is never re-set as
  /// markup: what a translation says is escaped, so it can add no element.
  ///
  /// What is carried depends on the kind of document (`Profile`): a
  /// transcript carries every text-bearing block; a dictionary entry carries
  /// its definitions and the notes and etymology written in English, and
  /// keeps everything else as it is — its forms, its headword, its quotations
  /// and their sources, its labels, its dates and references.
  ///
  /// `@corresp` names the source element by its `xml:id`, or — one without —
  /// as `#{page}.e{n}`, the n-th element of its page counting the page break,
  /// the page named by its image (`#e{n}` before the first page). A pointer
  /// scoped to its page stays put when another page's text changes.
  public struct TEIParallel: Sendable {
    /// One text-bearing block of a page.
    public struct Segment: Sendable, Equatable {
      /// Its key on its page: "s1", "s2"… in document order.
      public let key: String
      /// The block's element, or "text" for a page's text outside any block
      /// (a paragraph opened on the page before).
      public let element: String
      /// Its text, with every element inside it as a numbered placeholder.
      public let text: String
      /// How many placeholders it has.
      public let placeholders: Int
    }

    /// What a kind of document carries into a translation.
    public enum Profile: Sendable {
      /// A diplomatic transcript: every text-bearing block, all but a
      /// formula, a figure, forme work other than a running head.
      case transcript
      /// A dictionary entry (TEI dictionaries): its definitions, and the
      /// notes and etymology written in English. Its forms, headword and
      /// pronunciations, its quotations and their sources, its equivalents,
      /// its labels, dates, identifiers and references are kept as they are.
      case dictionary

      /// Whether an element is kept whole, as one placeholder in its
      /// block's text.
      func opaque(_ name: String, tag: String) -> Bool {
        switch self {
        case .transcript:
          switch name {
          case "formula", "figure": return true
          case "fw":
            let type = XMLFormatter.attribute("type", in: tag).lowercased()
            return !["header", "head", "running-head", "runninghead"].contains(type)
          default: return false
          }
        case .dictionary:
          return [
            "form", "orth", "pron", "hyph", "syll", "stress", "hw", "cit", "quote", "bibl", "biblStruct", "date",
            "ref", "ptr", "idno", "usg", "gramGrp", "pos", "subc", "gen", "number", "case", "per", "tns", "mood",
            "iType", "lang", "mentioned", "gloss", "xr", "lbl", "formula", "figure",
          ].contains(name)
        }
      }

      /// Whether a block's text is carried: every block of a transcript; a
      /// definition, a note or an etymology of a dictionary entry.
      func carries(_ element: String) -> Bool {
        switch self {
        case .transcript: return true
        case .dictionary: return ["def", "note", "etym"].contains(element)
        }
      }
    }

    /// One page: its facsimile and label, as `TEIRenderer` pages the
    /// document, and its segments. A document with no page breaks — a
    /// dictionary entry — is one page, without one.
    public struct Page: Sendable {
      public let facsimileURL: String
      public let segments: [Segment]
      /// The token range of the page: its page break, and the tokens up to
      /// the next.
      let pageBreak: Int?
      let tokens: Range<Int>
      /// Each segment's flow: its items, in order.
      let flows: [String: [Item]]
    }

    /// A token of the body: a tag, kept whole, or a run of text.
    struct Token: Sendable {
      enum Kind: Sendable, Equatable {
        case open(String)
        case close(String)
        case empty(String)
        /// A comment, CDATA, a declaration: kept whole.
        case other
        case text
      }

      let raw: String
      let kind: Kind
      /// The n-th element of the body in document order, for an opening or
      /// empty tag; 0 otherwise.
      let ordinal: Int
    }

    /// One item of a segment's flow: a text token, or what stands as a
    /// placeholder — a tag, or a span of tokens kept as they are.
    enum Item: Sendable {
      case text(Int)
      case placeholder(Range<Int>)
    }

    let tokens: [Token]
    /// Each element's pointer, by token.
    let pointers: [Int: String]
    public let pages: [Page]
    /// What the body holds before its first page: tags opened before the
    /// first page break.
    let prelude: Range<Int>

    /// Elements that sit inside a block's flow of text.
    static let inline: Set<String> = [
      "lb", "hi", "abbr", "expan", "choice", "sic", "corr", "orig", "reg", "unclear", "supplied", "add", "del",
      "seg", "name", "persName", "placeName", "orgName", "rs", "num", "measure", "date", "time", "foreign", "emph",
      "term", "g", "c", "ref", "ptr", "w", "pc", "am", "ex", "handShift", "space", "subst", "damage", "title", "q",
      "quote", "said", "mentioned", "soCalled", "gap", "cb", "milestone", "graphic", "anchor", "metamark",
    ]

    /// The source document, read into pages and segments as its kind
    /// carries them.
    public init(source teiXml: String, profile: Profile = .transcript) {
      let bodyOpen = teiXml.range(of: "<body", options: .caseInsensitive)
      let bodyStart = bodyOpen.flatMap { teiXml.range(of: ">", range: $0.upperBound..<teiXml.endIndex) }?.upperBound
      let bodyEnd = teiXml.range(of: "</body>", options: [.caseInsensitive, .backwards])?.lowerBound
      let start = bodyStart ?? teiXml.startIndex
      let end = bodyEnd.map { max($0, start) } ?? teiXml.endIndex
      let tokens = Self.tokenize(String(teiXml[start..<end]))
      self.tokens = tokens

      // Pages start at every page break that names a facsimile, as
      // `TEIRenderer` pages the document.
      let breaks = tokens.indices.filter { index in
        switch tokens[index].kind {
        case .open("pb"), .empty("pb"): return !XMLFormatter.attribute("facs", in: tokens[index].raw).isEmpty
        default: return false
        }
      }
      var pages: [Page] = []
      for (position, pageBreak) in breaks.enumerated() {
        let range = (pageBreak + 1)..<(position + 1 < breaks.count ? breaks[position + 1] : tokens.count)
        let (segments, flows) = Self.segments(of: tokens, in: range, profile: profile)
        pages.append(
          Page(
            facsimileURL: XMLFormatter.attribute("facs", in: tokens[pageBreak].raw), segments: segments,
            pageBreak: pageBreak, tokens: range, flows: flows))
      }
      if breaks.isEmpty {
        let (segments, flows) = Self.segments(of: tokens, in: tokens.indices, profile: profile)
        pages.append(Page(facsimileURL: "", segments: segments, pageBreak: nil, tokens: tokens.indices, flows: flows))
      }
      self.pages = pages
      prelude = 0..<(breaks.first ?? 0)

      var pointers: [Int: String] = [:]
      var count = 0
      for index in prelude where tokens[index].ordinal > 0 {
        count += 1
        pointers[index] = Self.pointer(tokens[index], or: "e\(count)")
      }
      for (position, page) in pages.enumerated() {
        // A document without pages points as it counts, from its first
        // element.
        let name = page.pageBreak == nil ? nil : Self.pageName(page.facsimileURL, position: position)
        count = 0
        let indices = (page.pageBreak.map { [$0] } ?? []) + Array(page.tokens)
        for index in indices where tokens[index].ordinal > 0 {
          count += 1
          pointers[index] = Self.pointer(tokens[index], or: name.map { "\($0).e\(count)" } ?? "e\(count)")
        }
      }
      self.pointers = pointers
    }

    /// An element's pointer: its `xml:id`, or the name given.
    static func pointer(_ token: Token, or name: String) -> String {
      let id = XMLFormatter.attribute("xml:id", in: token.raw)
      return "#\(id.isEmpty ? name : id)"
    }

    /// A page's name in a pointer: its image service's last part, as letters,
    /// digits and hyphens; "p{n}" for a page without one.
    static func pageName(_ facsimileURL: String, position: Int) -> String {
      let service = TEIRenderer.serviceID(ofFacsimile: facsimileURL)
      let last = service.split(separator: "/").last.map(String.init) ?? ""
      let name = String(last.filter { $0.isLetter || $0.isNumber || $0 == "-" })
      return name.isEmpty ? "p\(position + 1)" : name
    }

    // MARK: - Reading

    static func tokenize(_ body: String) -> [Token] {
      let pattern = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<(?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+"#)
      var out: [Token] = []
      var ordinal = 0
      for match in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        guard let range = Range(match.range, in: body) else { continue }
        let raw = String(body[range])
        guard raw.hasPrefix("<") else {
          out.append(Token(raw: raw, kind: .text, ordinal: 0))
          continue
        }
        if raw.hasPrefix("<!") || raw.hasPrefix("<?") {
          out.append(Token(raw: raw, kind: .other, ordinal: 0))
          continue
        }
        let closing = raw.hasPrefix("</")
        let inner = raw.dropFirst(closing ? 2 : 1).dropLast()
        let qualified = inner.prefix { !$0.isWhitespace && $0 != "/" }
        let name = String(qualified.split(separator: ":").last ?? qualified)
        if closing {
          out.append(Token(raw: raw, kind: .close(name), ordinal: 0))
        } else {
          ordinal += 1
          out.append(
            Token(raw: raw, kind: raw.hasSuffix("/>") ? .empty(name) : .open(name), ordinal: ordinal))
        }
      }
      return out
    }

    /// A page's segments and their flows: one frame a block, the page itself
    /// the first, each holding its text and, as placeholders, every element
    /// inside it; a frame with text in it is a segment.
    static func segments(of tokens: [Token], in range: Range<Int>, profile: Profile) -> ([Segment], [String: [Item]]) {
      final class Frame {
        let element: String
        var items: [Item] = []
        init(element: String) { self.element = element }
      }
      var frames: [Frame] = []
      var stack: [(frame: Frame, name: String)] = []
      let root = Frame(element: "text")
      frames.append(root)
      var current: Frame { stack.last?.frame ?? root }

      var index = range.lowerBound
      while index < range.upperBound {
        let token = tokens[index]
        switch token.kind {
        case .text:
          current.items.append(.text(index))
          index += 1
        case .other, .empty, .close:
          // A closing tag closes the block it names, when it is open on this
          // page; otherwise — an element opened on the page before, or an
          // inline one — it stands in the flow.
          // The block's closing tag stands in its parent's flow.
          if case .close(let name) = token.kind, let open = stack.lastIndex(where: { $0.name == name }) {
            stack.removeSubrange(open...)
          }
          current.items.append(.placeholder(index..<(index + 1)))
          index += 1
        case .open(let name):
          if profile.opaque(name, tag: token.raw) {
            // Kept whole: to its matching close, or the page's end.
            var depth = 0
            var end = index
            while end < range.upperBound {
              switch tokens[end].kind {
              case .open(let inner) where inner == name: depth += 1
              case .close(let inner) where inner == name: depth -= 1
              default: break
              }
              end += 1
              if depth == 0 { break }
            }
            current.items.append(.placeholder(index..<end))
            index = end
          } else if inline.contains(name) {
            current.items.append(.placeholder(index..<(index + 1)))
            index += 1
          } else {
            // A block: its opening tag stands in its parent's flow, and it
            // has a flow of its own.
            current.items.append(.placeholder(index..<(index + 1)))
            let frame = Frame(element: name)
            frames.append(frame)
            stack.append((frame, name))
            index += 1
          }
        }
      }

      var segments: [Segment] = []
      var flows: [String: [Item]] = [:]
      for frame in frames {
        let hasText = frame.items.contains { item in
          if case .text(let index) = item {
            return !tokens[index].raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          }
          return false
        }
        guard hasText, profile.carries(frame.element) else { continue }
        let key = "s\(segments.count + 1)"
        var text = ""
        var placeholders = 0
        for item in frame.items {
          switch item {
          case .text(let index):
            text += collapsed(XMLFormatter.decodingEntities(tokens[index].raw))
          case .placeholder:
            placeholders += 1
            text += "⟦\(placeholders)⟧"
          }
        }
        segments.append(
          Segment(
            key: key, element: frame.element,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines), placeholders: placeholders))
        flows[key] = frame.items
      }
      return (segments, flows)
    }

    /// Text as a reader sees it: every run of white space one space.
    static func collapsed(_ text: String) -> String {
      var out = ""
      var inSpace = false
      for character in text {
        if character.isWhitespace || character.isNewline {
          if !inSpace { out.append(" ") }
          inSpace = true
        } else {
          out.append(character)
          inSpace = false
        }
      }
      return out
    }

    // MARK: - Checking a translation

    /// The placeholders a text carries, in the order it carries them.
    public static func placeholders(in text: String) -> [Int] {
      let pattern = try! NSRegularExpression(pattern: "⟦(\\d+)⟧")
      return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
        Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
      }
    }

    /// What a page's translation breaks: a segment it leaves out, a key the
    /// page has no segment for, a segment whose placeholders are not the
    /// source's, all of them, in order. Empty when it keeps the structure.
    public static func violations(of texts: [String: String], for segments: [Segment]) -> [String] {
      var out: [String] = []
      let keys = Set(segments.map(\.key))
      for segment in segments {
        guard let text = texts[segment.key] else {
          out.append("segment \(segment.key) (\(segment.element)) is missing")
          continue
        }
        let found = placeholders(in: text)
        let expected = Array(1...max(segment.placeholders, 1)).prefix(segment.placeholders)
        if found != Array(expected) {
          out.append(
            "segment \(segment.key) (\(segment.element)) has placeholders \(found.map { "⟦\($0)⟧" }.joined()) "
              + "where the source has \(expected.map { "⟦\($0)⟧" }.joined())")
        }
      }
      for key in texts.keys.sorted() where !keys.contains(key) {
        out.append("segment \(key) is not on the page")
      }
      return out
    }

    // MARK: - Writing the translation

    /// A tag as cloned into the translation: the source's, with `@corresp`
    /// naming the element it clones.
    func cloned(_ index: Int) -> String {
      let token = tokens[index]
      guard let corresp = pointers[index] else { return token.raw }
      let closing = token.raw.hasSuffix("/>") ? "/>" : ">"
      let body = token.raw.dropLast(closing.count)
      return "\(body) corresp=\"\(corresp)\"\(closing)"
    }

    /// Text as XML carries it: escaped, so it can add no element.
    static func escaped(_ text: String) -> String {
      text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// One page of the translation — its page break and everything to the
    /// next — cloned from the source's, its segments' text replaced by
    /// `texts`. The texts must keep the structure (`violations(of:for:)`).
    public func translatedPage(_ pageIndex: Int, texts: [String: String]) throws -> String {
      let page = pages[pageIndex]
      let problems = Self.violations(of: texts, for: page.segments)
      guard problems.isEmpty else { throw Broken(violations: problems) }

      // What each text token becomes, and text put after a tag where the
      // source had none.
      var replaced: [Int: String] = [:]
      var before: [Int: String] = [:]
      var after: [Int: String] = [:]
      for segment in page.segments {
        guard let flow = page.flows[segment.key], let text = texts[segment.key] else { continue }
        // The translation between its placeholders: slot 0 before the
        // first, slot n after the n-th.
        let parts = text.components(separatedBy: "⟦")
        var slots = [parts[0]]
        for part in parts.dropFirst() {
          guard let close = part.firstIndex(of: "⟧") else { continue }
          slots.append(String(part[part.index(after: close)...]))
        }
        // The flow in the same gaps: the text tokens between placeholders.
        var gaps: [[Int]] = [[]]
        var firstTags: [Int] = []
        var lastTags: [Int] = []
        for item in flow {
          switch item {
          case .text(let index): gaps[gaps.count - 1].append(index)
          case .placeholder(let range):
            gaps.append([])
            firstTags.append(range.lowerBound)
            lastTags.append(range.upperBound - 1)
          }
        }
        for (slot, gap) in gaps.enumerated() {
          let translation = slot < slots.count ? slots[slot] : ""
          if let first = gap.first {
            let source = tokens[first].raw
            // White space that only lays the source out stays as it was.
            if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              continue
            }
            replaced[first] = Self.escaped(translation)
            for other in gap.dropFirst() { replaced[other] = "" }
          } else if !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Where the source had no text: after the placeholder before the
            // slot, or before the first.
            if slot > 0 {
              after[lastTags[slot - 1], default: ""] += Self.escaped(translation)
            } else if let first = firstTags.first {
              before[first, default: ""] += Self.escaped(translation)
            }
          }
        }
      }

      var out = page.pageBreak.map(cloned) ?? ""
      for index in page.tokens {
        if let text = before[index] { out += text }
        switch tokens[index].kind {
        case .text: out += replaced[index] ?? tokens[index].raw
        default: out += cloned(index)
        }
        if let text = after[index] { out += text }
      }
      return out
    }

    /// One page of this document as it stands — its page break and
    /// everything to the next — for a translation to keep a page it does not
    /// translate again.
    public func rawPage(_ pageIndex: Int) -> String {
      let page = pages[pageIndex]
      return ((page.pageBreak.map { [$0] } ?? []) + Array(page.tokens)).map { tokens[$0].raw }.joined()
    }

    /// A translation that does not keep the source's structure.
    public struct Broken: Error, CustomStringConvertible {
      public let violations: [String]
      public var description: String { violations.joined(separator: "; ") }
    }

    /// Who made a translation and from what, for its TEI header.
    public struct Responsibility: Sendable {
      /// The language it is in, as a BCP 47 tag, and its name.
      public let language: String
      public let languageName: String
      /// Who translated it: "gnorium madrigal …", and the model.
      public let translator: String
      public let model: String
      /// The exact source it translates, named.
      public let source: String

      public init(language: String, languageName: String, translator: String, model: String, source: String) {
        self.language = language
        self.languageName = languageName
        self.translator = translator
        self.model = model
        self.source = source
      }
    }

    /// The translation as a TEI document of its own: a header saying what it
    /// is in, who made it and from what, and a body that clones the source's
    /// — what stands before the first page, then every page, in order, each
    /// page's text the one given.
    public func document(pages translated: [String], title: String, responsibility: Responsibility) -> String {
      let names = Self.escaped
      let prelude = self.prelude.map { tokens[$0].kind == .text ? tokens[$0].raw : cloned($0) }.joined()
      return """
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc>\
        <titleStmt><title>\(names(title))</title>\
        <respStmt><resp>Translated by</resp><name>\(names(responsibility.translator))</name>\
        <name type="model">\(names(responsibility.model))</name></respStmt></titleStmt>\
        <publicationStmt><p>Gnorium</p></publicationStmt>\
        <sourceDesc><bibl>\(names(responsibility.source))</bibl></sourceDesc></fileDesc>\
        <encodingDesc><p>Every element's @corresp points to the source element it clones: its xml:id, \
        or #{page}.e{n}, the n-th element of its page counting the page break, the page named by its \
        image (#e{n} before the first page).</p></encodingDesc>\
        <profileDesc><langUsage><language ident="\(names(responsibility.language))">\
        \(names(responsibility.languageName))</language></langUsage></profileDesc></teiHeader>\
        <text xml:lang="\(names(responsibility.language))" type="translation"><body>\
        \(prelude)\(translated.joined())</body></text></TEI>
        """
    }

    // MARK: - The structural check

    /// The body's elements as tags, in order, without their text; each
    /// clone's own `@corresp` left out.
    public static func skeleton(of teiXml: String) -> [String] {
      let body = TEIParallel(source: teiXml).tokens
      let corresp = try! NSRegularExpression(pattern: ##" corresp="#[^"]*"(?=/?>$)"##)
      return body.compactMap { token in
        switch token.kind {
        case .text: return nil
        default:
          let raw = token.raw
          return corresp.stringByReplacingMatches(
            in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        }
      }
    }

    /// Whether `translation` is a parallel text of `source`: the same
    /// skeleton, and every element of its body pointing at a distinct element
    /// of the source's, each of them once.
    public static func check(translation: String, of source: String) -> [String] {
      var out: [String] = []
      let from = skeleton(of: source)
      let to = skeleton(of: translation)
      if from != to {
        let at = Array(zip(from, to)).firstIndex { $0 != $1 } ?? min(from.count, to.count)
        out.append(
          "the skeletons part at tag \(at + 1): \(at < from.count ? from[at] : "the end") against "
            + (at < to.count ? to[at] : "the end"))
      }
      let parallel = TEIParallel(source: source)
      let expected = parallel.tokens.indices.compactMap { parallel.pointers[$0] }
      let pointers = TEIParallel(source: translation).tokens.filter { $0.ordinal > 0 }
        .map { XMLFormatter.attribute("corresp", in: $0.raw) }
      if pointers.contains(where: \.isEmpty) { out.append("an element points at nothing") }
      if Set(pointers).count != pointers.count { out.append("two elements point at one source element") }
      if pointers != expected { out.append("the elements do not point at the source's, one to one, in order") }
      return out
    }
  }
#endif
