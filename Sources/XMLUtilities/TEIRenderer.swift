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

    public init(label: String, facsimileURL: String, lines: [TEILine], markup: String) {
      self.label = label
      self.facsimileURL = facsimileURL
      self.lines = lines
      self.markup = markup
    }
  }

  /// A line of a transcription, carrying what the markup said it was. Line
  /// breaks are kept because they are evidence — a diplomatic transcript says
  /// where the compositor broke the line.
  public struct TEILine: Sendable {
    /// `mark` is a page turn inside the image: a source that photographs
    /// openings puts two sides of the book on one facsimile. `forme` is the
    /// work's own apparatus — running head, catchword, signature, printed page
    /// number — which the page carries but the text does not.
    public enum Kind: Sendable {
      case text, heading, speaker, stage, mark
      /// Forme work, by the job it does on the page. A catchword sits at the
      /// foot under the last line and repeats the next page's first word; a
      /// signature is the binder's mark; a running head names the work. They
      /// are on the page, not in the work, and a reading that sets them in the
      /// flow makes the compositor's catchword look like a line of verse.
      case forme(FormeRole)
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

    public init(kind: Kind, text: String) {
      self.kind = kind
      self.text = text
    }
  }

  /// Reads a TEI document as a document — pages, and the lines on them —
  /// rather than as a tree.
  ///
  /// The counterpart of `MarkdownRenderer`: where that one turns a source
  /// format into HTML, this one turns it into the pages a view draws, because
  /// a facsimile edition is read one opening at a time and no HTML fragment
  /// can carry that structure.
  public enum TEIRenderer {
    /// Split the body at the page breaks that carry a facsimile.
    ///
    /// A document holds two kinds of `<pb>`: one per image, labelled for the
    /// opening ("F1 verso – F2 recto") and carrying `facs`, and one per side of
    /// the leaf, carrying only a label. Counting both made a 64-image quarto
    /// read as 162 pages. A page here is an image; the side marks are lines
    /// within it, where they belong.
    public static func pages(in xml: String) -> [TEIPage] {
      guard let body = XMLFormatter.body(of: xml) else { return [] }

      var pages: [TEIPage] = []
      var cursor = body.startIndex
      var current: (label: String, facs: String, start: String.Index)?

      func page(_ open: (label: String, facs: String, start: String.Index), upTo end: String.Index)
        -> TEIPage
      {
        let markup = String(body[open.start..<end])
        return TEIPage(
          label: open.label,
          facsimileURL: open.facs,
          lines: lines(in: markup),
          markup: markup.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }

      while let open = body.range(of: "<pb", range: cursor..<body.endIndex) {
        guard let close = body.range(of: ">", range: open.upperBound..<body.endIndex) else { break }
        let tag = String(body[open.lowerBound..<close.upperBound])
        let facs = XMLFormatter.attribute("facs", in: tag)
        guard !facs.isEmpty else {
          // A side mark: left in place so `lines(in:)` turns it into a line.
          cursor = close.upperBound
          continue
        }
        if let started = current { pages.append(page(started, upTo: open.lowerBound)) }
        current = (expandedLeafLabel(XMLFormatter.attribute("n", in: tag)), facs, close.upperBound)
        cursor = close.upperBound
      }
      if let started = current { pages.append(page(started, upTo: body.endIndex)) }
      return pages
    }

    /// One page's markup as the lines a reader sees.
    public static func lines(in markup: String) -> [TEILine] {
      var lines: [TEILine] = []
      var kind: TEILine.Kind = .text
      var buffer = ""

      func flush() {
        let text = XMLFormatter.decodingEntities(buffer)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { lines.append(TEILine(kind: kind, text: text)) }
        buffer = ""
        kind = .text
      }

      var cursor = markup.startIndex
      while cursor < markup.endIndex {
        guard let open = markup.range(of: "<", range: cursor..<markup.endIndex) else {
          buffer += markup[cursor...]
          break
        }
        buffer += markup[cursor..<open.lowerBound]
        guard let close = markup.range(of: ">", range: open.upperBound..<markup.endIndex) else {
          break
        }
        let tag = String(markup[open.upperBound..<close.lowerBound])
        let name = tag.split(separator: " ").first.map(String.init) ?? tag
        if name == "pb" {
          // The side of the leaf the following lines belong to.
          flush()
          let label = expandedLeafLabel(XMLFormatter.attribute("n", in: tag))
          if !label.isEmpty { lines.append(TEILine(kind: .mark, text: label)) }
          cursor = close.upperBound
          continue
        }
        switch name {
        case "lb", "lb/", "/p", "/head", "/speaker", "/stage", "/l", "/lg", "/fw":
          flush()
        case "fw":
          flush()
          kind = .forme(TEILine.FormeRole.from(XMLFormatter.attribute("type", in: tag)))
        case "head":
          flush()
          kind = .heading
        case "speaker":
          flush()
          kind = .speaker
        case "stage":
          flush()
          kind = .stage
        default:
          break
        }
        cursor = close.upperBound
      }
      flush()
      return lines
    }

    /// `A1v` is how a cataloguer writes it and not how a reader reads it.
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
