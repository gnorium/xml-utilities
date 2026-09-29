#if SERVER
  import Foundation

  /// A stretch of a page's reading to set apart, counted as the concordance
  /// counts a page (`TEIProjection`): an utterance's sentence, and its word.
  public struct TEIHighlight: Sendable, Equatable {
    public enum Kind: String, Sendable {
      /// The sentence an utterance is: an `<s>`, or the passage an anchor
      /// names where no `<s>` holds its word.
      case sentence
      /// The utterance's own word: the anchor's title.
      case title
    }

    /// Unicode scalar offsets in the page's projection, half-open.
    public let range: Range<Int>
    public let kind: Kind

    public init(_ range: Range<Int>, kind: Kind) {
      self.range = range
      self.kind = kind
    }
  }

  /// A page's text as the concordance counts it (`diplomatic-codepoints-v4`,
  /// gnorium-python `concordance/text.py` `diplomatic_text`), so that an
  /// utterance's anchor, which counts in it, can be found in the page's
  /// markup: Unicode scalars, not normalized; a `<choice>` reads its orig,
  /// sic or abbr (else its first child); what an editor adds beside the
  /// surface (supplied, reg, expan, corr, ex), the encoder's descriptions
  /// (figDesc, desc: gnorium-python `DESCRIPTIONS`) and the header, facsimile
  /// and standoff are left out; `<lb/>` and `<pb/>` are a line end unless
  /// `break="no"`; a gap is one U+FFFC; a line-starting element (l, p, head,
  /// item, note, fw, cell, ab) and a speech's first child end with a line end
  /// if they have none.
  struct TEIProjection {
    /// Where a text node starts, and whether the projection counts it: one it
    /// leaves out stands at the point where it would be.
    struct Position {
      let start: Int
      let counted: Bool
    }

    /// An `<s>`: its span, and its `part` ("I", "M" or "F" for a sentence split
    /// across pages; "" when whole).
    struct Sentence: Equatable {
      let range: Range<Int>
      let part: String
    }

    /// A `<w>`, or a form cited as a form (an `<m>` outside any `<w>`): its
    /// span, its `part` ("I", "M" or "F" for a word broken over lines or
    /// pages; "" when whole), its element, and what the transcription says
    /// of it: its lemma, its lexico type and its morphology (`@lemma`,
    /// `@type`, `@msd`; "" when it says nothing).
    struct Word: Equatable {
      let range: Range<Int>
      let part: String
      var element = "w"
      var lemma = ""
      var msd = ""
      /// The language it is in, as the nearest `xml:lang` over it (its own
      /// included) names it; "" where none does.
      var language = ""
      /// Its lexico type (`@type`, a gnorium-shared PartOfSpeech raw value:
      /// "noun", "preposition", "suffix"); "" where none is written.
      var type = ""
    }

    /// A word as an anchor counts it (gnorium-python `concordance/text.py`
    /// `units`): its line (`breaks`), its place among
    /// the words starting on that line, its parts on this page, its surface
    /// as written here, and whether it runs on to the next page.
    struct Unit: Equatable {
      let line: Int
      let number: Int
      var ranges: [Range<Int>]
      var surface: String
      var runsOn: Bool
      /// Its `<w>`'s (or cited form's `<m>`) element, lemma, type,
      /// morphology and language, as its first part carries them; "" for a
      /// token neither covers.
      var element = ""
      var lemma = ""
      var msd = ""
      var language = ""
      var type = ""
      var range: Range<Int> { ranges[0].lowerBound..<ranges[ranges.count - 1].upperBound }
    }

    private static let excluded: Set<String> = [
      "teiHeader", "facsimile", "standOff", "supplied", "reg", "expan", "corr", "ex",
      // What the encoder writes about the page, never on it: a figure's
      // description, a sound's or an event's. Never a word of an anchor.
      "figDesc", "desc",
    ]
    /// What starts a line (gnorium-python `LINE_STARTS`): a verse line and a
    /// block; the first child of an `<sp>` too.
    private static let lineStarts: Set<String> = ["l", "p", "head", "item", "note", "fw", "cell", "ab"]

    private(set) var size = 0
    private(set) var sentences: [Sentence] = []
    private(set) var words: [Word] = []
    /// Where each line after the first starts, in document order
    /// (`tei-line-word-v2`, gnorium-python `ANCHOR_VERSION`): after each
    /// `<lb/>` (`break="no"` too) and at the start of each verse line, block
    /// and first child of an `<sp>`, once text has been read since the last
    /// start, so an `<lb/>` at a block's start is the same line.
    private(set) var breaks: [Int] = []
    /// Whether text has been read since the last line start.
    private var read = false
    /// The `xml:lang` of each element being visited that names one.
    private var languages: [String] = []
    /// The text, scalar by scalar.
    private(set) var scalars: [Unicode.Scalar] = []
    /// Whether what was last added ends a line; nil before anything is.
    private var endsLine: Bool?

    /// A page's markup, as XML reads it: its line ends are line feeds.
    static func normalized(_ markup: String) -> String {
      markup.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Projects the markup under `root`, noting each text node's place on
    /// its element (`TEIMarkup.Element.projected`).
    init(_ root: TEIMarkup.Element) {
      visit(root)
    }

    /// A page's projection, from its markup.
    static func of(markup: String) -> TEIProjection {
      TEIProjection(TEIMarkup.document(normalized(markup)))
    }

    private mutating func append(_ text: String) {
      guard let last = text.unicodeScalars.last else { return }
      size += text.unicodeScalars.count
      scalars.append(contentsOf: text.unicodeScalars)
      endsLine = last == "\n"
      if text.unicodeScalars.contains(where: { !$0.properties.isWhitespace }) { read = true }
    }

    private mutating func startLine() {
      guard read else { return }
      breaks.append(size)
      read = false
    }

    private mutating func visit(_ element: TEIMarkup.Element, firstOfSpeech: Bool = false) {
      if Self.excluded.contains(element.name) {
        leaveOut(element)
        return
      }
      if Self.lineStarts.contains(element.name) || firstOfSpeech { startLine() }
      let language = element.attribute("xml:lang")
      if !language.isEmpty { languages.append(language) }
      defer { if !language.isEmpty { languages.removeLast() } }
      let start = size
      element.projectedStart = start
      switch element.name {
      case "gap":
        append("\u{FFFC}")
      case "lb", "pb":
        if element.name == "lb" { startLine() }
        if element.attribute("break") != "no" { append("\n") }
      case "choice":
        let children = element.elements
        let chosen =
          ["orig", "sic", "abbr"].lazy.compactMap { name in children.first { $0.name == name } }.first
          ?? children.first
        if let chosen {
          visit(chosen)
        } else {
          for (index, node) in element.children.enumerated() {
            if case .text(let text) = node {
              element.projected[index] = .init(start: size, counted: true)
              append(text)
            }
          }
        }
      default:
        var first = true
        for (index, node) in element.children.enumerated() {
          switch node {
          case .text(let text):
            element.projected[index] = .init(start: size, counted: true)
            append(text)
          case .element(let child):
            visit(child, firstOfSpeech: first && element.name == "sp")
            first = false
          }
        }
      }
      if element.name == "s", size > start {
        sentences.append(.init(range: start..<size, part: element.attribute("part")))
      }
      if element.name == "w" || element.name == "m", size > start {
        let word = Word(
          range: start..<size, part: element.attribute("part"), element: element.name,
          lemma: element.attribute("lemma"), msd: element.attribute("msd"), language: languages.last ?? "",
          type: element.attribute("type"))
        if element.name == "w" {
          // An <m> inside this <w> is part of it (gnorium-python `diplomatic_text`).
          words.removeAll { $0.element == "m" && word.range.contains($0.range.lowerBound) }
        }
        words.append(word)
      }
      // A line-starting element (and a speech's first child) ends its line,
      // so its last word never runs into the next line's first.
      if Self.lineStarts.contains(element.name) || firstOfSpeech, endsLine == false {
        append("\n")
      }
    }

    /// The line a point of the text is on: 1 + the line starts at or before it.
    func line(at offset: Int) -> Int {
      1 + breaks.filter { $0 <= offset }.count
    }

    func text(_ range: Range<Int>) -> String {
      var text = ""
      text.unicodeScalars.append(contentsOf: scalars[range])
      return text
    }

    /// Runs of letters and marks, with apostrophes inside a word
    /// (gnorium-python `tokens`).
    var tokens: [Range<Int>] {
      func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
      }
      func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
      }
      var found: [Range<Int>] = []
      var start: Int?
      for (index, scalar) in scalars.enumerated() {
        let apostrophe =
          (scalar == "'" || scalar == "\u{2019}") && start != nil && index + 1 < scalars.count
          && isLetter(scalars[index + 1])
        if isLetter(scalar) || isMark(scalar) || apostrophe {
          if start == nil { start = index }
        } else if let begun = start {
          found.append(begun..<index)
          start = nil
        }
      }
      if let begun = start { found.append(begun..<scalars.count) }
      return found
    }

    /// The page's words as anchors count them, in order: its `<w>`s, and any
    /// token of text no `<w>` covers. The parts of a word broken over lines
    /// are one word; a page's leading continuation (`<w part="M|F">` before
    /// any word of its own) is the previous page's word.
    var units: [Unit] {
      let covered = words.map(\.range)
      let loose = tokens.filter { token in !covered.contains { $0.overlaps(token) } }
      let items = (words.map { ($0.range, Optional($0.part), Optional($0)) } + loose.map { ($0, String?.none, Word?.none) })
        .sorted { $0.0.lowerBound < $1.0.lowerBound }
      var found: [Unit] = []
      var perLine: [Int: Int] = [:]
      for (range, part, word) in items {
        if let part, part == "M" || part == "F" {
          if var last = found.last, last.runsOn {
            last.ranges.append(range)
            last.surface += text(range)
            last.runsOn = part == "M"
            found[found.count - 1] = last
            continue
          }
          if found.isEmpty { continue }
        }
        let line = line(at: range.lowerBound)
        perLine[line, default: 0] += 1
        found.append(
          .init(
            line: line, number: perLine[line]!, ranges: [range], surface: text(range),
            runsOn: part == "I" || part == "M", element: word?.element ?? "", lemma: word?.lemma ?? "",
            msd: word?.msd ?? "", language: word?.language ?? "", type: word?.type ?? ""))
      }
      return found
    }

    /// The text a page begins with that goes on with the previous page's
    /// broken word, and whether the word ends on this page.
    var leadingContinuation: (text: String, ends: Bool) {
      var continued = ""
      for word in words {
        guard word.part == "M" || word.part == "F" else { return (continued, true) }
        continued += text(word.range)
        if word.part == "F" { return (continued, true) }
      }
      return (continued, continued.isEmpty)
    }

    /// How surfaces are compared: compatibility-folded, case-folded, long s
    /// as s, curly apostrophe as straight, white space single
    /// (gnorium-python `fold`).
    static func fold(_ word: String) -> String {
      word.precomposedStringWithCompatibilityMapping
        .folding(options: .caseInsensitive, locale: nil)
        .replacingOccurrences(of: "ſ", with: "s").replacingOccurrences(of: "\u{2019}", with: "'")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// An element the projection leaves out: each of its texts stands at the
    /// point it would be.
    private func leaveOut(_ element: TEIMarkup.Element) {
      element.projectedStart = size
      for (index, node) in element.children.enumerated() {
        switch node {
        case .text: element.projected[index] = .init(start: size, counted: false)
        case .element(let child): leaveOut(child)
        }
      }
    }
  }

  /// A word of a page as an utterance's anchor names it (`tei-line-word-v2`):
  /// its line (`TEIProjection.breaks`), its place among the words
  /// starting on that line, and its surface as written, which must still read
  /// there.
  public struct TEIWordPosition: Sendable, Equatable {
    public let line: Int
    public let word: Int
    public let surface: String

    public init(line: Int, word: Int, surface: String) {
      self.line = line
      self.word = word
      self.surface = surface
    }
  }

  /// Where a word stands on its page, as an utterance's anchor counts it
  /// (`tei-line-word-v2`): its line and its place among the words starting
  /// on that line. What a reader's word is found by.
  public struct TEIWordPlace: Sendable, Hashable {
    public let line: Int
    public let word: Int

    public init(line: Int, word: Int) {
      self.line = line
      self.word = word
    }
  }

  /// A word of a page and what the transcription says of it: its place,
  /// its surface as written on the page, and its `<w>`'s (or a cited
  /// form's `<m>`) lemma, lexico type (`@type`, a gnorium-shared
  /// PartOfSpeech raw value; UD UPOS derives from it) and morphology
  /// (`@msd`, UD features); "" where the transcription says nothing (a
  /// token neither covers says nothing).
  public struct TEIWord: Sendable, Equatable {
    public let place: TEIWordPlace
    public let surface: String
    /// "w", "m" (a form cited as a form), or "" for a token neither covers.
    public let element: String
    public let lemma: String
    public let morphology: String
    /// Its language, as the nearest `xml:lang` over it names it (ISO 639-3,
    /// as recognition writes it); "" where none does.
    public let language: String
    /// Its lexico type (`@type`: "noun", "preposition", "suffix"); "" where
    /// none is written.
    public let type: String

    /// Whether it is not a whole word (user, 2026-09-29): a form cited as a
    /// form (`<m>`: an affix, a root, a stem), or its lemma or surface an
    /// affix ("με-", "-τρον").
    public var isFragment: Bool {
      element == "m" || [lemma, surface].contains { $0.hasPrefix("-") || $0.hasSuffix("-") }
    }
  }

  extension TEIRenderer {
    /// A page's words as an utterance's anchor counts them
    /// (`tei-line-word-v2`), in reading order: each its place, its surface
    /// as written on this page and what its `<w>` says of it. A word broken
    /// over the page break is its part on this page; the part a page begins
    /// with belongs to the previous page's word.
    public static func words(of page: TEIPage) -> [TEIWord] {
      TEIProjection.of(markup: page.markup).units.map {
        TEIWord(
          place: .init(line: $0.line, word: $0.number), surface: $0.surface, element: $0.element,
          lemma: $0.lemma, morphology: $0.msd, language: $0.language, type: $0.type)
      }
    }

    /// Where an utterance reads in a document's pages: its words, found by
    /// their line and place in the line on the anchor's page (`start` to
    /// `end`), and the sentence holding them — the smallest `<s>` of the page
    /// holding the words, a sentence split across pages (`<s part="I|M|F">`)
    /// joined over the pages it runs on, as the concordance joins its
    /// `sentence_parts` — by page (its image service). Where no `<s>` holds
    /// the words, their lines stand for the sentence. Nil when the page is
    /// not among `pages`, or a word is not there or reads otherwise than its
    /// surface: nothing is highlighted rather than the wrong words.
    public static func utterance(
      in pages: [TEIPage], canvasID: String, start: TEIWordPosition, end: TEIWordPosition
    ) -> [String: [TEIHighlight]]? {
      let ids = pages.map { serviceID(ofFacsimile: $0.facsimileURL) }
      guard let at = ids.firstIndex(of: canvasID) else { return nil }
      let projections = pages.map { TEIProjection.of(markup: $0.markup) }
      let projection = projections[at]
      // Each word's whole surface: a word broken over the page break is its
      // parts on the pages it runs over.
      func located(_ position: TEIWordPosition) -> TEIProjection.Unit? {
        guard let unit = projection.units.first(where: { $0.line == position.line && $0.number == position.word })
        else { return nil }
        var surface = unit.surface
        if unit.runsOn {
          for following in projections.dropFirst(at + 1) {
            let continuation = following.leadingContinuation
            surface += continuation.text
            if continuation.ends { break }
          }
        }
        guard TEIProjection.fold(surface) == TEIProjection.fold(position.surface) else { return nil }
        return unit
      }
      guard let first = located(start), let last = located(end), first.range.lowerBound < last.range.upperBound
      else { return nil }
      let title = first.range.lowerBound..<last.range.upperBound
      // Every sentence of the pages in reading order, page by page.
      var sequence: [(page: Int, sentence: TEIProjection.Sentence)] = []
      for (index, page) in projections.enumerated() {
        sequence += page.sentences
          .sorted { $0.range.lowerBound < $1.range.lowerBound }
          .map { (index, $0) }
      }
      var highlights: [String: [TEIHighlight]] = [:]
      let own = sequence.indices
        .filter { i in
          sequence[i].page == at && sequence[i].sentence.range.lowerBound <= title.lowerBound
            && title.upperBound <= sequence[i].sentence.range.upperBound
        }
        .min { sequence[$0].sentence.range.count < sequence[$1].sentence.range.count }
      if let own {
        var low = own
        var high = own
        let continued = ["M", "F"]
        let continuing = ["I", "M"]
        if ["I", "M", "F"].contains(sequence[own].sentence.part) {
          while continued.contains(sequence[low].sentence.part), low > 0,
            continuing.contains(sequence[low - 1].sentence.part)
          {
            low -= 1
          }
          while continuing.contains(sequence[high].sentence.part), high + 1 < sequence.count,
            continued.contains(sequence[high + 1].sentence.part)
          {
            high += 1
          }
        }
        for entry in sequence[low...high] {
          highlights[ids[entry.page], default: []].append(.init(entry.sentence.range, kind: .sentence))
        }
      } else {
        // The words' lines: from the line end before the first to the line end after the last.
        let breaks = projection.breaks
        let from = first.line >= 2 && first.line - 2 < breaks.count ? breaks[first.line - 2] : 0
        let to = last.line - 1 < breaks.count ? breaks[last.line - 1] : projection.size
        highlights[canvasID, default: []].append(.init(min(from, title.lowerBound)..<max(to, title.upperBound), kind: .sentence))
      }
      highlights[canvasID, default: []].append(.init(title, kind: .title))
      return highlights
    }

    /// A document cut down to the pages around one: the page reading
    /// `serviceID` and up to `radius` pages either side, each page's markup
    /// exactly as the whole document has it (so offsets counted in a page
    /// hold in the excerpt). Nil when no page reads that image.
    public static func excerpt(of xml: String, around serviceID: String, radius: Int = 1) -> String? {
      guard let body = XMLFormatter.body(of: xml) else { return nil }
      let breaks = pageBreaks(in: body)
      guard
        let at = breaks.firstIndex(where: { self.serviceID(ofFacsimile: $0.facsimileURL) == serviceID })
      else { return nil }
      let first = max(0, at - radius)
      let last = min(breaks.count - 1, at + radius)
      let end = last + 1 < breaks.count ? breaks[last + 1].tag.lowerBound : body.endIndex
      return #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>"#
        + body[breaks[first].tag.lowerBound..<end] + "</body></text></TEI>"
    }
  }
#endif
