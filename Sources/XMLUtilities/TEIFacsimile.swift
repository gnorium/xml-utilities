#if SERVER
  import Foundation

  /// Where a figure or a decorated initial sits on its page: a TEI `<zone>`
  /// of a `<surface>` in the document's `<facsimile>`, named from the
  /// element by `facs="#…"` (gnorium-python recognition `facsimile.py`;
  /// FIGURES.md §1.1). The recognition's surfaces declare the 0–1000 space
  /// the model boxes in as their own extent, so a zone is resolution-free.
  public struct TEIZone: Sendable, Equatable {
    public let id: String
    /// Its corners, in its surface's coordinates.
    public let ulx: Double
    public let uly: Double
    public let lrx: Double
    public let lry: Double
    /// Its surface's extent, corner to corner.
    public let surfaceULX: Double
    public let surfaceULY: Double
    public let surfaceLRX: Double
    public let surfaceLRY: Double

    public init(
      id: String, ulx: Double, uly: Double, lrx: Double, lry: Double, surfaceULX: Double = 0,
      surfaceULY: Double = 0, surfaceLRX: Double = 1000, surfaceLRY: Double = 1000
    ) {
      self.id = id
      self.ulx = ulx
      self.uly = uly
      self.lrx = lrx
      self.lry = lry
      self.surfaceULX = surfaceULX
      self.surfaceULY = surfaceULY
      self.surfaceLRX = surfaceLRX
      self.surfaceLRY = surfaceLRY
    }

    /// The region as percentages of its surface: its left and top edge, its
    /// width and height, as a IIIF Image API `pct:` region takes them.
    public var percent: (x: Double, y: Double, width: Double, height: Double) {
      let width = surfaceLRX - surfaceULX
      let height = surfaceLRY - surfaceULY
      return (
        (ulx - surfaceULX) / width * 100, (uly - surfaceULY) / height * 100, (lrx - ulx) / width * 100,
        (lry - uly) / height * 100
      )
    }

    /// Its corners as a zone writes them: "ulx uly lrx lry".
    public var corners: String {
      [ulx, uly, lrx, lry].map(Self.number).joined(separator: " ")
    }

    static func number(_ value: Double) -> String {
      value == value.rounded() ? String(Int(value)) : String(value)
    }
  }

  /// A page's main text block on its scan, as the recognition measured it
  /// (gnorium-python `layout_measure.zone_corners`, placed by
  /// `facsimile.place_text_block`; user, 2026-10-13, 2026-10-14): its four
  /// corners, clockwise from the top-left and carrying the page's skew, a
  /// polygon zone (`type="textblock"`, TEI `@points`) of the page's
  /// surface, whose graphic gives the scan's size in pixels (the 0–1000
  /// space keeps no proportions), and whose style gives the type the block
  /// is set in, the scan's pixels per em (`font-size:…px`). Its printed
  /// text only, never its marginalia. Measured by tools, never written by
  /// the model.
  public struct TEITextBlock: Sendable, Equatable {
    public let id: String
    /// The corners, x and y in turn, in its surface's coordinates.
    public let points: [Double]
    /// Its surface's extent, corner to corner.
    public let surfaceULX: Double
    public let surfaceULY: Double
    public let surfaceLRX: Double
    public let surfaceLRY: Double
    /// The scan's size in pixels, its surface's graphic's (0: not given).
    public let imageWidth: Double
    public let imageHeight: Double
    /// Its surface's image and label: which page it is of.
    public let imageURL: String
    public let label: String
    /// The type it is set in: the scan's pixels per em (0: not measured).
    public let body: Double

    public init(
      id: String, points: [Double], surfaceULX: Double = 0, surfaceULY: Double = 0, surfaceLRX: Double = 1000,
      surfaceLRY: Double = 1000, imageWidth: Double = 0, imageHeight: Double = 0, imageURL: String = "",
      label: String = "", body: Double = 0
    ) {
      self.id = id
      self.points = points
      self.surfaceULX = surfaceULX
      self.surfaceULY = surfaceULY
      self.surfaceLRX = surfaceLRX
      self.surfaceLRY = surfaceLRY
      self.imageWidth = imageWidth
      self.imageHeight = imageHeight
      self.imageURL = imageURL
      self.label = label
      self.body = body
    }

    /// The corners as fractions of the page, x and y in turn: where they
    /// are on the scan whatever its resolution.
    public var fractions: [Double] {
      points.enumerated().map { index, value in
        index % 2 == 0
          ? (value - surfaceULX) / (surfaceLRX - surfaceULX) : (value - surfaceULY) / (surfaceLRY - surfaceULY)
      }
    }

    /// Its measure and height in the scan's pixels: its top edge's length
    /// and its left edge's. Nil where the scan's size is not given.
    public var size: (measure: Double, height: Double)? {
      guard imageWidth > 0, imageHeight > 0, points.count == 8 else { return nil }
      let corners = fractions
      func length(_ a: Int, _ b: Int) -> Double {
        let dx = (corners[2 * b] - corners[2 * a]) * imageWidth
        let dy = (corners[2 * b + 1] - corners[2 * a + 1]) * imageHeight
        return (dx * dx + dy * dy).squareRoot()
      }
      return (length(0, 1), length(0, 3))
    }

    /// The page as its own work frame, in its own type's em (`body`): its
    /// main text block's measure and height, and its side margin (half the
    /// scan's width less the measure). Nil where its size or its type is
    /// not given.
    public var frame: TEIWorkFrame? {
      guard body > 0, let size else { return nil }
      return TEIWorkFrame(
        body: body, measure: size.measure / body, height: size.height / body,
        margin: max(0, (imageWidth - size.measure) / 2 / body))
    }

    /// Its zone's style, as written: its type, `font-size` in the scan's
    /// pixels; "" where it was not measured.
    var style: String {
      body > 0 ? "font-size:" + TEIRendition.Length(value: body, unit: "px").text : ""
    }

    /// Its points as a zone writes them: "x1,y1 x2,y2 x3,y3 x4,y4".
    public var pointsText: String {
      stride(from: 0, to: points.count - 1, by: 2).map {
        TEIZone.number(points[$0]) + "," + TEIZone.number(points[$0 + 1])
      }.joined(separator: " ")
    }

    /// The same text block under another id (a page's place in a document).
    func renamed(_ id: String, imageURL: String? = nil, label: String? = nil) -> TEITextBlock {
      TEITextBlock(
        id: id, points: points, surfaceULX: surfaceULX, surfaceULY: surfaceULY, surfaceLRX: surfaceLRX,
        surfaceLRY: surfaceLRY, imageWidth: imageWidth, imageHeight: imageHeight, imageURL: imageURL ?? self.imageURL,
        label: label ?? self.label, body: body)
    }
  }

  /// A document's facsimile: its zones, and the pieces that keep them with
  /// their pages when a page is handed to the recognition or laid into the
  /// document again.
  public enum TEIFacsimile {
    private static let blockPattern = try! NSRegularExpression(
      pattern: #"\s*<facsimile\b[^>]*>[\s\S]*?</facsimile>"#)
    private static let surfacePattern = try! NSRegularExpression(pattern: #"<surface\b[^>]*>[\s\S]*?</surface>"#)
    private static let referencePattern = try! NSRegularExpression(pattern: #"(\sfacs\s*=\s*")#([^"\s]+)(")"#)

    /// The facsimile blocks of a document, as written ("" where it has none).
    public static func blocks(in xml: String) -> String {
      matches(of: blockPattern, in: xml).map { String(xml[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined()
    }

    /// Every zone the markup's surfaces hold, by its `xml:id`. A zone of a
    /// surface that declares no extent (its coordinates in the image's own
    /// pixels, which only the manifest knows) is left out.
    public static func zones(in markup: String) -> [String: TEIZone] {
      var found: [String: TEIZone] = [:]
      for range in matches(of: surfacePattern, in: markup) {
        let root = TEIMarkup.document(String(markup[range]))
        guard let surface = root.elements.first(where: { $0.name == "surface" }),
          let left = Double(surface.attribute("ulx")), let top = Double(surface.attribute("uly")),
          let right = Double(surface.attribute("lrx")), let bottom = Double(surface.attribute("lry")),
          right > left, bottom > top
        else { continue }
        for zone in surface.elements where zone.name == "zone" {
          let id = zone.attribute("xml:id")
          guard !id.isEmpty, let ulx = Double(zone.attribute("ulx")), let uly = Double(zone.attribute("uly")),
            let lrx = Double(zone.attribute("lrx")), let lry = Double(zone.attribute("lry")), lrx > ulx, lry > uly
          else { continue }
          found[id] = TEIZone(
            id: id, ulx: ulx, uly: uly, lrx: lrx, lry: lry, surfaceULX: left, surfaceULY: top, surfaceLRX: right,
            surfaceLRY: bottom)
        }
      }
      return found
    }

    /// The zone type of a page's measured text block.
    public static let textBlockType = "textblock"

    /// Every surface's measured text block (`TEITextBlock`), in document
    /// order. A zone whose points are not four corners, or whose surface
    /// declares no extent, is left out.
    public static func textBlocks(in markup: String) -> [TEITextBlock] {
      var found: [TEITextBlock] = []
      for range in matches(of: surfacePattern, in: markup) {
        let root = TEIMarkup.document(String(markup[range]))
        guard let surface = root.elements.first(where: { $0.name == "surface" }),
          let left = Double(surface.attribute("ulx")), let top = Double(surface.attribute("uly")),
          let right = Double(surface.attribute("lrx")), let bottom = Double(surface.attribute("lry")),
          right > left, bottom > top
        else { continue }
        let graphic = surface.elements.first { $0.name == "graphic" }
        func pixels(_ name: String) -> Double {
          let text = graphic?.attribute(name) ?? ""
          return Double(text.hasSuffix("px") ? String(text.dropLast(2)) : text) ?? 0
        }
        for zone in surface.elements where zone.name == "zone" && zone.attribute("type") == textBlockType {
          let points = zone.attribute("points").split(whereSeparator: \.isWhitespace).flatMap {
            $0.split(separator: ",").map { Double($0) }
          }
          guard points.count == 8, points.allSatisfy({ $0 != nil }) else { continue }
          let body = TEIRendition.Setting(TEIRendition.frameTokens(zone.attribute("style"))).length("font-size")
          found.append(
            TEITextBlock(
              id: zone.attribute("xml:id"), points: points.compactMap { $0 }, surfaceULX: left, surfaceULY: top,
              surfaceLRX: right, surfaceLRY: bottom, imageWidth: pixels("width"), imageHeight: pixels("height"),
              imageURL: graphic?.attribute("url") ?? "", label: surface.attribute("n"), body: body?.value ?? 0))
        }
      }
      return found
    }

    /// The text block of the page that reads `facsimileURL` (labeled
    /// `label`) among a document's: its surface's image's, or, on a
    /// surface with no image, its label's.
    public static func textBlock(of facsimileURL: String, label: String, in blocks: [TEITextBlock]) -> TEITextBlock? {
      let service = TEIRenderer.serviceID(ofFacsimile: facsimileURL)
      return blocks.first { !$0.imageURL.isEmpty && TEIRenderer.serviceID(ofFacsimile: $0.imageURL) == service }
        ?? blocks.first { $0.imageURL.isEmpty && !label.isEmpty && $0.label == label }
    }

    /// The frame every page of a work is set in, its body pages' main text
    /// block (gnorium-python `facsimile.work_frame`): the median body type,
    /// measure, height and side margin of its pages' measured text blocks,
    /// each weighted by its block's area, so a title page or an imprint
    /// counts for the little text it holds; lengths in the work's em, its
    /// body type. Nil where no page's type is measured.
    public static func workFrame(in document: String) -> TEIWorkFrame? {
      typealias Page = (block: TEITextBlock, measure: Double, height: Double)
      let pages = textBlocks(in: blocks(in: document)).compactMap { block -> Page? in
        guard block.body > 0, let size = block.size else { return nil }
        return (block, size.measure, size.height)
      }
      guard !pages.isEmpty else { return nil }
      func median(_ value: (Page) -> Double) -> Double {
        weightedMedian(pages.map { (value($0), $0.measure * $0.height) })
      }
      let body = median { $0.block.body }
      return TEIWorkFrame(
        body: body, measure: median { $0.measure } / body, height: median { $0.height } / body,
        margin: median { ($0.block.imageWidth - $0.measure) / 2 } / body)
    }

    /// The size of a work's pages' scans in pixels: the median width and
    /// height of its measured pages' scans, each weighted by its main text
    /// block's area as the work frame is (`workFrame`), so its body pages'
    /// is the size. Nil where none is measured.
    public static func workPage(of blocks: [TEITextBlock]) -> (width: Double, height: Double)? {
      let pages = blocks.compactMap { block -> (TEITextBlock, Double)? in
        guard block.imageWidth > 0, block.imageHeight > 0, let size = block.size else { return nil }
        return (block, size.measure * size.height)
      }
      guard !pages.isEmpty else { return nil }
      return (
        weightedMedian(pages.map { ($0.0.imageWidth, $0.1) }), weightedMedian(pages.map { ($0.0.imageHeight, $0.1) })
      )
    }

    /// The value at half the total weight, midway between two where the
    /// half falls exactly between them.
    static func weightedMedian(_ values: [(value: Double, weight: Double)]) -> Double {
      let ordered = values.sorted { $0.value < $1.value }
      let half = ordered.reduce(0) { $0 + $1.weight } / 2
      var total = 0.0
      for (index, entry) in ordered.enumerated() {
        total += entry.weight
        if total > half { return entry.value }
        if total == half { return index + 1 < ordered.count ? (entry.value + ordered[index + 1].value) / 2 : entry.value }
      }
      return ordered.last?.value ?? 0
    }

    /// `document` with its header's work frame (`TEIRendition.frameID`)
    /// as its pages' text blocks now give it (`workFrame`): written again
    /// whenever a page is laid in, and gone where no page is measured. A
    /// document with no header is as it was.
    public static func framing(_ document: String) -> String {
      var framed = document
      if let old = framed.range(of: #"\s*<rendition\b[^>]*xml:id="text-block"[^>]*>[^<]*</rendition>"#, options: .regularExpression) {
        framed.removeSubrange(old)
      }
      if let emptied = framed.range(of: #"\s*<tagsDecl>\s*</tagsDecl>"#, options: .regularExpression) {
        framed.removeSubrange(emptied)
      }
      guard let frame = workFrame(in: framed) else { return framed }
      let rendition = TEIRendition.frameRendition(frame)
      if let close = framed.range(of: "</tagsDecl>") {
        framed.insert(contentsOf: rendition, at: close.lowerBound)
      } else if let close = framed.range(of: "</encodingDesc>") {
        framed.insert(contentsOf: "<tagsDecl>" + rendition + "</tagsDecl>", at: close.lowerBound)
      } else if let at = framed.range(of: "</fileDesc>")?.upperBound {
        framed.insert(contentsOf: "<encodingDesc><tagsDecl>" + rendition + "</tagsDecl></encodingDesc>", at: at)
      }
      return framed
    }

    /// The ids of the zones a page's markup names (`facs="#…"`), in order.
    public static func references(in markup: String) -> [String] {
      matches(of: referencePattern, in: markup, group: 2).map { String(markup[$0]) }
    }

    /// A page's markup with the zones it names ahead of it, in a facsimile
    /// of their own: what the recognition is handed as a draft or a known
    /// page, whose service reads the zones back as the boxes the model
    /// writes (gnorium-python `zones_as_bbox`). The markup as it is when it
    /// names none.
    public static func withZones(_ markup: String, zones: [String: TEIZone]) -> String {
      block(for: markup, zones: zones) + markup
    }

    /// A facsimile of the zones a page's markup names, for a document of
    /// that page alone, with the page's measured text block and its image
    /// where it has one; "" where it has neither.
    public static func block(for markup: String, zones: [String: TEIZone], textBlock: TEITextBlock? = nil) -> String {
      let named = references(in: markup).compactMap { zones[$0] }
      guard !named.isEmpty || textBlock != nil else { return "" }
      var seen: Set<String> = []
      let distinct = named.filter { seen.insert($0.id).inserted }
      return "<facsimile>"
        + surface(distinct, textBlock: textBlock, label: textBlock?.label ?? "", imageURL: textBlock?.imageURL ?? "")
        + "</facsimile>"
    }

    /// A page's facsimile for a document of that page alone (`block`).
    public static func block(for page: TEIPage) -> String {
      block(
        for: page.markup, zones: page.zones,
        textBlock: page.textBlock.map { $0.renamed($0.id, imageURL: page.facsimileURL, label: page.label) })
    }

    /// A page laid into a document in place of a page it holds: `fragment`
    /// (the new page's body) in place of the old page's content, and the new page's
    /// zones (its whole TEI, `page`, holds them as `z1`, `z2`…) in the
    /// document's facsimile in place of the old page's surface, each id
    /// prefixed with the page's place (`p3-z1`, gnorium-python
    /// `document_surface`) and the fragment's references renamed to match.
    /// The page is found by its place (`position`, counted from 1, in
    /// `TEIRenderer.pageRanges`), never by searching for its text: a blank
    /// page's empty markup is in no document, and identical markup on an
    /// earlier page would be found first (prod, 2026-10-10). Nil when that
    /// place holds no page reading `old`'s image.
    public static func laying(
      page: String, fragment: String, over old: TEIPage, position: Int, in document: String
    ) -> String? {
      let service = TEIRenderer.serviceID(ofFacsimile: old.facsimileURL)
      // The old page's surface goes; the other pages' zones stay.
      var laid = document
      for range in matches(of: surfacePattern, in: laid).reversed() {
        let tag = String(laid[range].prefix { $0 != ">" })
        let graphic = XMLFormatter.attribute("url", in: String(laid[range]))
        if TEIRenderer.serviceID(ofFacsimile: graphic) == service || XMLFormatter.attribute("n", in: tag) == old.label {
          laid.removeSubrange(range)
        }
      }
      let taken = Set(zones(in: blocks(in: laid)).keys).union(textBlocks(in: blocks(in: laid)).map(\.id))
      let own = zones(in: page).values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
      let ownBlock = textBlocks(in: blocks(in: page)).first
      var prefix = "p\(position)-"
      var attempt = 1
      while own.contains(where: { taken.contains(prefix + $0.id) }) || ownBlock.map({ taken.contains(prefix + $0.id) }) == true {
        attempt += 1
        prefix = "p\(position)-\(attempt)-"
      }
      var renamed = fragment
      for range in matches(of: referencePattern, in: renamed, group: 2).reversed()
      where own.contains(where: { $0.id == renamed[range] }) {
        renamed.replaceSubrange(range, with: prefix + renamed[range])
      }
      // The body first (the facsimile precedes it, so its range moves).
      let index = position - 1
      let pages = TEIRenderer.pages(in: laid)
      guard pages.indices.contains(index),
        TEIRenderer.serviceID(ofFacsimile: pages[index].facsimileURL) == service,
        let replaced = TEIRenderer.replacingPage(index, with: renamed, in: laid)
      else { return nil }
      laid = replaced
      let surfaces = surface(
        own.map {
          TEIZone(
            id: prefix + $0.id, ulx: $0.ulx, uly: $0.uly, lrx: $0.lrx, lry: $0.lry, surfaceULX: $0.surfaceULX,
            surfaceULY: $0.surfaceULY, surfaceLRX: $0.surfaceLRX, surfaceLRY: $0.surfaceLRY)
        }, textBlock: ownBlock.map { $0.renamed(prefix + $0.id, imageURL: old.facsimileURL, label: old.label) },
        label: old.label, imageURL: old.facsimileURL)
      // An empty facsimile goes; a new surface joins the one there is, or
      // starts one after the header.
      if let open = laid.range(of: "<facsimile"), let close = laid.range(of: "</facsimile>", range: open.upperBound..<laid.endIndex) {
        laid.insert(contentsOf: surfaces, at: close.lowerBound)
        if let emptied = laid.range(of: #"\s*<facsimile\b[^>]*>\s*</facsimile>"#, options: .regularExpression) {
          laid.removeSubrange(emptied)
        }
      } else if !surfaces.isEmpty {
        let at = laid.range(of: "</teiHeader>")?.upperBound ?? laid.range(of: "<text")?.lowerBound
        if let at { laid.insert(contentsOf: "\n  <facsimile>" + surfaces + "</facsimile>", at: at) }
      }
      // The work frame as the pages laid in now give it.
      return framing(laid)
    }

    /// One page's surface: its label, its extent, its image (sized where it
    /// has a text block), its zones and its text block; "" with neither.
    static func surface(_ zones: [TEIZone], textBlock: TEITextBlock? = nil, label: String, imageURL: String) -> String {
      let extent: [Double]
      if let first = zones.first {
        extent = [first.surfaceULX, first.surfaceULY, first.surfaceLRX, first.surfaceLRY]
      } else if let textBlock {
        extent = [textBlock.surfaceULX, textBlock.surfaceULY, textBlock.surfaceLRX, textBlock.surfaceLRY]
      } else {
        return ""
      }
      var out = "<surface"
      if !label.isEmpty { out += " n=\"\(XMLFormatter.escapingAttribute(label))\"" }
      out +=
        " ulx=\"\(TEIZone.number(extent[0]))\" uly=\"\(TEIZone.number(extent[1]))\""
        + " lrx=\"\(TEIZone.number(extent[2]))\" lry=\"\(TEIZone.number(extent[3]))\">"
      if let textBlock, textBlock.imageWidth > 0, textBlock.imageHeight > 0 {
        out +=
          "<graphic url=\"\(XMLFormatter.escapingAttribute(imageURL))\" width=\"\(TEIZone.number(textBlock.imageWidth))px\""
          + " height=\"\(TEIZone.number(textBlock.imageHeight))px\"/>"
      } else if !imageURL.isEmpty {
        out += "<graphic url=\"\(XMLFormatter.escapingAttribute(imageURL))\"/>"
      }
      for zone in zones {
        out +=
          "<zone xml:id=\"\(XMLFormatter.escapingAttribute(zone.id))\" ulx=\"\(TEIZone.number(zone.ulx))\""
          + " uly=\"\(TEIZone.number(zone.uly))\" lrx=\"\(TEIZone.number(zone.lrx))\" lry=\"\(TEIZone.number(zone.lry))\"/>"
      }
      if let textBlock {
        out +=
          "<zone xml:id=\"\(XMLFormatter.escapingAttribute(textBlock.id))\" type=\"\(textBlockType)\""
          + " points=\"\(textBlock.pointsText)\""
          + (textBlock.style.isEmpty ? "" : " style=\"\(textBlock.style)\"") + "/>"
      }
      return out + "</surface>"
    }

    private static func matches(of pattern: NSRegularExpression, in text: String, group: Int = 0) -> [Range<String.Index>]
    {
      pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range(at: group), in: text)
      }
    }
  }
#endif
