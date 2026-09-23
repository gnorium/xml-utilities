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

  /// A line or structured block of a transcription, carrying what the markup said it was. Line
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
      /// Nothing was transcribed here, and the reason why: `<gap reason="blank"/>`
      /// for a surface with nothing on it, or a damaged one. It is a statement
      /// about the page, not a word on it.
      case gap(reason: String)
      /// Something drawn rather than set: a printer's device, an ornament, a
      /// decorated initial. `bbox` is where it sits on the surface, in a
      /// normalized 0–1000 space, so the region can be cut from the facsimile.
      ///
      /// A figure is not a line of the text. Its `<figDesc>` describes the
      /// object — "gold-tooled dark leather binding" — and setting that in the
      /// reading says the cover bears those words, which it does not.
      case figure(type: String, bbox: String)
      /// Rows and cells must survive parsing; their order alone cannot recover
      /// the relationship between a heading and a value after flattening.
      case table(TEITable)
      case documentBoundary
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
    /// compositor set it is part of that — a centred block on a title page is
    /// how an imprint statement or an epigraph is marked, and a reading that
    /// ranges it left has quietly dropped evidence.
    public let rend: String
    /// The line's runs, each with the setting the transcription gave it.
    ///
    /// `<hi rend="…">` is inline — small caps in an author statement, an
    /// italic speaker prefix — so it cannot be a property of the whole line.
    /// The renderer used to drop `<hi>` and keep its text, which turned
    /// "By WILLIAM SHAKESPEARE" and every italicised speaker into plain prose.
    public let runs: [Run]
    /// Whether the line opens a block — a paragraph, a verse line, a heading,
    /// anything set apart — rather than following an `<lb/>` inside one. A
    /// line break and a paragraph break are different evidence, and a diff
    /// that turned one into the other has changed the page.
    public let opensBlock: Bool

    /// A stretch of one line set one way.
    public struct Run: Sendable {
      public enum Kind: Sendable {
        case text
        case tex(display: Bool)
      }

      public let text: String
      public let rend: String
      public let kind: Kind

      public init(text: String, rend: String = "", kind: Kind = .text) {
        self.text = text
        self.rend = rend
        self.kind = kind
      }
    }

    public init(kind: Kind, text: String, rend: String = "", runs: [Run] = [], opensBlock: Bool = true) {
      self.kind = kind
      self.text = text
      self.rend = rend
      self.runs = runs.isEmpty ? [Run(text: text)] : runs
      self.opensBlock = opensBlock
    }
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
      reading(from: TEIMarkup.parse(markup))
    }

    private static func reading(from nodes: [TEIMarkup.Node]) -> [TEILine] {
      var lines: [TEILine] = []
      var runs: [TEILine.Run] = []
      var currentKind: TEILine.Kind = .text
      var currentRend = ""
      // Whether the next line opens a block: true until a line is set, and
      // again at every block's edge; an `<lb/>` leaves it false.
      var blockPending = true

      func flush() {
        let text = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          lines.append(
            TEILine(kind: currentKind, text: text, rend: currentRend, runs: runs, opensBlock: blockPending))
          blockPending = false
        }
        runs = []
      }

      func append(_ line: TEILine) {
        lines.append(line)
        blockPending = true
      }

      func walk(
        _ nodes: [TEIMarkup.Node], kind: TEILine.Kind = .text,
        rend: String = "", inlineRend: String = ""
      ) {
        for node in nodes {
          switch node {
          case .text(let text):
            currentKind = kind
            currentRend = rend
            if !text.isEmpty { runs.append(.init(text: text, rend: inlineRend)) }
          case .element(let element):
            let ownRend = element.attribute("rend")
            let blockRend = ownRend.isEmpty ? rend : ownRend
            switch element.name {
            case "formula"
            where ["tex", "latex"].contains(element.attribute("notation").lowercased()):
              currentKind = kind
              currentRend = rend
              let display =
                ownRend.split(whereSeparator: \.isWhitespace).contains("display")
                || element.attribute("type") == "display"
              runs.append(
                .init(text: element.textContent, rend: inlineRend, kind: .tex(display: display)))
            case "hi":
              // Passing the inherited setting down the tree restores it when
              // a nested span closes, including across physical line breaks.
              walk(
                element.children, kind: kind, rend: rend,
                inlineRend: [inlineRend, ownRend].filter { !$0.isEmpty }.joined(separator: " "))
            case "lb", "cb":
              flush()
            case "pb":
              flush()
              let label = expandedLeafLabel(element.attribute("n"))
              if !label.isEmpty { append(.init(kind: .mark, text: label)) }
            case "gap":
              flush()
              let reason = element.attribute("reason")
              append(.init(kind: .gap(reason: reason), text: reason.isEmpty ? "gap" : reason))
            case "milestone" where element.attribute("unit") == "document":
              flush()
              append(.init(kind: .documentBoundary, text: ""))
            case "p", "lg", "l", "head", "div", "speaker", "stage", "fw":
              flush()
              blockPending = true
              let blockKind: TEILine.Kind
              switch element.name {
              case "head": blockKind = .heading
              case "speaker": blockKind = .speaker
              case "stage": blockKind = .stage
              case "fw": blockKind = .forme(.from(element.attribute("type")))
              default: blockKind = kind
              }
              walk(element.children, kind: blockKind, rend: blockRend, inlineRend: inlineRend)
              flush()
              blockPending = true
            case "table":
              flush()
              let children = element.elements
              let caption = children.filter { $0.name == "head" }.flatMap {
                reading(from: $0.children)
              }
              let rows = children.filter { $0.name == "row" }.map { row in
                TEITable.Row(
                  cells: row.elements.filter { $0.name == "cell" }.map { cell in
                    TEITable.Cell(
                      lines: reading(from: cell.children),
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
              let description = descriptions.flatMap { reading(from: $0.children) }.map(\.text)
                .joined(separator: " ")
              append(
                .init(
                  kind: .figure(type: element.attribute("type"), bbox: element.attribute("bbox")),
                  text: description))
              // Captions, tables, and diagram labels remain readable even when
              // the graphic has no usable crop. figDesc is descriptive metadata.
              let content = element.children.filter { node in
                if case .element(let child) = node {
                  return child.name != "figDesc" && child.name != "desc"
                }
                return element.attribute("type") != "initial"
              }
              walk(content, kind: kind, rend: rend, inlineRend: inlineRend)
              flush()
              blockPending = true
            default:
              walk(element.children, kind: kind, rend: rend, inlineRend: inlineRend)
            }
          }
        }
      }
      walk(nodes)
      flush()
      return lines
    }

    /// The facsimile at the size the scan actually is.
    ///
    /// Documents carry their pages at `/full/1300,/`, which is what the first
    /// pass reads: a whole quarto page scaled to 1300 pixels puts a line of
    /// type at about fifteen pixels tall, and the last letters of a word are
    /// two or three of them. That is where "Ophelia." comes back as "Ophel."
    /// and "ſleepe" as "ſleep" — the model is not misreading, it cannot see
    /// them. Re-reading one page is cheap enough to do at native size.
    public static func fullResolutionURL(ofFacsimile url: String) -> String {
      let service = serviceID(ofFacsimile: url)
      guard !service.isEmpty else { return url }
      return "\(service)/full/max/0/default.jpg"
    }

    /// The region of a facsimile a `bbox` names, as a IIIF Image API request.
    ///
    /// The bbox is `x y w h` in a normalized 0–1000 space, and IIIF takes a
    /// region as a percentage of the full image — so the two meet by dividing
    /// by ten, and nothing needs to know how many pixels wide the scan is.
    /// That matters: the pixel dimensions live in the manifest, which only the
    /// viewer loads, and a reading that had to wait for it could not be
    /// rendered on the server at all.
    ///
    /// Returns nil when the bbox is not four numbers — a malformed one should
    /// leave the figure without a crop, not with the wrong one.
    /// A region at the size the scan actually is, for reading rather than
    /// showing. An argument about one word should carry the pixels that settle
    /// it, not a thumbnail of the page it sits on.
    public static func fullResolutionRegionURL(ofFacsimile url: String, bbox: String)
      -> String?
    {
      let parts = bbox.split(whereSeparator: { $0 == " " || $0 == "," })
        .compactMap { Double($0) }
      guard parts.count == 4 else { return nil }
      let service = serviceID(ofFacsimile: url)
      guard !service.isEmpty else { return nil }
      func pct(_ value: Double) -> String {
        let scaled = (value / 10 * 1000).rounded() / 1000
        return scaled == scaled.rounded() ? String(Int(scaled)) : String(scaled)
      }
      let region = "pct:\(pct(parts[0])),\(pct(parts[1])),\(pct(parts[2])),\(pct(parts[3]))"
      return "\(service)/\(region)/full/0/default.jpg"
    }

    public static func regionURL(ofFacsimile url: String, bbox: String, fitting: Int = 600)
      -> String?
    {
      let parts = bbox.split(whereSeparator: { $0 == " " || $0 == "," })
        .compactMap { Double($0) }
      guard parts.count == 4 else { return nil }
      let service = serviceID(ofFacsimile: url)
      guard !service.isEmpty else { return nil }
      func pct(_ value: Double) -> String {
        let scaled = (value / 10 * 1000).rounded() / 1000
        return scaled == scaled.rounded() ? String(Int(scaled)) : String(scaled)
      }
      let region = "pct:\(pct(parts[0])),\(pct(parts[1])),\(pct(parts[2])),\(pct(parts[3]))"
      // Best fit inside a square, not a fixed width. A spine ornament is a
      // narrow slice of a very tall scan, and asking for 600 wide returned it
      // 1500 high — a thumbnail taller than the column it sits in.
      return "\(service)/\(region)/!\(fitting),\(fitting)/0/default.jpg"
    }

    /// The image service a facsimile URL is a request against: everything
    /// before the IIIF Image API parameters. `…/iiif/2/<id>/full/1300,/0/default.jpg`
    /// and `…/iiif/2/<id>/full/max/0/default.jpg` are two requests for one
    /// image, and it is the image that identifies a rendition.
    public static func serviceID(ofFacsimile url: String) -> String {
      guard let cut = url.range(of: "/full/") else { return url }
      return String(url[url.startIndex..<cut.lowerBound])
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
