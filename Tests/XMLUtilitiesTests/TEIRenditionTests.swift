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
    let frame = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, head: 4.07, foot: 4.07, inner: 4.07, outer: 4.07)
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
    let wide = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, head: 4.07, foot: 4.07, inner: 4.07, outer: 4.07, width: 61.45)
    XCTAssertTrue(TEIRendition.frameRendition(wide).hasSuffix("margin:4.07em;max-inline-size:61.45em</rendition>"))
    // The leaf's four margins (user, 2026-10-28), a recto's: head, right (its
    // outer), foot, left (its inner), as gnorium-python declares them, read back.
    let leaf = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, head: 7.3, foot: 11.5, inner: 10.4, outer: 12.7)
    let declared = TEIRendition.frameRendition(leaf)
    XCTAssertTrue(declared.contains("margin:7.3em 12.7em 11.5em 10.4em<"))
    let fourSided = "<TEI><teiHeader><encodingDesc><tagsDecl>" + declared
      + "</tagsDecl></encodingDesc></teiHeader><text><body><pb n=\"1\" facs=\"https://example.org/a.jpg\"/><p>A</p></body></text></TEI>"
    let leafRead = try! XCTUnwrap(TEIRenderer.pages(in: fourSided).first).renditions
    XCTAssertEqual(TEIRendition.frame(in: leafRead), leaf)
    XCTAssertTrue(TEIRendition.header(leafRead).contains(";margin:7.3em 12.7em 11.5em 10.4em<"))
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
      in: #"<note type="binding" subtype="edition" style="border-style:solid;padding:1em;inline-size:20em;margin-inline-start:8em"><p rend="color(blue)" style="font-size:0.5em">Gift</p></note>"#)
    XCTAssertEqual(framed[0].frame, "css:border-style=solid css:padding=1em css:inline-size=20em css:margin-inline-start=8em")
    XCTAssertEqual(framed[0].rend, "color(blue) css:font-size=0.5em")
    // A run of lines on a ground of its own (user, 2026-10-25: a shaded
    // box, gnorium-python `base_tei.fills`): its rendition's
    // `background-color` and its inset frame its lines, drawn as encoded;
    // a color that is no "#rrggbb" is none, and the run after it is no
    // part of it.
    let filled = TEIRenderer.lines(
      in: ##"<TEI><teiHeader><encodingDesc><tagsDecl><rendition xml:id="fill-d7e4f3" scheme="css">background-color:#D7E4F3</rendition></tagsDecl></encodingDesc></teiHeader><text><body><ab rendition="#fill-d7e4f3" rend="color(red)" style="padding:1em"><lb/>Boxed<lb/>lines</ab><ab><lb/>After</ab><ab style="background-color:blue"><lb/>Plain</ab></body></text></TEI>"##)
    XCTAssertEqual(filled.map(\.text), ["Boxed", "lines", "After", "Plain"])
    XCTAssertEqual(filled[0].frame, "css:background-color=#d7e4f3 css:padding=1em")
    XCTAssertEqual(filled[1].frame, filled[0].frame)
    XCTAssertEqual(filled[2].frame, "")
    XCTAssertEqual(filled[3].frame, "")
    // The page's own pair on its <pb> (its ground, its default ink) is the
    // theme's: no frame and no color on any line.
    let cover = TEIRenderer.lines(
      in: ##"<TEI><teiHeader><encodingDesc><tagsDecl><rendition xml:id="ground-1c2230" scheme="css">background-color:#1c2230</rendition><rendition xml:id="ink-cfb784" scheme="css">color:#cfb784</rendition></tagsDecl></encodingDesc></teiHeader><text><body><pb n="Front cover" rendition="#ground-1c2230 #ink-cfb784"/><lb/>HAMLET</body></text></TEI>"##)
    XCTAssertTrue(cover.allSatisfy { $0.frame.isEmpty && !$0.rend.contains("color") })
    XCTAssertTrue(TEIRendition.frames("css:background-color=#d7e4f3"))
    XCTAssertFalse(TEIRendition.valid(property: "background-color", value: "#d7e4f"))
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
    // A page's header written again, formatted one element per line.
    let page = try fixture("canvas-5")
    let redeclared = TEIRendition.declaring(TEIRendition.renditions(of: page), in: page)
    XCTAssertEqual(TEIRendition.renditions(of: redeclared), pages[4])
    XCTAssertEqual(TEIRendition.declaring(pages[4], in: TEIRendition.declaring("", in: page)), redeclared)
    XCTAssertTrue(
      redeclared.hasPrefix(
        """
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader>
          <encodingDesc>
            <tagsDecl>
              <rendition xml:id="text-block"
        """))
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
    XCTAssertTrue(
      joined.contains(
        """
        <encodingDesc>
            <tagsDecl>
              \(frame)
              \(size)
            </tagsDecl><p>Joined.</p></encodingDesc>
        """))
    XCTAssertEqual(TEIRendition.joining(size, into: joined), joined)
    XCTAssertEqual(TEIRendition.joining("", into: document), document)
    let other = #"<rendition xml:id="size-1" scheme="css">font-size:0.9rem</rendition><rendition xml:id="gap-1" scheme="css">margin-block-start:0.7845rem</rendition>"#
    XCTAssertEqual(
      TEIRendition.renditions(of: TEIRendition.joining(other, into: joined)),
      frame + size + #"<rendition xml:id="gap-1" scheme="css">margin-block-start:0.7845rem</rendition>"#)
    // A document with no header is given one, formatted one element per line.
    XCTAssertEqual(
      TEIRendition.joining(size, into: "<TEI><text/></TEI>"),
      """
      <TEI><teiHeader>
        <encodingDesc>
          <tagsDecl>
            \(size)
          </tagsDecl>
        </encodingDesc>
      </teiHeader><text/></TEI>
      """)
    // Indented consistently with an explicated document's header, and
    // `TEIRendition.header(_:)` formatted one element per line.
    let explicated = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader>
          <fileDesc>
            <titleStmt>
              <title>T</title>
            </titleStmt>
          </fileDesc>
        </teiHeader>
        <text/>
      </TEI>
      """
    XCTAssertEqual(
      TEIRendition.declaring(frame + size, in: explicated),
      """
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader>
          <fileDesc>
            <titleStmt>
              <title>T</title>
            </titleStmt>
          </fileDesc>
          <encodingDesc>
            <tagsDecl>
              \(frame)
              \(size)
            </tagsDecl>
          </encodingDesc>
        </teiHeader>
        <text/>
      </TEI>
      """)
    XCTAssertEqual(
      TEIRendition.header(TEIRendition.declarations(of: "<tagsDecl>" + size + "</tagsDecl>")),
      """
      <teiHeader>
        <encodingDesc>
          <tagsDecl>
            <rendition xml:id="size-1" scheme="css">font-size:0.8251rem;</rendition>
          </tagsDecl>
        </encodingDesc>
      </teiHeader>
      """)
  }

  /// A page encoded under its own scale, laid into a document whose header
  /// numbers the witness's steps otherwise (a halftone's): each of its
  /// references names a rendition that declares what it was encoded with—
  /// the document's alike, else a new id—and its placement renditions
  /// (no step) join the header.
  func testAPageKeepsItsOwnSettingInADocumentNumberingOtherwise() {
    let document = #"<rendition xml:id="size-1" scheme="css">font-size:0.62rem</rendition><rendition xml:id="size-2" scheme="css">font-size:1rem</rendition><rendition xml:id="indent-1" scheme="css">text-indent:1.3373rem</rendition>"#
    let page = #"<rendition xml:id="size-2" scheme="css">font-size:0.62rem</rendition><rendition xml:id="size-3" scheme="css">font-size:1rem</rendition><rendition xml:id="indent-1" scheme="css">text-indent:1.5456rem</rendition><rendition xml:id="fw-header" scheme="css">text-align:center</rendition>"#
    let fragment = ##"<ab rendition="#size-3 #indent-1">A</ab><ab rendition="#size-2">B</ab><fw rendition="#fw-header" type="header">C</fw>"##
    let reconciled = TEIRendition.reconciled(page, fragment: fragment, with: document)
    // size-2 here is the document's size-1; size-3 the document's size-2
    // only by the same value (kept: the document lacks size-3); indent-1 a
    // new step.
    XCTAssertEqual(
      reconciled.fragment,
      ##"<ab rendition="#size-3 #indent-2">A</ab><ab rendition="#size-1">B</ab><fw rendition="#fw-header" type="header">C</fw>"##)
    XCTAssertTrue(reconciled.renditions.contains(#"<rendition xml:id="indent-2" scheme="css">text-indent:1.5456rem</rendition>"#))
    XCTAssertFalse(reconciled.renditions.contains(#"xml:id="size-2""#))
    let laid = TEIRendition.joining(
      reconciled.renditions, into: "<TEI><teiHeader><encodingDesc><tagsDecl>" + document + "</tagsDecl></encodingDesc></teiHeader><text/></TEI>")
    let declared = TEIRendition.declarations(of: laid)
    XCTAssertEqual(declared["fw-header"], "css:text-align=center")
    XCTAssertEqual(declared["indent-2"], "css:text-indent=1.5456rem")
    XCTAssertEqual(declared["size-2"], "css:font-size=1rem")
  }

  /// The witness's own typeface (user, 2026-10-28): the frame declares its
  /// family, one quoted name, which reads back as the frame's and is written
  /// again; a stack, a generic, a URL or a bare name is no rendition.
  func testTheFrameDeclaresTheWitnessTypefaceFamilyAlone() throws {
    XCTAssertTrue(TEIRendition.valid(property: "font-family", value: "\"Hamlet Q1 1603\""))
    XCTAssertTrue(TEIRendition.valid(property: "font-family", value: "\"A-Book\""))
    XCTAssertFalse(TEIRendition.valid(property: "font-family", value: "Hamlet Q1 1603"))
    XCTAssertFalse(TEIRendition.valid(property: "font-family", value: "\"Hamlet\", serif"))
    XCTAssertFalse(TEIRendition.valid(property: "font-family", value: "serif"))
    XCTAssertFalse(TEIRendition.valid(property: "font-family", value: "\"url(x)\""))
    let frame = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, head: 4.07, foot: 4.07, inner: 4.07, outer: 4.07, family: "Hamlet Q1 1603")
    let rendition = TEIRendition.frameRendition(frame)
    XCTAssertTrue(rendition.hasSuffix(#"margin:4.07em;font-family:"Hamlet Q1 1603"</rendition>"#), rendition)
    let read = TEIRendition.declarations(of: "<teiHeader><encodingDesc><tagsDecl>" + rendition + "</tagsDecl></encodingDesc></teiHeader>")
    XCTAssertEqual(TEIRendition.frame(in: read), frame)
    // Written again from the frame read, its quotes escaped as an element's text is.
    XCTAssertTrue(TEIRendition.header(read).contains(";font-family:&quot;Hamlet Q1 1603&quot;<"), TEIRendition.header(read))
    // A frame without one declares none, and reads back with none.
    let plain = TEIWorkFrame(body: 44.78, measure: 54.8, height: 64.86, head: 4.07, foot: 4.07, inner: 4.07, outer: 4.07)
    XCTAssertFalse(TEIRendition.frameRendition(plain).contains("font-family"))
    XCTAssertEqual(TEIRendition.frame(in: TEIRendition.declarations(of: TEIRendition.frameRendition(plain)))?.family, "")
  }
}
