#if SERVER
  import Foundation

  /// A stretch of a page's reading to set apart, counted as the concordance
  /// counts a page (`TEIProjection`): an utterance's sentence, and its word.
  public struct TEIHighlight: Sendable, Equatable {
    public enum Kind: String, Sendable {
      /// The sentence an utterance is: an `<s>`, or the passage an anchor
      /// names where no `<s>` holds its word.
      case sentence
      /// The utterance's own word: the anchor's headword.
      case headword
    }

    /// Unicode scalar offsets in the page's projection, half-open.
    public let range: Range<Int>
    public let kind: Kind

    public init(_ range: Range<Int>, kind: Kind) {
      self.range = range
      self.kind = kind
    }
  }

  /// A page's text as the concordance counts it (`diplomatic-codepoints-v2`,
  /// gnorium-python `concordance/text.py` `diplomatic_text`), so that an
  /// utterance's anchor, which counts in it, can be found in the page's
  /// markup: Unicode scalars, not normalized; a `<choice>` reads its orig,
  /// sic or abbr (else its first child); what an editor adds beside the
  /// surface (supplied, reg, expan, corr, ex) and the header, facsimile and
  /// standoff are left out; `<lb/>` and `<pb/>` are a line end unless
  /// `break="no"`; a gap is one U+FFFC; a block (p, head, l, ab, item, cell)
  /// ends with a line end if it has none.
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

    private static let excluded: Set<String> = [
      "teiHeader", "facsimile", "standOff", "supplied", "reg", "expan", "corr", "ex",
    ]
    private static let blocks: Set<String> = ["p", "head", "l", "ab", "item", "cell"]

    private(set) var size = 0
    private(set) var sentences: [Sentence] = []
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
      endsLine = last == "\n"
    }

    private mutating func visit(_ element: TEIMarkup.Element) {
      if Self.excluded.contains(element.name) {
        leaveOut(element)
        return
      }
      let start = size
      element.projectedStart = start
      switch element.name {
      case "gap":
        append("\u{FFFC}")
      case "lb", "pb":
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
        for (index, node) in element.children.enumerated() {
          switch node {
          case .text(let text):
            element.projected[index] = .init(start: size, counted: true)
            append(text)
          case .element(let child):
            visit(child)
          }
        }
      }
      element.projectedEnd = size
      if element.name == "s", size > start {
        sentences.append(.init(range: start..<size, part: element.attribute("part")))
      }
      if Self.blocks.contains(element.name), endsLine == false {
        append("\n")
      }
    }

    /// An element the projection leaves out: each of its texts stands at the
    /// point it would be.
    private func leaveOut(_ element: TEIMarkup.Element) {
      element.projectedStart = size
      element.projectedEnd = size
      for (index, node) in element.children.enumerated() {
        switch node {
        case .text: element.projected[index] = .init(start: size, counted: false)
        case .element(let child): leaveOut(child)
        }
      }
    }
  }

  extension TEIRenderer {
    /// Where an utterance reads in a document's pages: the sentence holding
    /// its word — the smallest `<s>` of its canvas holding the headword, a
    /// sentence split across pages (`<s part="I|M|F">`) joined over the
    /// pages it runs on, as the concordance joins its `sentence_parts` —
    /// and the word itself, by page (its image service). Where no `<s>`
    /// holds the word, the anchor's passage stands for the sentence.
    public static func utterance(
      in pages: [TEIPage], canvasID: String, passage: Range<Int>, headword: Range<Int>
    ) -> [String: [TEIHighlight]] {
      let ids = pages.map { serviceID(ofFacsimile: $0.facsimileURL) }
      guard let at = ids.firstIndex(of: canvasID) else { return [:] }
      // Every sentence of the pages in reading order, page by page.
      var sequence: [(page: Int, sentence: TEIProjection.Sentence)] = []
      for (index, page) in pages.enumerated() {
        sequence += TEIProjection.of(markup: page.markup).sentences
          .sorted { $0.range.lowerBound < $1.range.lowerBound }
          .map { (index, $0) }
      }
      var highlights: [String: [TEIHighlight]] = [:]
      let own = sequence.indices
        .filter { i in
          sequence[i].page == at && sequence[i].sentence.range.lowerBound <= headword.lowerBound
            && headword.upperBound <= sequence[i].sentence.range.upperBound
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
        highlights[canvasID, default: []].append(.init(passage, kind: .sentence))
      }
      highlights[canvasID, default: []].append(.init(headword, kind: .headword))
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
