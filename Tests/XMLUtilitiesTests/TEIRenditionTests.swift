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
  /// Old-style or lining figures, as the print sets its numerals.
  func testNumeralsTakeOldStyleOrLiningFigures() {
    XCTAssertTrue(TEIRendition.valid(property: "font-variant-numeric", value: "oldstyle-nums"))
    XCTAssertTrue(TEIRendition.valid(property: "font-variant-numeric", value: "lining-nums"))
    XCTAssertFalse(TEIRendition.valid(property: "font-variant-numeric", value: "tabular-nums"))
    // A note over the frame's empty part keeps its measured, negative white.
    XCTAssertTrue(TEIRendition.valid(property: "margin-block-end", value: "-14.5em"))
    XCTAssertFalse(TEIRendition.valid(property: "padding", value: "-1em"))
    XCTAssertEqual(
      TEIRendition.css(from: TEIRendition.tokens("font-variant-numeric:oldstyle-nums")),
      "font-variant-numeric:oldstyle-nums;")
  }

  /// The work frame's rendition keeps its body type in the scans' pixels
  /// and its lengths in that em, whatever a page's text may write.
  func testTheWorkFrameKeepsItsBodyTypeAndMargin() {
    let frame = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, margin: 4.07)
    let rendition = TEIRendition.frameRendition(frame)
    XCTAssertEqual(
      rendition,
      #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:44.78px;inline-size:54.8em;block-size:64.86em;margin:4.07em</rendition>"#)
    let document = "<TEI><teiHeader><encodingDesc><tagsDecl>" + rendition
      + "</tagsDecl></encodingDesc></teiHeader><text><body><pb n=\"1\" facs=\"https://example.org/a.jpg\"/><p>A</p></body></text></TEI>"
    let read = try! XCTUnwrap(TEIRenderer.pages(in: document).first).renditions
    XCTAssertEqual(TEIRendition.frame(in: read), frame)
    XCTAssertTrue(TEIRendition.header(read).contains(">font-size:44.78px;inline-size:54.8em;block-size:64.86em;margin:4.07em<"))
    // The scans' width in that em, where it is declared (the book's one em).
    let wide = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, margin: 4.07, width: 61.45)
    XCTAssertTrue(TEIRendition.frameRendition(wide).hasSuffix("margin:4.07em;max-inline-size:61.45em</rendition>"))
    let wideDocument = "<TEI><teiHeader><encodingDesc><tagsDecl>" + TEIRendition.frameRendition(wide)
      + "</tagsDecl></encodingDesc></teiHeader><text><body><pb n=\"1\" facs=\"https://example.org/a.jpg\"/><p>A</p></body></text></TEI>"
    let wideRead = try! XCTUnwrap(TEIRenderer.pages(in: wideDocument).first).renditions
    XCTAssertEqual(TEIRendition.frame(in: wideRead), wide)
    // Without its body type, no frame.
    XCTAssertNil(TEIRendition.frame(in: [TEIRendition.frameID: "css:inline-size=35.2em css:block-size=44.72em"]))
  }

  func testDivisionStyleCascadesToItsParagraphs() {
    let lines = TEIRenderer.lines(
      in: #"<div style="font-size:0.75em;line-height:1.35;margin-inline-start:2em;text-indent:2em"><p rend="align(justify)">One<lb/>two</p><p style="font-size:0.8em;margin-inline-start:1em">Three</p></div>"#)
    XCTAssertEqual(lines[0].rend, "css:font-size=0.75em css:line-height=1.35 css:margin-inline-start=2em css:text-indent=2em align(justify)")
    XCTAssertEqual(lines[1].rend, lines[0].rend)
    // em counts the paragraph's own font, 0.8 of the division's: the
    // division's 2em margin and indent are 2.5 of its em.
    XCTAssertEqual(lines[2].rend, "css:font-size=0.6em css:line-height=1.35 css:margin-inline-start=3.5em css:text-indent=2.5em")
  }

  /// A witness's type scale (gnorium-python `type_scale`): steps in rem,
  /// the body type, declared in the header and referenced by `@rendition`.
  /// A step is one size wherever it stands: inside a block set at 0.8em, a
  /// 1.2rem paragraph is 1.5 of its em and computes to 1.2em of the page,
  /// its 1.8rem leading and 0.6rem indent counted in its own font.
  func testScaleStepsInRemAreTheBodyTypeWhereverTheyStand() throws {
    XCTAssertTrue(TEIRendition.valid(property: "line-height", value: "1.8rem"))
    XCTAssertFalse(TEIRendition.valid(property: "line-height", value: "13rem"))
    let header = ##"<teiHeader><encodingDesc><tagsDecl><rendition xml:id="size-1" scheme="css">font-size:1.2rem</rendition><rendition xml:id="leading-1" scheme="css">line-height:1.8rem</rendition><rendition xml:id="indent-1" scheme="css">text-indent:0.6rem</rendition></tagsDecl></encodingDesc></teiHeader>"##
    let xml = ##"<TEI>"## + header + ##"<text><body><pb n="1" facs="https://example.org/page/full/max/0/default.jpg"/><div style="font-size:0.8em"><p rendition="#size-1 #leading-1 #indent-1">Step<lb/></p></div><p rendition="#size-1">Top<lb/></p></body></text></TEI>"##
    let page = try XCTUnwrap(TEIRenderer.pages(in: xml).first)
    XCTAssertEqual(page.lines.map(\.rend), [
      "css:font-size=1.2em css:line-height=1.5em css:text-indent=0.5em", "css:font-size=1.2em",
    ])
    XCTAssertTrue(TEIRendition.header(page.renditions).contains(##"<rendition xml:id="leading-1" scheme="css">line-height:1.8rem;</rendition>"##))
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

  /// The witness's renditions joined over a header's and its pages'
  /// (gnorium-python `type_scale.joined`, the reference): its
  /// `test_joined_is_the_header_xml_utilities_pins_for_the_skeat_pages`
  /// reads the same expected headers, written by Python from these pages.
  func testJoinedRenditionsMatchPythonForTheSkeatPages() throws {
    func fixture(_ name: String) throws -> String {
      let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures/skeat"))
      return try String(contentsOf: url, encoding: .utf8)
    }
    let pages = try (1...10).map { try TEIRendition.renditions(of: fixture("canvas-\($0)")) }
    XCTAssertTrue(pages.allSatisfy { $0.contains(#"xml:id="gap-16""#) })
    XCTAssertEqual(TEIRendition.joined([""] + pages), try fixture("joined-blank"))
    let standing = try fixture("standing").trimmingCharacters(in: .whitespacesAndNewlines)
    let joined = TEIRendition.joined([standing] + pages)
    XCTAssertEqual(joined, try fixture("joined-standing"))
    // The standing frame and size-1 are kept; its size-7 and gap-5 stay
    // beside the pages' steps; what is no step goes.
    XCTAssertTrue(joined.hasPrefix(#"<rendition xml:id="text-block" scheme="css" selector="text">font-size:46.10px;"#))
    XCTAssertTrue(joined.contains("font-size:0.83rem") && joined.contains(#"xml:id="size-7""#) && joined.contains(#"xml:id="gap-5""#))
    XCTAssertFalse(joined.contains(#"xml:id="title""#) || joined.contains("gap-0"))
    // A page's header written again as Python heads it (`with_renditions`).
    let page = try fixture("canvas-5")
    XCTAssertEqual(TEIRendition.declaring(TEIRendition.renditions(of: page), in: page), page)
    XCTAssertEqual(TEIRendition.declaring(pages[4], in: TEIRendition.declaring("", in: page)), page)
  }

  /// A page's renditions joined into a document's header: added where it
  /// declares none, the document's kept where it does, and the document
  /// as it was when the page adds nothing.
  func testAPageRenditionsJoinTheDocumentHeader() {
    let frame = #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:45.89px;inline-size:54.54em;block-size:75.62em;margin:3.99em</rendition>"#
    let size = #"<rendition xml:id="size-1" scheme="css">font-size:0.8251rem</rendition>"#
    let document = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>T</title></titleStmt></fileDesc><encodingDesc><p>Joined.</p></encodingDesc></teiHeader><text><body><p>A</p></body></text></TEI>"#
    let joined = TEIRendition.joining(frame + size, into: document)
    XCTAssertEqual(TEIRendition.renditions(of: joined), frame + size)
    XCTAssertTrue(joined.contains("<encodingDesc><tagsDecl>" + frame + size + "</tagsDecl><p>Joined.</p>"))
    XCTAssertEqual(TEIRendition.joining(size, into: joined), joined)
    XCTAssertEqual(TEIRendition.joining("", into: document), document)
    let other = #"<rendition xml:id="size-1" scheme="css">font-size:0.9rem</rendition><rendition xml:id="gap-1" scheme="css">margin-block-start:0.7845rem</rendition>"#
    XCTAssertEqual(
      TEIRendition.renditions(of: TEIRendition.joining(other, into: joined)),
      frame + size + #"<rendition xml:id="gap-1" scheme="css">margin-block-start:0.7845rem</rendition>"#)
    // A document with no header is given one.
    XCTAssertEqual(
      TEIRendition.joining(size, into: "<TEI><text/></TEI>"),
      "<TEI><teiHeader><encodingDesc><tagsDecl>" + size + "</tagsDecl></encodingDesc></teiHeader><text/></TEI>")
  }
}
