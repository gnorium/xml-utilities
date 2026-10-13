import XCTest
import XMLUtilities

final class TEIRenditionTests: XCTestCase {
  func testBoundedStandardStyleAndNamedRendition() throws {
    XCTAssertEqual(TEIRendition.tokens("font-size:2em;position:absolute;letter-spacing:.08em"), "css:font-size=2em css:letter-spacing=.08em")
    XCTAssertFalse(TEIRendition.valid(property: "font-size", value: "999px"))
    let xml = ##"<TEI><teiHeader><encodingDesc><tagsDecl><rendition xml:id="title" scheme="css">font-size:2em;letter-spacing:.08em</rendition></tagsDecl></encodingDesc></teiHeader><text><body><pb n="1" facs="https://example.org/page/full/max/0/default.jpg"/><head rendition="#title" style="line-height:1.2">Title<lb/></head></body></text></TEI>"##
    let page = try XCTUnwrap(TEIRenderer.pages(in: xml).first)
    let line = try XCTUnwrap(page.lines.first)
    XCTAssertTrue(line.rend.contains("css:font-size=2em"))
    XCTAssertTrue(line.rend.contains("css:line-height=1.2"))
    XCTAssertEqual(line.text, "Title")
    XCTAssertFalse(page.renditions.isEmpty)
    XCTAssertTrue(TEIRendition.header(page.renditions).contains("font-size:2em"))
  }
}
