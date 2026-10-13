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

  /// A block's style cascades as CSS's does: a division's size, leading,
  /// indent and margins reach its paragraphs, whose own rend adds to them.
  func testDivisionStyleCascadesToItsParagraphs() {
    let lines = TEIRenderer.lines(
      in: #"<div style="font-size:0.75em;line-height:1.35;margin-inline-start:2em;text-indent:2em"><p rend="align(justify)">One<lb/>two</p><p style="font-size:0.8em;margin-inline-start:1em">Three</p></div>"#)
    XCTAssertEqual(lines[0].rend, "css:font-size=0.75em css:line-height=1.35 css:margin-inline-start=2em css:text-indent=2em align(justify)")
    XCTAssertEqual(lines[1].rend, lines[0].rend)
    // em counts the paragraph's own font, 0.8 of the division's: the
    // division's 2em margin and indent are 2.5 of its em.
    XCTAssertEqual(lines[2].rend, "css:font-size=0.6em css:line-height=1.35 css:margin-inline-start=3.5em css:text-indent=2.5em")
  }

  /// The type size's bounds hold of the size the cascade computes, not
  /// only of each written value: 0.5em inside 0.7em is 0.35em of the page,
  /// below its 0.5em, and is no size (the paragraph keeps the division's).
  func testComputedFontSizeIsBounded() {
    XCTAssertEqual(TEIRendition.fontSizes, 0.5...4)
    XCTAssertEqual(TEIRendition.cascade("css:font-size=0.7em", "css:font-size=0.5em"), "css:font-size=0.7em")
    XCTAssertEqual(TEIRendition.cascade("css:font-size=0.7em", "css:font-size=0.8em"), "css:font-size=0.56em")
    XCTAssertEqual(TEIRendition.cascade("css:font-size=3em", "css:font-size=150%"), "css:font-size=3em")
    XCTAssertEqual(TEIRendition.cascade("css:font-size=10px", "css:font-size=0.8em"), "css:font-size=8px")
    XCTAssertEqual(TEIRendition.cascade("css:font-size=10px", "css:font-size=0.7em"), "css:font-size=10px")
    XCTAssertEqual(TEIRendition.fontSize(of: "css:font-size=12px"), 0.75)
    XCTAssertEqual(TEIRendition.fontSize(of: "css:font-size=9pt"), 0.75)
    XCTAssertEqual(TEIRendition.fontSize(of: "align(center)"), 1)
    let lines = TEIRenderer.lines(in: #"<div style="font-size:0.7em"><p style="font-size:0.5em">Small</p></div>"#)
    XCTAssertEqual(lines.first?.rend, "css:font-size=0.7em")
  }

  /// A division's margin before it is its first block's, its margin after
  /// it its last block's; a block between them takes neither.
  func testDivisionBlockMarginsAtItsEdges() {
    let lines = TEIRenderer.lines(
      in: #"<div style="margin-block-start:3em;margin-block-end:1em"><head>A</head><p>B</p><p style="margin-block-end:2em">C</p></div>"#)
    XCTAssertEqual(lines.map(\.rend), ["css:margin-block-start=3em", "", "css:margin-block-end=2em"])
    let collapsed = TEIRenderer.lines(in: #"<div style="margin-block-end:3em"><p>A</p><p style="margin-block-end:2em">B</p></div>"#)
    XCTAssertEqual(collapsed.last?.rend, "css:margin-block-end=3em")
  }

  func testPrintedRuleColumnsFrameAndPhraseStyle() throws {
    let rule = TEIRenderer.lines(in: #"<p>A</p><milestone unit="section" rend="rule align(center)" style="inline-size:12em"/><p>B</p>"#)
    guard case .rule = rule[1].kind else { return XCTFail("no rule") }
    XCTAssertEqual(rule[1].rend, "rule align(center) css:inline-size=12em")
    let note = TEIRenderer.lines(
      in: #"<note place="foot" rend="align(justify)" style="font-size:0.5em;column-gap:2em;margin-inline-start:1em"><cb/>One<lb/><cb/>Two</note>"#)
    XCTAssertEqual(note.map(\.column), [1, 2])
    XCTAssertEqual(TEIRendition.columnGap(of: note[0].columnRend), "1em")
    XCTAssertEqual(TEIRendition.columnMargins(of: note[0].columnRend), "padding-inline-start:0.5em;")
    XCTAssertEqual(TEIRendition.inColumns(note[0].rend, of: note[0].columnRend), "align(justify) css:font-size=0.5em css:column-gap=2em")
    let framed = TEIRenderer.lines(
      in: #"<note type="provenance" style="border-style:solid;padding:1em;inline-size:20em;margin-inline-start:8em"><p rend="color(blue)" style="font-size:0.5em">Gift</p></note>"#)
    XCTAssertEqual(framed[0].frame, "css:border-style=solid css:padding=1em css:inline-size=20em css:margin-inline-start=8em")
    XCTAssertEqual(framed[0].rend, "color(blue) css:font-size=0.5em")
    let leader = TEIRenderer.lines(in: #"<p style="letter-spacing:0.05em">Title <pc style="word-spacing:2.5em">. . .</pc></p>"#)
    XCTAssertEqual(leader[0].rend, "css:letter-spacing=0.05em")
    XCTAssertEqual(leader[0].runs.last?.rend, "css:word-spacing=2.5em")
  }

  /// A paragraph run on across a page break (`<p part="I|M|F">`): every
  /// line of it knows its part; a paragraph whole on its page has none.
  func testParagraphPartAcrossAPageBreak() {
    let lines = TEIRenderer.lines(in: #"<p>Whole<lb/>here.</p><p part="I">Runs<lb/>on</p>"#)
    XCTAssertEqual(lines.map(\.part), ["", "", "I", "I"])
  }
}
