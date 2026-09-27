#if SERVER
  import Foundation

  /// Attributes to put on one word of a document: the `<w>` whose span on
  /// its page, counted in the page's projection (`TEIProjection`, the
  /// concordance's `diplomatic-codepoints-v2`), is `range` — how a standoff
  /// link (a word's `lemmaRef`) is merged into a transcript for export.
  public struct TEIWordLink: Sendable, Equatable {
    public struct Attribute: Sendable, Equatable {
      public let name: String
      public let value: String

      public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
      }
    }

    /// The page's image service (`TEIRenderer.serviceID(ofFacsimile:)`).
    public let canvasID: String
    /// Unicode scalar offsets in the page's projection, half-open.
    public let range: Range<Int>
    public let attributes: [Attribute]

    public init(canvasID: String, range: Range<Int>, attributes: [Attribute]) {
      self.canvasID = canvasID
      self.range = range
      self.attributes = attributes
    }
  }

  extension TEIRenderer {
    /// The document with each link's attributes written into the start tag
    /// of the `<w>` it names, and nothing else changed: the stored
    /// transcript is never rewritten, this is its export. A word that
    /// already carries an attribute keeps its own value for it. A link whose
    /// page or word is not found is returned in `unmatched`, never dropped
    /// silently. A page whose markup has carriage returns is exported with
    /// line feeds, as the projection counts it.
    public static func linkingWords(in xml: String, links: [TEIWordLink]) -> (
      xml: String, unmatched: [TEIWordLink]
    ) {
      guard !links.isEmpty, let open = xml.range(of: "<body>") else { return (xml, links) }
      let close = xml.range(of: "</body>", range: open.upperBound..<xml.endIndex)?.lowerBound ?? xml.endIndex
      guard open.upperBound < close else { return (xml, links) }
      let body = String(xml[open.upperBound..<close])
      let breaks = pageBreaks(in: body)
      var remaining = links
      var linked = ""
      var cursor = body.startIndex
      for (index, page) in breaks.enumerated() {
        let canvasID = serviceID(ofFacsimile: page.facsimileURL)
        let own = remaining.filter { $0.canvasID == canvasID }
        guard !own.isEmpty else { continue }
        let end = index + 1 < breaks.count ? breaks[index + 1].tag.lowerBound : body.endIndex
        // The page's markup trimmed, as `pages(in:)` gives it and the
        // projection counts it.
        let region = body[page.tag.upperBound..<end]
        guard let first = region.firstIndex(where: { !$0.isWhitespace && !$0.isNewline }),
          let last = region.lastIndex(where: { !$0.isWhitespace && !$0.isNewline })
        else { continue }
        let markup = TEIProjection.normalized(String(region[first...last]))
        let root = TEIMarkup.document(markup)
        _ = TEIProjection(root)
        var words: [TEIMarkup.Element] = []
        collectWords(in: root, into: &words)
        var edits: [(at: String.Index, text: String)] = []
        for link in own {
          guard
            let word = words.first(where: {
              $0.projectedStart == link.range.lowerBound && $0.projectedEnd == link.range.upperBound
            }), let tag = word.tag
          else { continue }
          remaining.removeAll { $0 == link }
          let added = link.attributes.filter { word.attributes[$0.name] == nil }
          guard !added.isEmpty else { continue }
          let text = added.map { " \($0.name)=\"\(XMLFormatter.escapingAttribute($0.value))\"" }.joined()
          let tagText = markup[tag]
          let at = tagText.hasSuffix("/>") ? markup.index(tag.upperBound, offsetBy: -2) : markup.index(before: tag.upperBound)
          edits.append((at, text))
        }
        var page = ""
        var from = markup.startIndex
        for edit in edits.sorted(by: { $0.at < $1.at }) {
          page += markup[from..<edit.at] + edit.text
          from = edit.at
        }
        page += markup[from...]
        linked += body[cursor..<first] + page
        cursor = region.index(after: last)
      }
      linked += body[cursor...]
      return (String(xml[..<open.upperBound]) + linked + String(xml[close...]), remaining)
    }

    private static func collectWords(in element: TEIMarkup.Element, into words: inout [TEIMarkup.Element]) {
      if element.name == "w" { words.append(element) }
      for child in element.elements { collectWords(in: child, into: &words) }
    }
  }
#endif
