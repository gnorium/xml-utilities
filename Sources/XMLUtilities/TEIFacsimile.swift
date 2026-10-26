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
    /// Whether it is derived, not measured (`subtype="derived"`,
    /// gnorium-python `facsimile.DERIVED`): a page that sets no main text
    /// (an owner's label alone) has the work frame placed on its scan as
    /// the edition sets it, centered at its pixels per em
    /// (`layout_measure.derived_corners`). The overlay lays it on the
    /// rendered frame itself, whole.
    public let derived: Bool
    /// The scan's measured layout on the same surface, as the tools wrote
    /// it (gnorium-python `facsimile.layout_zones`, user, 2026-10-14): its
    /// blocks, their lines and the lines' words, flat zones in reading
    /// order after the text block's (`type="block"` with its subtype `main`
    /// or `marginalia`, `type="line"`, `type="word"`; a line is the block's
    /// before it, a word the line's), each its four corners, a line's
    /// holding its baseline's `<path type="baseline">`, a word's zone
    /// with its id, which its `<w>`'s `@facs` names (user, 2026-10-15:
    /// `TEIWord.zones`). Kept with the text block wherever its surface is
    /// written; "" where none was measured. Never written by the model.
    public let layout: String

    public init(
      id: String, points: [Double], surfaceULX: Double = 0, surfaceULY: Double = 0, surfaceLRX: Double = 1000,
      surfaceLRY: Double = 1000, imageWidth: Double = 0, imageHeight: Double = 0, imageURL: String = "",
      label: String = "", body: Double = 0, derived: Bool = false, layout: String = ""
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
      self.derived = derived
      self.layout = layout
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
    /// main text block's measure and height, and its side margin (half its
    /// leaf's width less the measure: the white the typesetter left beside
    /// the text, never the photograph's beyond the leaf, user, 2026-10-26).
    /// Nil where its size or its type is not given.
    public var frame: TEIWorkFrame? {
      guard body > 0, let size else { return nil }
      return TEIWorkFrame(
        body: body, measure: size.measure / body, height: size.height / body,
        margin: max(0, (paperWidth - size.measure) / 2 / body), width: imageWidth / body)
    }

    /// The leaf's width on the scan, in its pixels: its zone (`type="leaf"`,
    /// gnorium-python `facsimile.LEAF`) kept with the scan's structure
    /// (`layout`). The whole scan where it keeps none, as the measuring
    /// takes a scan whose leaf it found no edge of (`layout_measure.leaf_box`).
    public var paperWidth: Double {
      guard let range = layout.range(of: #"<zone\b[^>]*\btype="leaf"[^>]*/>"#, options: .regularExpression),
        surfaceLRX > surfaceULX
      else { return imageWidth }
      let xs = XMLFormatter.attribute("points", in: String(layout[range])).split(whereSeparator: \.isWhitespace)
        .compactMap { $0.split(separator: ",").first.flatMap { Double($0) } }
      guard let left = xs.min(), let right = xs.max(), right > left else { return imageWidth }
      return (right - left) / (surfaceLRX - surfaceULX) * imageWidth
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
    func renamed(_ id: String, imageURL: String? = nil, label: String? = nil, layout: String? = nil) -> TEITextBlock {
      TEITextBlock(
        id: id, points: points, surfaceULX: surfaceULX, surfaceULY: surfaceULY, surfaceLRX: surfaceLRX,
        surfaceLRY: surfaceLRY, imageWidth: imageWidth, imageHeight: imageHeight, imageURL: imageURL ?? self.imageURL,
        label: label ?? self.label, body: body, derived: derived, layout: layout ?? self.layout)
    }
  }

  /// A document's facsimile: its zones, and the pieces that keep them with
  /// their pages when a page is handed to the recognition or laid into the
  /// document again.
  public enum TEIFacsimile {
    private static let blockPattern = try! NSRegularExpression(
      pattern: #"\s*<facsimile\b[^>]*>[\s\S]*?</facsimile>"#)
    private static let surfacePattern = try! NSRegularExpression(pattern: #"<surface\b[^>]*>[\s\S]*?</surface>"#)
    private static let zoneIDPattern = try! NSRegularExpression(
      pattern: #"<zone\b[^>]*?\sxml:id\s*=\s*(["'])([^"']+)\1"#)

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
    /// The subtype of a derived text block (`TEITextBlock.derived`).
    public static let derivedSubtype = "derived"
    /// The zone types of the scan's measured layout (`TEITextBlock.layout`).
    public static let layoutTypes: Set<String> = ["block", "line", "word"]
    /// A layout zone as written: self-closing, or a line's holding its
    /// baseline's `<path type="baseline">` (TEI's own element for it, as
    /// ALTO and PAGE keep a line's baseline; gnorium-python
    /// `facsimile.layout_zones_xml`, user, 2026-10-17).
    private static let layoutZonePattern = try! NSRegularExpression(
      pattern: #"<zone\b[^>]*\btype="(?:block|line|word|leaf)"[^>]*?(?:/>|>\s*<path\b[^>]*/>\s*</zone>)"#)

    /// The layout zones a surface holds (`TEITextBlock.layout`), as
    /// written, in order; "" for none.
    public static func layoutZones(in surface: String) -> String {
      matches(of: layoutZonePattern, in: surface).map { String(surface[$0]) }.joined()
    }

    /// One zone of a scan's measured layout (`TEITextBlock.layout`): its
    /// type ("block", "line" or "word"), a block's subtype ("main" or
    /// "marginalia"), its id (a word's, which its `<w>`'s `@facs` names:
    /// `TEIWord.zones`; "" for a block's and a line's), its four corners,
    /// x and y in turn, as fractions of its surface, and a line's baseline
    /// (its `<path type="baseline">`: where its letters sit, from its left
    /// to its right), its two ends the same way; empty where it has none
    /// (a line with no x-height measured, a block, a word).
    public struct LayoutZone: Sendable, Equatable {
      public let type: String
      public let subtype: String
      public let id: String
      public let fractions: [Double]
      public var baseline: [Double] = []
    }

    /// A text block's layout zones (`TEITextBlock.layout`) read, in order;
    /// a zone whose points are not four corners is left out.
    public static func layout(of block: TEITextBlock) -> [LayoutZone] {
      guard !block.layout.isEmpty else { return [] }
      let root = TEIMarkup.document("<surface>" + block.layout + "</surface>")
      guard let surface = root.elements.first(where: { $0.name == "surface" }) else { return [] }
      let width = block.surfaceLRX - block.surfaceULX
      let height = block.surfaceLRY - block.surfaceULY
      guard width > 0, height > 0 else { return [] }
      return surface.elements.compactMap { zone -> LayoutZone? in
        guard zone.name == "zone", layoutTypes.contains(zone.attribute("type")) else { return nil }
        let points = zone.attribute("points").split(whereSeparator: \.isWhitespace).flatMap {
          $0.split(separator: ",").map { Double($0) }
        }
        guard points.count == 8, points.allSatisfy({ $0 != nil }) else { return nil }
        func fractions(_ values: [Double]) -> [Double] {
          values.enumerated().map { index, value in
            index % 2 == 0 ? (value - block.surfaceULX) / width : (value - block.surfaceULY) / height
          }
        }
        let path = zone.elements.first { $0.name == "path" && $0.attribute("type") == "baseline" }
        let ends = (path?.attribute("points") ?? "").split(whereSeparator: \.isWhitespace).flatMap {
          $0.split(separator: ",").map { Double($0) }
        }
        return LayoutZone(
          type: zone.attribute("type"), subtype: zone.attribute("subtype"), id: zone.attribute("xml:id"),
          fractions: fractions(points.compactMap { $0 }),
          baseline: ends.count == 4 && ends.allSatisfy({ $0 != nil }) ? fractions(ends.compactMap { $0 }) : [])
      }
    }

    /// A page's scan layout as the reader's structure overlay reads it: its
    /// text block's measured layout (`layout(of:)` a block) where its
    /// surface keeps one; else the lines its line breaks name (each `<lb
    /// facs>`'s zone: gnorium-python `calibration.base_tei` writes a zone a
    /// measured line, `z-L7`, the box of its corners on the scan, and no
    /// layout zones), the main text's after its text block as its block, a
    /// marginal note's (`<note place>`) after a block of their own, the box
    /// around them. Such a line has no baseline: it is seated on its box's
    /// foot. None where the page has no measured text block.
    public static func layout(of page: TEIPage) -> [LayoutZone] {
      guard let block = page.textBlock else { return [] }
      let measured = layout(of: block)
      guard measured.isEmpty, block.fractions.count == 8 else { return measured }
      var main: [LayoutZone] = []
      var notes: [[LayoutZone]] = []
      func corners(_ zone: TEIZone) -> [Double] {
        let box = zone.percent
        let (left, top) = (box.x / 100, box.y / 100)
        let (right, bottom) = ((box.x + box.width) / 100, (box.y + box.height) / 100)
        return [left, top, right, top, right, bottom, left, bottom]
      }
      func visit(_ element: TEIMarkup.Element, note: Int?) {
        var note = note
        if element.name == "note", TEIRenderer.marginalArea(of: element.attribute("place")) != nil {
          notes.append([])
          note = notes.count - 1
        }
        if element.name == "lb" {
          for pointer in element.attribute("facs").split(whereSeparator: \.isWhitespace) where pointer.hasPrefix("#") {
            guard let zone = page.zones[String(pointer.dropFirst())] else { continue }
            let line = LayoutZone(type: "line", subtype: "", id: "", fractions: corners(zone))
            if let note { notes[note].append(line) } else { main.append(line) }
          }
        }
        for child in element.elements { visit(child, note: note) }
      }
      visit(TEIMarkup.document(page.markup), note: nil)
      guard !main.isEmpty || notes.contains(where: { !$0.isEmpty }) else { return [] }
      var out = [LayoutZone(type: "block", subtype: "main", id: "", fractions: block.fractions)] + main
      for lines in notes where !lines.isEmpty {
        let xs = lines.flatMap { line in stride(from: 0, to: 8, by: 2).map { line.fractions[$0] } }
        let ys = lines.flatMap { line in stride(from: 1, to: 8, by: 2).map { line.fractions[$0] } }
        let (left, top, right, bottom) = (xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
        out.append(
          LayoutZone(
            type: "block", subtype: "marginalia", id: "", fractions: [left, top, right, top, right, bottom, left, bottom]))
        out += lines
      }
      return out
    }

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
              imageURL: graphic?.attribute("url") ?? "", label: surface.attribute("n"), body: body?.value ?? 0,
              derived: zone.attribute("subtype") == derivedSubtype, layout: layoutZones(in: String(markup[range]))))
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
        // A derived block is the frame placed, never a measure of it.
        guard block.body > 0, !block.derived, let size = block.size else { return nil }
        return (block, size.measure, size.height)
      }
      guard !pages.isEmpty else { return nil }
      func median(_ value: (Page) -> Double) -> Double {
        weightedMedian(pages.map { (value($0), $0.measure * $0.height) })
      }
      let body = median { $0.block.body }
      return TEIWorkFrame(
        body: body, measure: median { $0.measure } / body, height: median { $0.height } / body,
        margin: median { max(0, ($0.block.paperWidth - $0.measure) / 2) } / body, width: median { $0.block.imageWidth } / body)
    }

    /// The size of a work's pages' scans in pixels: the median width and
    /// height of its measured pages' scans, each weighted by its main text
    /// block's area as the work frame is (`workFrame`), so its body pages'
    /// is the size. Nil where none is measured.
    public static func workPage(of blocks: [TEITextBlock]) -> (width: Double, height: Double)? {
      let pages = blocks.compactMap { block -> (TEITextBlock, Double)? in
        guard block.imageWidth > 0, block.imageHeight > 0, !block.derived, let size = block.size else { return nil }
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

    /// `document` with its header's work frame (`TEIRendition.frameID`):
    /// a frame it declares stands—the first frame declared wins, as
    /// everywhere the witness's renditions are joined (`TEIRendition.joined`,
    /// gnorium-python `type_scale.joined`); where it declares none, its
    /// pages' text blocks give it (`workFrame`), and none where no page is
    /// measured. A document with no header is as it was.
    public static func framing(_ document: String) -> String {
      if TEIRendition.frame(in: TEIRendition.declarations(of: TEIRendition.renditions(of: document))) != nil {
        return document
      }
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
        let lineStart = framed[..<close.lowerBound].lastIndex(of: "\n")
        if let lineStart, framed[framed.index(after: lineStart)..<close.lowerBound].allSatisfy({ $0 == " " }) {
          let indent = String(framed[framed.index(after: lineStart)..<close.lowerBound])
          framed.insert(contentsOf: "  " + rendition + "\n" + indent, at: close.lowerBound)
        } else {
          framed.insert(contentsOf: rendition, at: close.lowerBound)
        }
      } else if let close = framed.range(of: "</encodingDesc>") {
        framed.insert(contentsOf: "<tagsDecl>" + rendition + "</tagsDecl>", at: close.lowerBound)
      } else if let at = framed.range(of: "</fileDesc>")?.upperBound {
        framed.insert(contentsOf: "<encodingDesc><tagsDecl>" + rendition + "</tagsDecl></encodingDesc>", at: at)
      }
      return framed
    }

    /// The ids of the zones a page's markup names (`facs="#…"`), in order: a
    /// `@facs` names one zone or several (`#a #b`: a word's pieces on the
    /// scan), and a pointer to anything but a zone of the document (a page
    /// break's image address) is none.
    public static func references(in markup: String) -> [String] {
      matches(of: facsPattern, in: markup, group: 2).flatMap { range in
        markup[range].split(whereSeparator: \.isWhitespace).filter { $0.count > 1 && $0.first == "#" }
          .map { String($0.dropFirst()) }
      }
    }

    /// The ids of every zone a facsimile holds, whatever it is: a figure's or
    /// an initial's box, the page's text block, a word's polygon on the scan
    /// (`type="word"`). What a `@facs` may name; `TEIPage.zones` holds the
    /// boxes alone, the zones that are regions of the image.
    public static func zoneIDs(in facsimile: String) -> Set<String> {
      Set(matches(of: zoneIDPattern, in: facsimile, group: 2).map { String(facsimile[$0]) })
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
    /// (the new page's body) in place of the old page's content, its side's
    /// own page break folded into the page's image break
    /// (`TEIRenderer.layingPage`), and the new page's
    /// zones (its whole TEI, `page`, holds them as `z1`, `z2`…) in the
    /// document's facsimile in place of the old page's surface, each id
    /// prefixed with the page's place (`p3-z1`, gnorium-python
    /// `document_surface`) and the fragment's references renamed to match,
    /// and its renditions joined into the document's header.
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
      let standing = blocks(in: laid)
      let taken = Set(zones(in: standing).keys).union(textBlocks(in: standing).map(\.id))
        .union(textBlocks(in: standing).flatMap { layoutIDs(in: $0.layout) })
      let own = zones(in: page).values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
      let ownBlock = textBlocks(in: blocks(in: page)).first
      // Its word zones' ids, which its words' `@facs` name.
      let ownWords = ownBlock.map { layoutIDs(in: $0.layout) } ?? []
      let ids = own.map(\.id) + (ownBlock.map { [$0.id] } ?? []) + ownWords
      var prefix = "p\(position)-"
      var attempt = 1
      while ids.contains(where: { taken.contains(prefix + $0) }) {
        attempt += 1
        prefix = "p\(position)-\(attempt)-"
      }
      let named = Set(own.map(\.id) + ownWords)
      // Its renditions made to agree with the document's: a step the page
      // numbers as the document numbers another keeps its own value
      // (`TEIRendition.reconciled`).
      let reconciled = TEIRendition.reconciled(
        TEIRendition.renditions(of: page), fragment: renamingPointers(in: fragment, named: named, prefix: prefix),
        with: TEIRendition.renditions(of: laid))
      let renamed = reconciled.fragment
      // The body first (the facsimile precedes it, so its range moves).
      let index = position - 1
      let pages = TEIRenderer.pages(in: laid)
      guard pages.indices.contains(index),
        TEIRenderer.serviceID(ofFacsimile: pages[index].facsimileURL) == service,
        let replaced = TEIRenderer.layingPage(index, with: renamed, in: laid)
      else { return nil }
      laid = replaced
      let surfaces = surface(
        own.map {
          TEIZone(
            id: prefix + $0.id, ulx: $0.ulx, uly: $0.uly, lrx: $0.lrx, lry: $0.lry, surfaceULX: $0.surfaceULX,
            surfaceULY: $0.surfaceULY, surfaceLRX: $0.surfaceLRX, surfaceLRY: $0.surfaceLRY)
        },
        textBlock: ownBlock.map {
          $0.renamed(
            prefix + $0.id, imageURL: old.facsimileURL, label: old.label,
            layout: renamingLayoutIDs(in: $0.layout, prefix: prefix))
        },
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
      // The page's renditions joined into the header's (`TEIRendition.joining`):
      // a step the page references declared in the document it is laid in.
      // The work frame as the pages laid in now give it.
      return framing(TEIRendition.joining(reconciled.renditions, into: laid))
    }

    private static let layoutIDPattern = try! NSRegularExpression(pattern: #"(xml:id\s*=\s*")([^"]+)(")"#)
    private static let facsPattern = try! NSRegularExpression(pattern: #"(\sfacs\s*=\s*["'])([^"']*)(["'])"#)

    /// The ids a text block's layout zones carry (its word zones'), in order.
    static func layoutIDs(in layout: String) -> [String] {
      matches(of: layoutIDPattern, in: layout, group: 2).map { String(layout[$0]) }
    }

    /// A text block's layout zones with each id prefixed (`laying`).
    static func renamingLayoutIDs(in layout: String, prefix: String) -> String {
      var renamed = layout
      for range in matches(of: layoutIDPattern, in: renamed, group: 2).reversed() {
        renamed.replaceSubrange(range, with: prefix + renamed[range])
      }
      return renamed
    }

    /// Markup with each `@facs` pointer to one of the `named` zones
    /// prefixed: a `@facs` names one zone or several (`#a #b`: a word's
    /// pieces on the scan).
    static func renamingPointers(in markup: String, named: Set<String>, prefix: String) -> String {
      var renamed = markup
      for range in matches(of: facsPattern, in: renamed, group: 2).reversed() {
        let pointers = renamed[range].split(whereSeparator: \.isWhitespace).map { pointer -> String in
          guard pointer.hasPrefix("#"), named.contains(String(pointer.dropFirst())) else { return String(pointer) }
          return "#" + prefix + pointer.dropFirst()
        }
        renamed.replaceSubrange(range, with: pointers.joined(separator: " "))
      }
      return renamed
    }

    /// The range of the surface a document's facsimile holds for a page:
    /// the one whose image reads `facsimileURL`, or, with no image, the one
    /// labeled `label` (as `laying` finds a page's surface); nil for none.
    static func surfaceRange(of facsimileURL: String, label: String, in document: String) -> Range<String.Index>? {
      let service = TEIRenderer.serviceID(ofFacsimile: facsimileURL)
      for range in matches(of: surfacePattern, in: document) {
        let written = String(document[range])
        let graphic = XMLFormatter.attribute("url", in: written)
        if graphic.isEmpty ? (!label.isEmpty && XMLFormatter.attribute("n", in: String(written.prefix { $0 != ">" })) == label)
          : TEIRenderer.serviceID(ofFacsimile: graphic) == service
        {
          return range
        }
      }
      return nil
    }

    /// The surface a document holds for a page (`surfaceRange`), as
    /// written; "" where it holds none.
    public static func surface(of page: TEIPage, in document: String) -> String {
      surfaceRange(of: page.facsimileURL, label: page.label, in: document).map { String(document[$0]) } ?? ""
    }

    /// The surfaces a document holds for `pages`, in their order
    /// (`surface(of:in:)` for each), the facsimile read once: a page at a
    /// time read it whole for every page, minutes for a long book's
    /// revision (dev, 2026-10-26).
    public static func surfaces(of pages: [TEIPage], in document: String) -> [String] {
      var byService: [String: String] = [:]
      var byLabel: [String: String] = [:]
      for range in matches(of: surfacePattern, in: document) {
        let written = String(document[range])
        let graphic = XMLFormatter.attribute("url", in: written)
        if graphic.isEmpty {
          let label = XMLFormatter.attribute("n", in: String(written.prefix { $0 != ">" }))
          if !label.isEmpty, byLabel[label] == nil { byLabel[label] = written }
        } else {
          let service = TEIRenderer.serviceID(ofFacsimile: graphic)
          if byService[service] == nil { byService[service] = written }
        }
      }
      return pages.map { page in
        let service = TEIRenderer.serviceID(ofFacsimile: page.facsimileURL)
        return byService[service] ?? (page.label.isEmpty ? nil : byLabel[page.label]) ?? ""
      }
    }

    /// A headed page (`TEIRendition.headedPage`) with its surface as its
    /// `<facsimile>`, after the header and before the text, a zone a line,
    /// as a document holds it: what a page's XML and its diff show alike
    /// (user, 2026-10-16). As it is with no surface.
    public static func headed(_ headed: String, surface: String) -> String {
      guard !surface.isEmpty, let text = headed.range(of: "<text><body>") else { return headed }
      var out = headed
      out.insert(contentsOf: XMLFormatter.prettified("<facsimile>" + surface + "</facsimile>") + "\n", at: text.lowerBound)
      return out
    }

    /// `document` with a page's surface `from` (as `surface(of:in:)` gives
    /// it; "" for none) made `to` ("" removes it): a surface added joins
    /// the document's facsimile, or starts one after its header; a
    /// facsimile left empty goes. Nil where the page's surface is not
    /// `from`: something else changed it.
    public static func replacingSurface(_ from: String, with to: String, of page: TEIPage, in document: String)
      -> String?
    {
      var written = document
      let range = surfaceRange(of: page.facsimileURL, label: page.label, in: written)
      if from.isEmpty {
        guard range == nil else { return nil }
        guard !to.isEmpty else { return written }
        if let open = written.range(of: "<facsimile"),
          let close = written.range(of: "</facsimile>", range: open.upperBound..<written.endIndex)
        {
          written.insert(contentsOf: to, at: close.lowerBound)
        } else if let at = written.range(of: "</teiHeader>")?.upperBound ?? written.range(of: "<text")?.lowerBound {
          written.insert(contentsOf: "\n  <facsimile>" + to + "</facsimile>", at: at)
        } else {
          return nil
        }
        return written
      }
      guard let range, written[range] == from else { return nil }
      written.replaceSubrange(range, with: to)
      if let emptied = written.range(of: #"\s*<facsimile\b[^>]*>\s*</facsimile>"#, options: .regularExpression) {
        written.removeSubrange(emptied)
      }
      return written
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
          + (textBlock.derived ? " subtype=\"\(derivedSubtype)\"" : "")
          + " points=\"\(textBlock.pointsText)\""
          + (textBlock.style.isEmpty ? "" : " style=\"\(textBlock.style)\"") + "/>" + textBlock.layout
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
