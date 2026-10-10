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
    /// that page alone; "" where it names none.
    public static func block(for markup: String, zones: [String: TEIZone]) -> String {
      let named = references(in: markup).compactMap { zones[$0] }
      guard !named.isEmpty else { return "" }
      var seen: Set<String> = []
      let distinct = named.filter { seen.insert($0.id).inserted }
      return "<facsimile>" + surface(distinct, label: "", imageURL: "") + "</facsimile>"
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
      let taken = Set(zones(in: blocks(in: laid)).keys)
      let own = zones(in: page).values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
      var prefix = "p\(position)-"
      var attempt = 1
      while own.contains(where: { taken.contains(prefix + $0.id) }) {
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
      let surfaces =
        own.isEmpty
        ? ""
        : surface(
          own.map {
            TEIZone(
              id: prefix + $0.id, ulx: $0.ulx, uly: $0.uly, lrx: $0.lrx, lry: $0.lry, surfaceULX: $0.surfaceULX,
              surfaceULY: $0.surfaceULY, surfaceLRX: $0.surfaceLRX, surfaceLRY: $0.surfaceLRY)
          }, label: old.label, imageURL: old.facsimileURL)
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
      return laid
    }

    /// One page's surface: its label, its extent, its image, its zones.
    static func surface(_ zones: [TEIZone], label: String, imageURL: String) -> String {
      guard let first = zones.first else { return "" }
      var out = "<surface"
      if !label.isEmpty { out += " n=\"\(XMLFormatter.escapingAttribute(label))\"" }
      out +=
        " ulx=\"\(TEIZone.number(first.surfaceULX))\" uly=\"\(TEIZone.number(first.surfaceULY))\""
        + " lrx=\"\(TEIZone.number(first.surfaceLRX))\" lry=\"\(TEIZone.number(first.surfaceLRY))\">"
      if !imageURL.isEmpty { out += "<graphic url=\"\(XMLFormatter.escapingAttribute(imageURL))\"/>" }
      for zone in zones {
        out +=
          "<zone xml:id=\"\(XMLFormatter.escapingAttribute(zone.id))\" ulx=\"\(TEIZone.number(zone.ulx))\""
          + " uly=\"\(TEIZone.number(zone.uly))\" lrx=\"\(TEIZone.number(zone.lrx))\" lry=\"\(TEIZone.number(zone.lry))\"/>"
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
