import XCTest
import XMLUtilities

/// The scan's measured layout (user, 2026-10-14): the tools' block, line and
/// word zones after a page's text block, read and kept wherever its surface
/// is written; each word naming its word zones by its `@facs` (user,
/// 2026-10-15).
final class TEIScanLayoutTests: XCTestCase {
  static let service = "https://example.org/iiif/layout"
  static let layout =
    #"<zone type="block" subtype="main" points="100,100 900,100 900,200 100,200"/>"#
    + #"<zone type="line" points="100,100 900,100 900,150 100,150"/>"#
    + #"<zone xml:id="wz1" type="word" points="100,100 300,100 300,150 100,150"/>"#
  static func document(layout: String) -> String {
    #"<TEI><teiHeader><encodingDesc><tagsDecl><rendition xml:id="size-1" scheme="css">font-size:0.8rem</rendition><rendition xml:id="size-2" scheme="css">font-size:1.0029rem</rendition><rendition xml:id="leading-1" scheme="css">line-height:1.1rem</rendition><rendition xml:id="leading-2" scheme="css">line-height:1.569rem</rendition></tagsDecl></encodingDesc></teiHeader><facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\#(service)/full/max/0/default.jpg" width="2000px" height="3000px"/><zone xml:id="textblock" type="textblock" points="100,100 900,100 900,900 100,900" style="font-size:40px"/>"#
      + layout + #"</surface></facsimile><text><body><pb n="1" facs="\#(service)/full/max/0/default.jpg"/><p>One<lb/></p></body></text></TEI>"#
  }

  func testAPagesLayoutIsReadAndKeptWithItsTextBlock() throws {
    let page = try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: Self.layout)).first)
    let block = try XCTUnwrap(page.textBlock)
    XCTAssertEqual(block.layout, Self.layout)
    let zones = TEIFacsimile.layout(of: block)
    XCTAssertEqual(zones.map(\.type), ["block", "line", "word"])
    XCTAssertEqual(zones[0].subtype, "main")
    XCTAssertEqual(zones[2].fractions, [0.1, 0.1, 0.3, 0.1, 0.3, 0.15, 0.1, 0.15])
    // A page's own facsimile (the editor's, the recognition's) keeps it.
    XCTAssertTrue(TEIFacsimile.block(for: page).contains(Self.layout))
  }

  /// A line's zone holds its baseline as TEI's `<path type="baseline">`
  /// (user, 2026-10-17): read with it, kept with it, never a zone of its
  /// own (no `@facs` names it).
  func testALinesBaselineIsReadAndKeptWithItsZone() throws {
    let layout =
      #"<zone type="block" subtype="main" points="100,100 900,100 900,200 100,200"/>"#
      + #"<zone type="line" points="100,100 900,100 900,150 100,150"><path type="baseline" points="100,140 900,142"/></zone>"#
      + #"<zone xml:id="wz1" type="word" points="100,100 300,100 300,150 100,150"/>"#
    let page = try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: layout)).first)
    let block = try XCTUnwrap(page.textBlock)
    XCTAssertEqual(block.layout, layout)
    let zones = TEIFacsimile.layout(of: block)
    XCTAssertEqual(zones.map(\.type), ["block", "line", "word"])
    XCTAssertEqual(zones[1].baseline, [0.1, 0.14, 0.9, 0.142])
    XCTAssertEqual(zones[0].baseline, [])
    XCTAssertEqual(zones[2].baseline, [])
    XCTAssertTrue(TEIFacsimile.block(for: page).contains(layout))
    XCTAssertEqual(page.zoneIDs.contains("wz1"), true)
  }

  func testEachWordNamesItsZonesAndKeepsThemWhenItsPageIsLaidIn() throws {
    let block = try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: Self.layout)).first?.textBlock)
    XCTAssertEqual(TEIFacsimile.layout(of: block).map(\.id), ["", "", "wz1"])
    // A word's zones, as its @facs names them; a word broken over lines
    // names its two pieces' and is one word with both.
    let words = TEIRenderer.words(of: try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: "")
      .replacingOccurrences(
        of: "<p>One<lb/></p>",
        with: ##"<p><w facs="#wz1">One</w> <w facs="#wz2 #wz3">bro-<lb break="no"/>ken</w> two<lb/></p>"##)).first))
    XCTAssertEqual(words.map(\.surface), ["One", "bro-ken", "two"])
    XCTAssertEqual(words.map(\.zones), [["wz1"], ["wz2", "wz3"], []])
    // Laid into a document, the zones' ids and the pointers to them take
    // the page's prefix; another page's zones keep theirs.
    let page = Self.document(layout: Self.layout + #"<zone xml:id="wz2" type="word" points="1,1 2,1 2,2 1,2"/>"#)
      .replacingOccurrences(of: #"<pb n="1" facs="\#(Self.service)/full/max/0/default.jpg"/>"#, with: "")
    let fragment = ##"<p><w facs="#wz1 #wz2">One</w><lb/></p>"##
    let document = Self.document(layout: "")
    let laid = try XCTUnwrap(TEIFacsimile.laying(
      page: page, fragment: fragment, over: try XCTUnwrap(TEIRenderer.pages(in: document).first), position: 1,
      in: document))
    XCTAssertTrue(laid.contains(##"<w facs="#p1-wz1 #p1-wz2">One</w>"##))
    let kept = try XCTUnwrap(TEIRenderer.pages(in: laid).first)
    XCTAssertEqual(TEIFacsimile.layout(of: try XCTUnwrap(kept.textBlock)).map(\.id), ["", "", "p1-wz1", "p1-wz2"])
    XCTAssertEqual(TEIRenderer.words(of: kept).first?.zones, ["p1-wz1", "p1-wz2"])
  }

  /// A word's `@facs` names polygons of the scan's layout, which are zones of
  /// the document's facsimile but not boxes: a page whose words point at their
  /// zones is whole, one whose pointer names no zone—one pointer or one of
  /// several—is not (prod madrigal dd5cc0b2, 2026-10-17: `#p5-wz17` was
  /// reported missing while the facsimile held it). The same pages as
  /// gnorium-python `test_facsimile.test_a_pointer_names_any_zone_of_the_document`.
  func testAPointerNamesAnyZoneOfTheDocumentsFacsimile() throws {
    let layout =
      #"<zone type="block" subtype="main" points="100,100 900,100 900,200 100,200"/>"#
      + #"<zone type="line" points="100,100 900,100 900,150 100,150"/>"#
      + #"<zone xml:id="p5-wz1" type="word" points="100,100 300,100 300,150 100,150"/>"#
      + #"<zone xml:id="p5-wz2" type="word" points="310,100 500,100 500,150 310,150"/>"#
      + #"<zone xml:id="p5-wz3" type="word" points="100,160 200,160 200,200 100,200"/>"#
    func document(_ body: String) -> String {
      Self.document(layout: layout).replacingOccurrences(of: "<p>One<lb/></p>", with: body)
    }
    let body = ##"<p><w facs="#p5-wz1">One</w> <w facs="#p5-wz2 #p5-wz3">bro-<lb break="no"/>ken</w><lb/></p>"##
    let page = try XCTUnwrap(TEIRenderer.pages(in: document(body)).first)
    // The boxes are the regions of the image; the zones are all of them.
    XCTAssertTrue(page.zones.isEmpty)
    XCTAssertEqual(page.zoneIDs, ["textblock", "p5-wz1", "p5-wz2", "p5-wz3"])
    XCTAssertEqual(TEIFacsimile.references(in: page.markup), ["p5-wz1", "p5-wz2", "p5-wz3"])
    XCTAssertEqual(TEIRenderer.faults(in: page).filter { $0.kind == .zone }.count, 0)
    // A pointer to no zone: alone, or among a word's several.
    for (dangling, detail) in [("p5-wz1", "p5-wz7"), ("p5-wz3", "p5-wz9")] {
      let broken = try XCTUnwrap(
        TEIRenderer.pages(in: document(body.replacingOccurrences(of: "#" + dangling, with: "#" + detail))).first)
      XCTAssertEqual(TEIRenderer.faults(in: broken).filter { $0.kind == .zone }.map(\.detail), ["#" + detail])
    }
    // A page break's image address is no pointer to a zone.
    XCTAssertEqual(TEIFacsimile.references(in: ##"<pb facs="https://example.org/a.jpg"/><w facs='#a #b'>x</w>"##), ["a", "b"])
  }

  func testTheBodysLeadingIsTheLeadingOfTheSizeNearestTheBody() throws {
    let page = try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: "")).first)
    XCTAssertEqual(TEIRendition.bodyLeading(in: page.renditions), 1.569)
  }
}
