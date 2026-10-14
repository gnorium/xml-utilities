import XCTest
import XMLUtilities

/// The scan's measured layout (user, 2026-10-14): the tools' block, line and
/// word zones after a page's text block, read, kept wherever its surface is
/// written, and placed where a page keeps a text block without them.
final class TEIScanLayoutTests: XCTestCase {
  static let service = "https://example.org/iiif/layout"
  static let layout =
    #"<zone type="block" subtype="main" points="100,100 900,100 900,200 100,200"/>"#
    + #"<zone type="line" points="100,100 900,100 900,150 100,150"/>"#
    + #"<zone type="word" points="100,100 300,100 300,150 100,150"/>"#
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

  func testMeasurePagesPlacesALayoutAfterAKeptTextBlock() throws {
    let document = Self.document(layout: "")
    let page = try XCTUnwrap(TEIRenderer.pages(in: document).first)
    let surface = try XCTUnwrap(TEIFacsimile.placingLayout(Self.layout, on: page, in: document))
    XCTAssertTrue(surface.contains(#"style="font-size:40px"/>"# + Self.layout))
    // Kept already: nothing to place.
    let kept = try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: Self.layout)).first)
    XCTAssertNil(TEIFacsimile.placingLayout(Self.layout, on: kept, in: Self.document(layout: Self.layout)))
  }

  func testTheBodysLeadingIsTheLeadingOfTheSizeNearestTheBody() throws {
    let page = try XCTUnwrap(TEIRenderer.pages(in: Self.document(layout: "")).first)
    XCTAssertEqual(TEIRendition.bodyLeading(in: page.renditions), 1.569)
  }
}
