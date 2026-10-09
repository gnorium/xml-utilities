#if SERVER
  import Foundation

  /// An attribute as the transcription writes it: `xml:lang`, `rend`, `when`.
  public struct TEIAttribute: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
      self.name = name
      self.value = value
    }
  }

  /// An element of a page's markup that bears on what a reader opened (a
  /// gloss, user 2026-10-08): the element itself, its attributes as
  /// written, its text, and how it stands to what was opened—around it (a
  /// `<persName>` around a word, the `<note>` it is in), the element opened
  /// (its `<w>`, a `<gap>`), or within it (the `<hi>`, the `<choice>` inside
  /// a word). Nothing encoded is left out: a reader sees in the rendered
  /// text all the markup says of what they opened.
  public struct TEIEncoding: Sendable, Equatable {
    public enum Relation: String, Sendable {
      case around, own, within
    }

    /// Its name, without a namespace prefix: "w", "hi", "persName".
    public let element: String
    /// Its attributes, by name.
    public let attributes: [TEIAttribute]
    /// Its text, white space single and trimmed; "" for a block (a
    /// paragraph, a sentence), whose text is not what was opened—but a
    /// figure's heading, its caption.
    public let text: String
    public let relation: Relation
    /// The element it is directly in: a `<choice>` names its readings'.
    public let parent: String

    public init(element: String, attributes: [TEIAttribute], text: String, relation: Relation, parent: String) {
      self.element = element
      self.attributes = attributes
      self.text = text
      self.relation = relation
      self.parent = parent
    }

    public func attribute(_ name: String) -> String {
      attributes.first { $0.name == name }?.value ?? ""
    }
  }

  extension TEIRenderer {
    /// What sets a page's text out in blocks rather than marks a stretch of
    /// it: a run of text in one is opened by an element around the block,
    /// never by the block, and a block's text is not a gloss's.
    public static let blocks: Set<String> = [
      "root", "TEI", "text", "body", "front", "back", "group", "div", "div1", "div2", "div3", "div4", "div5",
      "p", "s", "ab", "l", "lg", "sp", "table", "row", "cell", "list", "item", "head", "figure", "speaker",
      "stage", "floatingText", "opener", "closer", "titlePage", "docTitle", "titlePart", "argument", "epigraph",
      "trailer", "byline", "docImprint", "salute", "signed", "dateline", "postscript", "castList",
    ]

    /// A page's elements in document order, each with the elements it is in
    /// (the outermost first, the document's root left out): an element's
    /// place in this order is what a reader opens it by (`TEILine.element`,
    /// `TEILine.Run.element`).
    static func elements(of root: TEIMarkup.Element) -> [(element: TEIMarkup.Element, path: [TEIMarkup.Element])] {
      var found: [(element: TEIMarkup.Element, path: [TEIMarkup.Element])] = []
      func visit(_ element: TEIMarkup.Element, path: [TEIMarkup.Element]) {
        for child in element.elements {
          found.append((child, path))
          visit(child, path: path + [child])
        }
      }
      visit(root, path: [])
      return found
    }

    /// What the markup encodes of the word at `place` on `page`, as an
    /// anchor counts its words: every element around it, the word's own
    /// element, and every element within it, in document order; a
    /// `<choice>`'s every reading with it. Nil where no word is there.
    public static func encoding(of page: TEIPage, at place: TEIWordPlace) -> [TEIEncoding]? {
      let root = TEIMarkup.document(TEIProjection.normalized(page.markup))
      let projection = TEIProjection(root)
      guard let unit = projection.units.first(where: { $0.line == place.line && $0.number == place.word })
      else { return nil }
      var spans: [ObjectIdentifier: Range<Int>] = [:]
      measure(root, into: &spans)
      let all = elements(of: root)
      let tokens: Set<String> = ["w", "m", "mi", "mn", "mo", "ms", "mtext"]
      var own: Set<ObjectIdentifier> = []
      for entry in all where tokens.contains(entry.element.name) {
        guard let span = spans[ObjectIdentifier(entry.element)], unit.ranges.contains(span),
          !entry.path.contains(where: { own.contains(ObjectIdentifier($0)) })
        else { continue }
        own.insert(ObjectIdentifier(entry.element))
      }
      // Every part owns its ancestors, even when an annotation encloses
      // only one component of a word continued across a line break.
      let around = Set(all.filter { own.contains(ObjectIdentifier($0.element)) }
        .flatMap { $0.path.map(ObjectIdentifier.init) })
      let whole = unit.range
      var relations: [ObjectIdentifier: TEIEncoding.Relation] = [:]
      for entry in all {
        let id = ObjectIdentifier(entry.element)
        if own.contains(id) {
          relations[id] = .own
        } else if entry.path.contains(where: { relations[ObjectIdentifier($0)] == .own || relations[ObjectIdentifier($0)] == .within }) {
          relations[id] = .within
        } else if around.contains(id) {
          relations[id] = .around
        } else if let span = spans[id] {
          if span.lowerBound <= whole.lowerBound, whole.upperBound <= span.upperBound {
            relations[id] = .around
          } else if own.isEmpty, whole.lowerBound <= span.lowerBound, span.upperBound <= whole.upperBound {
            relations[id] = .within
          }
        } else if own.isEmpty, let start = entry.element.projectedStart, whole.lowerBound < start,
          start < whole.upperBound
        {
          // What an editor adds inside a token no element covers.
          relations[id] = .within
        }
      }
      return encodings(all, relations: relations)
    }

    /// What the markup encodes of the element at `index` among the page's
    /// elements in document order (`elements(of:)`): the elements around
    /// it, it, and the elements within it. Nil where there is none.
    public static func encoding(of page: TEIPage, element index: Int) -> [TEIEncoding]? {
      let root = TEIMarkup.document(TEIProjection.normalized(page.markup))
      let all = elements(of: root)
      guard index >= 0, index < all.count else { return nil }
      let opened = all[index].element
      var relations: [ObjectIdentifier: TEIEncoding.Relation] = [ObjectIdentifier(opened): .own]
      for ancestor in all[index].path { relations[ObjectIdentifier(ancestor)] = .around }
      for entry in all where entry.path.contains(where: { $0 === opened }) {
        relations[ObjectIdentifier(entry.element)] = .within
      }
      return encodings(all, relations: relations)
    }

    /// The elements related, in document order, with every reading of a
    /// `<choice>` among them and what those readings hold.
    private static func encodings(
      _ all: [(element: TEIMarkup.Element, path: [TEIMarkup.Element])],
      relations: [ObjectIdentifier: TEIEncoding.Relation]
    ) -> [TEIEncoding] {
      var relations = relations
      for entry in all where relations[ObjectIdentifier(entry.element)] == nil {
        guard let parent = entry.path.last, let relation = relations[ObjectIdentifier(parent)] else { continue }
        // Its parent is a choice brought in, or a reading brought with one.
        if parent.name == "choice" || entry.path.contains(where: { $0.name == "choice" && relations[ObjectIdentifier($0)] != nil }) {
          relations[ObjectIdentifier(entry.element)] = relation == .own ? .within : relation
        }
      }
      return all.compactMap { entry in
        guard let relation = relations[ObjectIdentifier(entry.element)] else { return nil }
        let element = entry.element
        // A figure's heading is its caption, read as its description is.
        let caption = element.name == "head" && entry.path.last?.name == "figure"
        let text = blocks.contains(element.name) && !caption
          ? "" : element.textContent.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return TEIEncoding(
          element: element.name,
          attributes: element.attributes.keys.sorted().map { TEIAttribute(name: $0, value: element.attributes[$0] ?? "") },
          text: text, relation: relation, parent: entry.path.last?.name ?? "")
      }
    }

    /// The stretch of the projection each element's counted text covers;
    /// none for an element the projection leaves out.
    @discardableResult
    private static func measure(_ element: TEIMarkup.Element, into spans: inout [ObjectIdentifier: Range<Int>])
      -> Range<Int>?
    {
      var low = element.projectedSynthetic?.lowerBound
      var high = element.projectedSynthetic?.upperBound
      for (index, node) in element.children.enumerated() {
        var range: Range<Int>?
        switch node {
        case .text(let text):
          if let position = element.projected[index], position.counted, !text.isEmpty {
            range = position.start..<(position.start + text.unicodeScalars.count)
          }
        case .element(let child):
          range = measure(child, into: &spans)
        }
        if let range {
          low = min(low ?? range.lowerBound, range.lowerBound)
          high = max(high ?? range.upperBound, range.upperBound)
        }
      }
      guard let low, let high else { return nil }
      spans[ObjectIdentifier(element)] = low..<high
      return low..<high
    }
  }
#endif
