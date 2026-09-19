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

    /// A stretch of one line set one way.
    public struct Run: Sendable {
      public let text: String
      public let rend: String

      public init(text: String, rend: String = "") {
        self.text = text
        self.rend = rend
      }
    }

    public init(kind: Kind, text: String, rend: String = "", runs: [Run] = []) {
      self.kind = kind
      self.text = text
      self.rend = rend
      self.runs = runs.isEmpty ? [Run(text: text)] : runs
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
      var rend = ""
      var buffer = ""
      var runs: [TEILine.Run] = []
      var inlineRend = ""

      /// Close the run in hand, so the next one can be set differently.
      func closeRun() {
        let text = XMLFormatter.decodingEntities(buffer)
        guard !text.isEmpty else {
          buffer = ""
          return
        }
        runs.append(TEILine.Run(text: text, rend: inlineRend))
        buffer = ""
      }

      func flush() {
        closeRun()
        let text = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          lines.append(TEILine(kind: kind, text: text, rend: rend, runs: runs))
        }
        runs = []
        inlineRend = ""
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
        if name == "gap" || name == "gap/" {
          flush()
          let reason = XMLFormatter.attribute("reason", in: tag)
          lines.append(TEILine(kind: .gap(reason: reason), text: reason.isEmpty ? "gap" : reason))
          cursor = close.upperBound
          continue
        }
        switch name {
        case "p", "lg", "l", "head", "div":
          // Setting is a property of the block, and the lines inside it keep it
          // until the block closes.
          flush()
          let value = XMLFormatter.attribute("rend", in: tag)
          if !value.isEmpty { rend = value }
          if name == "head" { kind = .heading }
        case "/p", "/lg", "/l", "/div":
          flush()
          rend = ""
        case "hi":
          // Inline: the run before it ends here and a new one begins, set the
          // way this says.
          closeRun()
          inlineRend = XMLFormatter.attribute("rend", in: tag)
        case "/hi":
          closeRun()
          inlineRend = ""
        case "lb", "lb/", "/head", "/speaker", "/stage", "/fw":
          flush()
        case "figure", "figure/":
          flush()
          kind = .figure(
            type: XMLFormatter.attribute("type", in: tag),
            bbox: XMLFormatter.attribute("bbox", in: tag)
          )
          // A self-closing figure carries no description, only its region.
          if tag.hasSuffix("/") { flush() }
        case "/figure":
          flush()
        case "figDesc", "/figDesc", "desc", "/desc":
          // The description is the figure's text, not a line of its own.
          break
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
