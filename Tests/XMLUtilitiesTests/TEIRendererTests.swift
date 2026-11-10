import XCTest
import XMLUtilities

final class TEIRendererTests: XCTestCase {
  /// A document's language is what its own data says: its text's
  /// xml:lang, else its header's langUsage; never its letters.
  func testADocumentsLanguageIsWhatItsDataSays() {
    XCTAssertEqual(TEIRenderer.language(in: #"<TEI><text xml:lang="heb"><body/></text></TEI>"#), "heb")
    XCTAssertEqual(
      TEIRenderer.language(
        in: #"<TEI><teiHeader><profileDesc><textClass/><langUsage><language ident="ara"/></langUsage></profileDesc></teiHeader><text><body/></text></TEI>"#),
      "ara")
    XCTAssertEqual(
      TEIRenderer.language(
        in: #"<TEI><teiHeader><langUsage><language ident="ara"/></langUsage></teiHeader><text xml:lang="san-Latn"/></TEI>"#),
      "san-Latn")
    XCTAssertNil(TEIRenderer.language(in: "<TEI><text><body><p>שלום</p></body></text></TEI>"))
  }

  /// A translation's runs carry the source block they translate, as its
  /// segment names it: the block's `@corresp`, never a phrase's.
  func testATranslationsRunsNameTheirSegment() throws {
    let translation = #"""
      <TEI><text><body><pb n="1" facs="https://example.org/1.jpg" corresp="#p1.e1"/>
      <head corresp="#p1.e2">A <hi corresp="#p1.e3">title</hi></head>
      <p corresp="#p1.e4"><s corresp="#p1.e5"><w corresp="#p1.e6">First</w> one.</s> <s corresp="#p1.e7">Second.</s></p>
      </body></text></TEI>
      """#
    let page = try XCTUnwrap(TEIRenderer.pages(in: translation).first)
    let runs = page.lines.flatMap(\.runs).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    XCTAssertEqual(runs.map(\.segment), ["#p1.e2", "#p1.e2", "#p1.e5", "#p1.e5", "#p1.e7"])
  }

  /// A segment's pointer is the one its block's clone carries in the
  /// translation: what a translator's note is kept and found by.
  func testASegmentsPointerIsItsClonesCorresp() throws {
    let source = #"<TEI><text><body><pb n="1" facs="https://example.org/iiif/pg1/full/max/0/default.jpg"/><head>Libro</head><p><s>Regola</s> <s xml:id="due">Due</s></p></body></text></TEI>"#
    let parallel = TEIParallel(source: source)
    let segments = try XCTUnwrap(parallel.pages.first).segments
    XCTAssertEqual(segments.map(\.pointer), ["#pg1.e2", "#pg1.e4", "#due"])
    let translated = try parallel.translatedPage(0, texts: ["s1": "Book", "s2": "Rule", "s3": "Two"])
    for segment in segments { XCTAssertTrue(translated.contains("corresp=\"\(segment.pointer)\""), segment.pointer) }
    // Rendered, each run names its block by the same pointer.
    let rendered = try XCTUnwrap(
      TEIRenderer.pages(in: "<TEI><text><body>" + translated + "</body></text></TEI>").first)
    let named = Set(rendered.lines.flatMap(\.runs).filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.segment))
    XCTAssertEqual(named, Set(segments.map(\.pointer)))
  }

  func testPagesIncludeTitlePagesAndBackMatter() {
    let document = """
      <TEI><text xml:lang="eng"><front><pb n="title" facs="https://example.org/title.jpg"/>
      <titlePage><docTitle><titlePart><bibl><title><w>Letters</w></title></bibl><lb/></titlePart></docTitle></titlePage></front>
      <body><pb n="1" facs="https://example.org/1.jpg"/><p><w>Begins</w><lb/></p></body>
      <back><pb n="end" facs="https://example.org/end.jpg"/><div><p><w>End</w><lb/></p></div></back></text></TEI>
      """
    let pages = TEIRenderer.pages(in: document)
    XCTAssertEqual(pages.map(\.label), ["title", "1", "end"])
    XCTAssertTrue(pages[0].markup.contains("Letters"))
    XCTAssertTrue(pages[2].markup.contains("End"))
  }

  func testAnEditBreaksMarkupOnlyWhereItChangedTheBalance() {
    let page = "<div><p>To be,<lb/>or not</p>"
    XCTAssertFalse(TEIRenderer.breaksMarkup("<div><p>To be,<lb/>or not to be</p>", from: page))
    XCTAssertTrue(TEIRenderer.breaksMarkup("<div><p>To be,<lb/>or not", from: page))
    XCTAssertTrue(TEIRenderer.breaksMarkup("<div><p>To be,<lb/>or <hi rend=\"it\" not</p>", from: page))
    XCTAssertEqual(XMLFormatter.escapingAttribute("a&b \"c\""), "a&amp;b &quot;c&quot;")
  }

  func testLineBreaksAndBlocksAreToldApart() {
    let lines = TEIRenderer.lines(in: "<p>To be,<lb/>or not</p><p>That is</p><l>the question</l>")
    XCTAssertEqual(lines.map(\.text), ["To be,", "or not", "That is", "the question"])
    XCTAssertEqual(lines.map(\.opensBlock), [true, false, true, true])
  }

  /// The MathML the page keeps for a formula (gnorium-python recognition `formulas.py`).
  static let math = #"<math xmlns="http://www.w3.org/1998/Math/MathML" display="inline">"#

  func testAFormulaIsDrawnAsItsMathMLAndReadAsItsSymbols() {
    let lines = TEIRenderer.lines(
      in: #"<p>Let <formula notation="mathml">"# + Self.math
        + #"<semantics><mrow><mi>x</mi><mo>=</mo><mfrac><mi>a</mi><mi>b</mi></mfrac></mrow>"#
        + #"<annotation encoding="application/x-tex">x=\frac{a}{b}</annotation></semantics></math></formula> hold.</p>"#)
    XCTAssertEqual(lines.count, 1)
    XCTAssertEqual(lines[0].runs.map(\.text), ["Let ", "x=ab", " hold."])
    guard case .math(let formula) = lines[0].runs[1].kind else { return XCTFail("Lost the formula") }
    XCTAssertFalse(formula.display)
    XCTAssertEqual(formula.source, #"x=\frac{a}{b}"#)
    guard case .element(name: "mrow", _, let children) = formula.content.first else {
      return XCTFail("The formula draws its semantics' first child")
    }
    XCTAssertEqual(formula.content.count, 1)
    XCTAssertEqual(children.count, 3)
    guard case .token(name: "mo", _, let runs) = children[1] else { return XCTFail("Lost the operator") }
    XCTAssertEqual(runs.map(\.text), ["="])
  }

  /// Only MathML Core's elements and presentation attributes are drawn: any
  /// other element reads as an mrow, any other attribute is dropped.
  func testAFormulaDrawsOnlyMathMLCore() {
    let lines = TEIRenderer.lines(
      in: #"<p><formula notation="mathml"><math xmlns="http://www.w3.org/1998/Math/MathML" display="block">"#
        + #"<semantics><maction onclick="x()" href="https://example.org"><mi mathvariant="normal" style="color:red">H</mi>"#
        + #"</maction><annotation encoding="application/x-tex">\mathrm{H}</annotation></semantics></math></formula></p>"#)
    guard case .math(let formula) = lines[0].runs[0].kind else { return XCTFail("Lost the formula") }
    XCTAssertTrue(formula.display)
    guard case .element(name: "mrow", let attributes, let children) = formula.content.first,
      case .token(name: "mi", let tokenAttributes, _) = children.first
    else { return XCTFail("An unknown element reads as an mrow") }
    XCTAssertTrue(attributes.isEmpty)
    XCTAssertEqual(tokenAttributes.map(\.name), ["mathvariant"])
  }

  /// Read word by word, each symbol is its word, as an anchor counts it.
  func testAFormulasSymbolsAreItsWords() {
    let lines = TEIRenderer.lines(
      in: #"<p>so <formula notation="mathml">"# + Self.math
        + #"<semantics><mrow><mi>sin</mi><mo>\#u{2061}</mo><mi>x</mi></mrow>"#
        + #"<annotation encoding="application/x-tex">\sin x</annotation></semantics></math></formula></p>"#,
      marksWords: true)
    let formulas = lines[0].runs.compactMap { run -> TEIMath? in
      if case .math(let formula) = run.kind { return formula }
      return nil
    }
    guard let formula = formulas.first, case .element(_, _, let children) = formula.content.first
    else { return XCTFail("Lost the formula") }
    let places = children.map { child -> String in
      guard case .token(_, _, let runs) = child else { return "?" }
      return runs.map { $0.word.map { "\($0.line).\($0.word)" } ?? "-" }.joined()
    }
    XCTAssertEqual(places, ["1.2", "-", "1.3"])
  }

  func testNonTeXFormulaKeepsExistingInlineMarkup() {
    let line = TEIRenderer.lines(
      in: #"<p><formula notation="none">P<hi rend="subscript">d</hi></formula></p>"#)[0]
    XCTAssertEqual(line.text, "Pd")
    XCTAssertEqual(line.runs[1].rend, "subscript")
    guard case .text = line.runs[1].kind else { return XCTFail("Unexpected TeX conversion") }
  }

  func testTablesPreserveSpansBlankCellsAndNestedReadings() throws {
    let lines = TEIRenderer.lines(
      in: """
        <p>Before</p><table><head>Probabilities</head>
        <row role="label"><cell rows="2">N<hi rend="subscript">s</hi></cell><cell cols="2">P</cell></row>
        <row><cell/><cell>2<hi rend="underline">1</hi>10<lb/>next</cell></row>
        </table><p>After</p>
        """)
    XCTAssertEqual(lines.count, 3)
    XCTAssertEqual(lines.first?.text, "Before")
    XCTAssertEqual(lines.last?.text, "After")
    guard case .table(let table) = lines[1].kind else { return XCTFail("Missing table") }
    XCTAssertEqual(table.caption.map(\.text), ["Probabilities"])
    XCTAssertEqual(table.rows.map { $0.cells.count }, [2, 2])
    XCTAssertEqual(table.rows[0].cells[0].rows, 2)
    XCTAssertEqual(table.rows[0].cells[1].columns, 2)
    XCTAssertTrue(table.rows[0].cells.allSatisfy(\.isLabel))
    XCTAssertTrue(table.rows[1].cells[0].lines.isEmpty)
    let content = table.rows[1].cells[1].lines
    XCTAssertEqual(content.map(\.text), ["2110", "next"])
    XCTAssertEqual(content[0].runs.filter { $0.rend == "underline" }.map(\.text), ["1"])
  }

  func testNestedEmphasisRestoresParentAndSurvivesLineBreaks() {
    let lines = TEIRenderer.lines(
      in: "<p><hi rend=\"underline\">P<hi rend=\"subscript\">d</hi> + N<lb/>next</hi> plain</p>")
    XCTAssertEqual(lines.map(\.text), ["Pd + N", "next plain"])
    XCTAssertEqual(lines[0].runs.map(\.rend), ["underline", "underline subscript", "underline"])
    XCTAssertEqual(lines[1].runs.map(\.rend), ["underline", ""])
  }

  func testHeadingAndFurnitureRetainInlineSettingOnEveryLine() {
    let lines = TEIRenderer.lines(
      in:
        "<head><hi rend=\"italic\">first<lb/>second</hi></head><fw type=\"header\"><hi rend=\"smallcaps\">header</hi></fw>"
    )
    for line in lines.prefix(2) {
      guard case .heading = line.kind else { return XCTFail("Lost heading across lb") }
      XCTAssertEqual(line.runs.first?.rend, "italic")
    }
    guard case .forme(.header) = lines.last?.kind else { return XCTFail("Lost furniture") }
    XCTAssertEqual(lines.last?.runs.first?.rend, "smallcaps")
  }

  /// A page's own facsimile: one surface over the 0–1000 space with zones,
  /// as the recognition commits a page (gnorium-python `encode_zones`).
  static let facsimile =
    #"<facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"#
    + #"<zone xml:id="z1" ulx="10" uly="20" lrx="40" lry="60"/><zone xml:id="z2" ulx="40" uly="60" lrx="160" lry="210"/>"#
    + "</surface></facsimile>"

  func testTableInsideFigureIsNotSwallowedByDescription() {
    let lines = TEIRenderer.lines(
      in: Self.facsimile
        + "<figure facs=\"#z1\"><figDesc>Device</figDesc><head>Original caption</head><table><row><cell>OXOX</cell></row></table></figure>"
    )
    XCTAssertEqual(lines.map(\.text), ["Device", "Original caption", "OXOX"])
    guard case .figure(_, let zone, let graphic) = lines[0].kind else { return XCTFail("Missing crop") }
    XCTAssertEqual(zone?.corners, "10 20 40 60")
    XCTAssertNil(graphic)
    guard case .table = lines[2].kind else { return XCTFail("Missing figure table") }
  }

  /// A figure's drawing is its SVG graphic (its inks traced when its page was
  /// calibrated); a graphic of another type, a photograph, is not one.
  func testFigureCarriesItsSVGGraphicAsItsDrawing() {
    let lines = TEIRenderer.lines(
      in: Self.facsimile
        + "<figure facs=\"#z1\"><graphic url=\"/calibration-figures/z1.svg?image=x\" mimeType=\"image/svg+xml\"/>"
        + "<figDesc>Device</figDesc></figure>"
        + "<figure facs=\"#z2\"><graphic url=\"/photo.jpg\" mimeType=\"image/jpeg\"/></figure>"
    )
    guard case .figure(_, _, let drawing) = lines[0].kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(drawing, "/calibration-figures/z1.svg?image=x")
    XCTAssertEqual(lines[0].text, "Device")
    guard case .figure(_, _, let photograph) = lines[1].kind else { return XCTFail("Missing figure") }
    XCTAssertNil(photograph)
  }

  /// A drawing read from its SVG keeps its size and each path's outline,
  /// fill and ink, and nothing else: no other element, no handler; it is
  /// served written again from those alone.
  func testDrawingReadsItsPathsAndNothingElse() throws {
    let drawing = try XCTUnwrap(
      TEIDrawing(
        svg: #"<svg xmlns="http://www.w3.org/2000/svg" width="258" height="332" viewBox="0 0 258 332" onload="x()">"#
          + #"<path fill="currentColor" fill-rule="evenodd" d="M1,2L3,4Z"/>"#
          + #"<script>alert(1)</script><path class="ink-red" fill="currentColor" d="M5,6Z" onclick="y()"/></svg>"#))
    XCTAssertEqual(drawing.width, "258")
    XCTAssertEqual(drawing.height, "332")
    XCTAssertEqual(drawing.viewBox, "0 0 258 332")
    XCTAssertEqual(
      drawing.paths,
      [
        .init(ink: "", fill: "currentColor", fillRule: "evenodd", d: "M1,2L3,4Z"),
        .init(ink: "ink-red", fill: "currentColor", fillRule: "", d: "M5,6Z"),
      ])
    // Served as the reader references it: its paths in a symbol its `<use>` names, another ink's
    // color its reader's property.
    XCTAssertEqual(
      drawing.referenced,
      #"<svg xmlns="http://www.w3.org/2000/svg" width="258" height="332" viewBox="0 0 258 332">"#
        + #"<symbol id="figure" viewBox="0 0 258 332" preserveAspectRatio="none">"#
        + #"<path fill="currentColor" fill-rule="evenodd" d="M1,2L3,4Z"/>"#
        + #"<path class="ink-red" style="fill:var(--tei-ink-red,currentColor)" fill="currentColor" d="M5,6Z"/>"#
        + ##"</symbol><use href="#figure" width="100%" height="100%"/></svg>"##)
    XCTAssertNil(TEIDrawing(svg: "<svg/>"))
    XCTAssertNil(TEIDrawing(svg: "not a drawing"))
  }

  /// A decorated initial is the first letter of its word, never a figure:
  /// its zone rides on the letter's run, and the letter reads with its word.
  func testADecoratedInitialIsTheFirstLetterOfItsWord() throws {
    let lines = TEIRenderer.lines(
      in: Self.facsimile + ##"<p><w lemma="when"><hi rend="initial" facs="#z2">W</hi>hen</w> in the course</p>"##,
      marksWords: true)
    XCTAssertEqual(lines.count, 1)
    guard case .text = lines[0].kind else { return XCTFail("An initial is not a figure") }
    XCTAssertEqual(lines[0].text, "When in the course")
    let letter = try XCTUnwrap(lines[0].runs.first)
    XCTAssertEqual(letter.text, "W")
    XCTAssertEqual(letter.rend, "initial")
    XCTAssertEqual(letter.zone?.corners, "40 60 160 210")
    XCTAssertEqual(lines[0].runs[1].text, "hen")
    XCTAssertNil(lines[0].runs[1].zone)
    XCTAssertNotNil(letter.word)
    XCTAssertEqual(letter.word, lines[0].runs[1].word)
    // Naming no zone, the letter alone.
    let bare = TEIRenderer.lines(in: ##"<p><w><hi rend="initial" facs="#z9">W</hi>hen</w></p>"##)
    XCTAssertEqual(bare[0].runs.map { $0.zone == nil }, [true, true])
    // A figure typed "initial" is a figure like any other: its text is read.
    let figure = TEIRenderer.lines(in: #"<figure type="initial"><head>W</head></figure>"#)
    XCTAssertEqual(figure.map(\.text), ["", "W"])
  }

  /// Hamlet Q1 p. 3 (user, 2026-11-01): the S of "1. STand: who is that?"
  /// is two lines deep; its zone covers its own line and "2. Tis I.", so it
  /// drops two lines, and the line beside it begins after it. The line
  /// below, which the zone clears, is a line of its own.
  func testAnInitialDropsThroughTheLinesItsZoneStandsBeside() throws {
    let page = """
      <facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">\
      <zone xml:id="z-L1" ulx="320" uly="444" lrx="480" lry="477"/>\
      <zone xml:id="z-L2" ulx="320" uly="461" lrx="400" lry="477"/>\
      <zone xml:id="z-L3" ulx="320" uly="478" lrx="600" lry="494"/>\
      <zone xml:id="z-fig-1" ulx="338" uly="444" lrx="352" lry="476"/></surface></facsimile>\
      <ab><lb facs="#z-L1"/>1. <w><hi rend="initial" facs="#z-fig-1">S</hi>Tand</w>: who is that?\
      <lb facs="#z-L2"/>2. <w>Tis</w> <w>I</w>.<lb facs="#z-L3"/>1. O you come</ab>
      """
    let lines = TEIRenderer.lines(in: page, marksWords: true)
    XCTAssertEqual(lines.map(\.text), ["1. STand: who is that?", "2. Tis I.", "1. O you come"])
    let initial = try XCTUnwrap(lines[0].runs.first { $0.text == "S" })
    XCTAssertEqual(initial.drop, 2)
    XCTAssertEqual(lines[0].runs.filter { $0.drop > 1 }.count, 1)
    XCTAssertNil(lines[0].hang)
    XCTAssertEqual(lines[1].hang, TEILine.Hang(letter: "S", lines: 2))
    XCTAssertNil(lines[2].hang)
    // An initial whose zone no line after it stands beside drops no line.
    let alone = TEIRenderer.lines(in: Self.facsimile + ##"<p><w><hi rend="initial" facs="#z2">W</hi>hen</w></p>"##)
    XCTAssertEqual(alone[0].runs.map(\.drop), [1, 1])
  }

  func testFigureWithoutDescriptionStillCarriesItsCrop() throws {
    let lines = TEIRenderer.lines(in: Self.facsimile + "<figure facs=\"#z1\"/>")
    XCTAssertEqual(lines.count, 1)
    guard case .figure(_, let zone, _) = lines.first?.kind else { return XCTFail("Missing figure") }
    let found = try XCTUnwrap(zone)
    XCTAssertEqual(
      TEIRenderer.regionURL(ofFacsimile: "https://example.org/iiif/a/full/1300,/0/default.jpg", zone: found),
      "https://example.org/iiif/a/pct:1,2,3,4/!600,600/0/default.jpg")
    XCTAssertEqual(
      TEIRenderer.fullResolutionRegionURL(ofFacsimile: "https://example.org/iiif/a/full/1300,/0/default.jpg", zone: found),
      "https://example.org/iiif/a/pct:1,2,3,4/full/0/default.jpg")
  }

  /// A document's zones are in its facsimile, outside the body its pages are
  /// cut from: each page carries them, and its figures and initials find
  /// theirs; an excerpt keeps them.
  func testADocumentsPagesFindTheirZonesInItsFacsimile() throws {
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/>
      <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="https://example.org/iiif/a/full/1300,/0/default.jpg"/>\
      <zone xml:id="p1-z1" ulx="100" uly="200" lrx="400" lry="600"/></surface>\
      <surface n="2" ulx="0" uly="0" lrx="500" lry="500"><zone xml:id="p2-z1" ulx="50" uly="50" lrx="100" lry="150"/></surface></facsimile>
      <text><body><pb n="1" facs="https://example.org/iiif/a/full/1300,/0/default.jpg"/><figure facs="#p1-z1"><figDesc>A woodcut.</figDesc></figure>
      <pb n="2" facs="https://example.org/iiif/b/full/1300,/0/default.jpg"/><p><w><hi rend="initial" facs="#p2-z1">W</hi>hen</w></p></body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: document)
    XCTAssertEqual(pages.count, 2)
    guard case .figure(_, let zone, _) = pages[0].lines[0].kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(
      TEIRenderer.regionURL(ofFacsimile: pages[0].facsimileURL, zone: try XCTUnwrap(zone)),
      "https://example.org/iiif/a/pct:10,20,30,40/!600,600/0/default.jpg")
    // A surface of its own extent: a zone is a fraction of it.
    let initial = try XCTUnwrap(pages[1].lines[0].runs[0].zone)
    XCTAssertEqual(
      TEIRenderer.regionURL(ofFacsimile: pages[1].facsimileURL, zone: initial),
      "https://example.org/iiif/b/pct:10,10,10,20/!600,600/0/default.jpg")
    XCTAssertEqual(Set(pages[1].zones.keys), ["p1-z1", "p2-z1"])
    let excerpt = try XCTUnwrap(TEIRenderer.excerpt(of: document, around: "https://example.org/iiif/b", radius: 0))
    XCTAssertNotNil(TEIRenderer.pages(in: excerpt)[0].lines[0].runs[0].zone)
    // A page handed to the recognition carries the zones it names.
    XCTAssertEqual(
      TEIFacsimile.withZones(pages[1].markup, zones: pages[1].zones),
      #"<facsimile><surface ulx="0" uly="0" lrx="500" lry="500"><zone xml:id="p2-z1" ulx="50" uly="50" lrx="100" lry="150"/></surface></facsimile>"#
        + pages[1].markup)
    // A stored page keeps its boxes as zones: a bbox, or a zone the document
    // lacks, is a fault.
    XCTAssertFalse(TEIRenderer.faults(in: pages[1]).contains { $0.kind == .zone })
    let missing = TEIPage(label: "2", facsimileURL: pages[1].facsimileURL, lines: [], markup: ##"<figure facs="#p9-z1"/>"##)
    XCTAssertEqual(TEIRenderer.faults(in: missing).filter { $0.kind == .zone }.map(\.detail), ["#p9-z1"])
    let boxed = TEIPage(label: "2", facsimileURL: pages[1].facsimileURL, lines: [], markup: #"<figure bbox="1 2 3 4"/>"#)
    XCTAssertEqual(TEIRenderer.faults(in: boxed).filter { $0.kind == .zone }.map(\.detail), ["bbox"])
  }

  /// A page's margin is its leaf's white beside its main text block (its
  /// `type="leaf"` zone, kept with the scan's structure), never the
  /// photograph's beyond the leaf (user, 2026-10-26); the whole scan where
  /// it keeps no leaf.
  func testAPagesMarginIsItsLeafsWhiteBesideTheText() throws {
    let a = "https://example.org/iiif/a/full/1300,/0/default.jpg"
    func page(_ leaf: String) -> TEIPage? {
      TEIRenderer.pages(in: """
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000">\
        <graphic url="\(a)" width="2000px" height="1300px"/>\
        <zone xml:id="textblock" type="textblock" points="280,60 720,60 720,920 280,920" style="font-size:20px"/>\
        \(leaf)</surface></facsimile><text><body><pb n="1" facs="\(a)"/><p>Body.</p></body></text></TEI>
        """).first
    }
    // The text 880px wide on a leaf 1000px wide, a scan 2000px wide.
    let leafed = try XCTUnwrap(page(#"<zone type="leaf" points="250,0 750,0 750,1000 250,1000"/>"#)?.typeArea)
    XCTAssertEqual(leafed.measure, 44, accuracy: 0.001)
    // Its four margins (user, 2026-10-28): the head 78px, the foot 104px,
    // either side 60px, in 20px ems.
    for (margin, expected) in zip([leafed.head, leafed.foot, leafed.inner, leafed.outer], [3.9, 5.2, 3, 3]) {
      XCTAssertEqual(margin, expected, accuracy: 0.001)
    }
    let unleafed = try XCTUnwrap(page("")?.typeArea)
    for margin in [unleafed.head, unleafed.foot, unleafed.inner, unleafed.outer] { XCTAssertEqual(margin, 28, accuracy: 0.001) }
    // A leaf narrower at its left is a recto, its inner margin its left; at
    // its right, a verso, mirrored.
    let recto = try XCTUnwrap(page(#"<zone type="leaf" points="270,0 760,0 760,1000 270,1000"/>"#))
    XCTAssertEqual(try XCTUnwrap(recto.typeArea).recto, true)
    XCTAssertEqual(try XCTUnwrap(recto.typeArea).left, 1, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(recto.typeArea).right, 4, accuracy: 0.001)
    let verso = try XCTUnwrap(page(#"<zone type="leaf" points="240,0 730,0 730,1000 240,1000"/>"#))
    XCTAssertEqual(try XCTUnwrap(verso.typeArea).recto, false)
    XCTAssertEqual(try XCTUnwrap(verso.typeArea).left, 4, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(verso.typeArea).right, 1, accuracy: 0.001)
  }

  /// Every page is set in the work's type area, its body pages' main text
  /// block in their body type's em: the header's rendition where the
  /// document has one, else the page's own measured text block (its
  /// surface's `textblock` zone, sized by its graphic, its type its style),
  /// else none; laid in again, a page's text block goes with it and the
  /// type area is measured again (user, 2026-10-13, 2026-10-14).
  func testPagesAreSetInTheWorksTypeAreaMeasuredFromTheirTextBlocks() throws {
    let a = "https://example.org/iiif/a/full/1300,/0/default.jpg"
    let b = "https://example.org/iiif/b/full/1300,/0/default.jpg"
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc/><encodingDesc><p>Joined.</p></encodingDesc></teiHeader>
      <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(a)" width="1000px" height="1300px"/>\
      <zone xml:id="p1-textblock" type="textblock" points="60,60 940,60 940,920 60,920" style="font-size:20px"/></surface>\
      <surface n="2" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(b)" width="1000px" height="1300px"/>\
      <zone xml:id="p2-textblock" type="textblock" points="300,400 700,400 700,500 300,500" style="font-size:40px"/></surface></facsimile>
      <text><body><pb n="1" facs="\(a)"/><p>Body.</p>
      <pb n="2" facs="\(b)"/><p>Title.</p></body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: document)
    // No header type area yet: each page its own text block, in its own type.
    let body = try XCTUnwrap(pages[0].typeArea)
    XCTAssertEqual(body.measure, 44, accuracy: 0.001)
    XCTAssertEqual(body.height, 55.9, accuracy: 0.001)
    for margin in [body.head, body.foot, body.inner, body.outer] { XCTAssertEqual(margin, 3, accuracy: 0.001) }
    XCTAssertEqual(try XCTUnwrap(pages[1].typeArea).measure, 10, accuracy: 0.001)
    XCTAssertEqual(pages[0].textBlock?.fractions, [0.06, 0.06, 0.94, 0.06, 0.94, 0.92, 0.06, 0.92])
    XCTAssertEqual(pages[0].textBlock?.body, 20)
    // The work's type area: the body page's, the title page counting for its
    // little text; the header declares it and every page is set in it.
    let declared = TEIFacsimile.declaringTypeArea(document)
    XCTAssertTrue(declared.contains(
      #"<encodingDesc><p>Joined.</p><tagsDecl><rendition xml:id="text-block" scheme="css" selector="text">font-size:20px;inline-size:44em;block-size:55.9em;margin:3em;max-inline-size:50em</rendition></tagsDecl></encodingDesc>"#))
    for page in TEIRenderer.pages(in: declared) {
      XCTAssertEqual(page.typeArea, TEIPageTypeArea(measure: 44, height: 55.9, head: 3, foot: 3, inner: 3, outer: 3))
    }
    XCTAssertEqual(TEIFacsimile.declaringTypeArea(declared), declared)
    // A page drawn alone is handed the type area and its own text block.
    let title = TEIRenderer.pages(in: declared)[1]
    let alone = "<TEI>" + TEIRendition.header(title.renditions) + TEIFacsimile.block(for: title)
      + "<text><body><pb n=\"2\" facs=\"\(b)\"/>" + title.markup + "</body></text></TEI>"
    let drawn = try XCTUnwrap(TEIRenderer.pages(in: alone).first)
    XCTAssertEqual(drawn.textBlock?.points, [300, 400, 700, 400, 700, 500, 300, 500])
    XCTAssertEqual(drawn.textBlock?.body, 40)
    XCTAssertEqual(try XCTUnwrap(drawn.typeArea).measure, 44, accuracy: 0.001)
    // Read again with a text block of its own: laid in with it, renamed;
    // the type area the header declares stands (the first declared wins).
    let page = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/><facsimile><surface n="2" ulx="0" uly="0" lrx="1000" lry="1000">\
      <graphic url="\(b)" width="1000px" height="1300px"/><zone xml:id="textblock" type="textblock" points="50,50 950,50 950,950 50,950" style="font-size:20px"/>\
      </surface></facsimile><text><body><p>Body again.</p></body></text></TEI>
      """
    let laid = try XCTUnwrap(TEIFacsimile.laying(
      page: page, fragment: "<p>Body again.</p>", over: TEIRenderer.pages(in: declared)[1], position: 2, in: declared))
    XCTAssertTrue(laid.contains(
      #"<surface n="2" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\#(b)" width="1000px" height="1300px"/><zone xml:id="p2-textblock" type="textblock" points="50,50 950,50 950,950 50,950" style="font-size:20px"/></surface>"#))
    XCTAssertEqual(TEIFacsimile.textBlocks(in: laid).map(\.id), ["p1-textblock", "p2-textblock"])
    XCTAssertEqual(TEIRenderer.pages(in: laid).first?.typeArea, TEIPageTypeArea(measure: 44, height: 55.9, head: 3, foot: 3, inner: 3, outer: 3))
    XCTAssertEqual(laid.components(separatedBy: #"xml:id="text-block""#).count, 2)
    // Only a document declaring none takes its type area from its text blocks: two body
    // pages now.
    let undeclared = laid.replacingOccurrences(
      of: #"<tagsDecl><rendition xml:id="text-block" scheme="css" selector="text">font-size:20px;inline-size:44em;block-size:55.9em;margin:3em;max-inline-size:50em</rendition></tagsDecl>"#,
      with: "")
    XCTAssertNotEqual(undeclared, laid)
    let remeasured = try XCTUnwrap(TEIRenderer.pages(in: TEIFacsimile.declaringTypeArea(undeclared)).first?.typeArea)
    XCTAssertEqual(remeasured.measure, 45, accuracy: 0.001)
    XCTAssertEqual(remeasured.height, 58.5, accuracy: 0.001)
    for margin in [remeasured.head, remeasured.foot, remeasured.inner, remeasured.outer] { XCTAssertEqual(margin, 2.5, accuracy: 0.001) }
  }

  /// A figure with no setting of its own on a page set in a type area (user, 2026-10-30:
  /// Hamlet Q1's front cover, a board lettered in gilt, with no body type
  /// for `base_tei._figure` to write one in) is set by its zone on the
  /// page's leaf, at the type area's scale: its size, its place across from the
  /// text block's left, its place down from the text block's top or from
  /// the figure before it; a figure set already is left as it is, as is
  /// every figure of a page with main text and no type area.
  func testAFigureWithNoSettingOnAPageInATypeAreaIsSetByItsZoneOnTheLeaf() throws {
    let a = "https://example.org/iiif/a/full/1300,/0/default.jpg"
    let header = "<teiHeader><encodingDesc><tagsDecl>"
      + #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:20px;inline-size:44em;block-size:55.9em;margin:3em</rendition>"#
      + "</tagsDecl></encodingDesc></teiHeader>"
    // The leaf 800 px wide (100 to 900 of a 1000 px scan), the type area 50 em: an em is 16 px of the scan.
    let facsimile = #"<facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\#(a)" width="1000px" height="1300px"/>"#
      + #"<zone xml:id="textblock" type="textblock" points="420,240 620,240 620,440 420,440"/>"#
      + #"<zone type="leaf" points="100,80 900,80 900,920 100,920"/>"#
      + #"<zone xml:id="z1" ulx="500" uly="300" lrx="580" lry="400"/><zone xml:id="z2" ulx="100" uly="500" lrx="200" lry="600"/>"#
      + #"<zone xml:id="z3" ulx="100" uly="700" lrx="200" lry="800"/></surface></facsimile>"#
    let figures = ##"<pb n="1" facs="\##(a)"/><figure facs="#z1"/><figure facs="#z2"/>"##
      + ##"<figure facs="#z3" style="inline-size:2em;block-size:2em;margin-inline-start:1em"/>"##
    let body = "<text><body>" + figures + "</body></text>"
    // Set in the work's type area, its main text after them.
    let withText = "<text><body>" + figures + "<p>Words.</p></body></text>"
    let pages = TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + facsimile + withText + "</TEI>")
    let settings = pages[0].lines.dropLast().map { TEIRendition.css(from: $0.rend, only: TEIPage.figureSetting) }
    // z1: 80 by 100 scan px at 390 px down, 500 across: 5 by 8.125 em, 22 em from the text block's left
    // (400 px from the leaf's less the 3 em margin), 14.875 em from its top (286 px less the 3 em head).
    // z2: 130 px under z1's bottom (520 px), 8.125 em down from it. z3 keeps its own setting.
    XCTAssertEqual(
      settings,
      [
        "inline-size:5em;block-size:8.125em;margin-inline-start:22em;margin-block-start:14.875em;",
        "inline-size:6.25em;block-size:8.125em;margin-inline-start:-3em;margin-block-start:8.125em;",
        "inline-size:2em;block-size:2em;margin-inline-start:1em;",
      ])
    // No main text, no body type: set in its leaf, 38 em wide (`TEIPage.leafTypeArea`), an
    // em 800/38 px of the scan; z1 3.8 by 6.175 em, 19 em from the leaf's left, 13.585 em from its top.
    // With its work's type area in the header too (user, 2026-10-31: Hamlet Q1's cover under the integrated header):
    // a page with no type of its own is its leaf whatever its work's type area, as filed before Integration.
    let leaf = [
      "inline-size:3.8em;block-size:6.175em;margin-inline-start:19em;margin-block-start:13.585em;",
      "inline-size:4.75em;block-size:6.175em;margin-inline-start:0em;margin-block-start:6.175em;",
      "inline-size:2em;block-size:2em;margin-inline-start:1em;",
    ]
    for header in ["", header] {
      let leafed = TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + facsimile + body + "</TEI>")
      XCTAssertEqual(leafed[0].typeArea?.measure, TEIPage.leafMeasure)
      XCTAssertEqual(leafed[0].lines.map { TEIRendition.css(from: $0.rend, only: TEIPage.figureSetting) }, leaf)
    }
    // With main text and no type area: as they are.
    let text = ##"<text><body><pb n="1" facs="\##(a)"/><figure facs="#z1"/><p>Words.</p></body></text>"##
    let withoutTypeArea = TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + facsimile + text + "</TEI>")
    XCTAssertNil(withoutTypeArea[0].typeArea)
    XCTAssertEqual(withoutTypeArea[0].lines.map { TEIRendition.css(from: $0.rend, only: TEIPage.figureSetting) }, ["", ""])
  }

  /// A page with no main text (user, 2026-10-30: Hamlet Q1's front cover,
  /// a board lettered in gilt around a crest) sets every line by its line
  /// break's zone as it sets its figures: its box, its place across and
  /// down, its text centered in the box; a page with main text sets only
  /// its figures so, its lines as their settings place them.
  func testAPageWithNoMainTextSetsEveryLineByItsZoneOnTheLeaf() throws {
    let a = "https://example.org/iiif/a/full/1300,/0/default.jpg"
    let header = "<teiHeader><encodingDesc><tagsDecl>"
      + #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:20px;inline-size:44em;block-size:55.9em;margin:3em</rendition>"#
      + "</tagsDecl></encodingDesc></teiHeader>"
    // As the figure test's leaf, set in it whatever the work's type area (`TEIPage.leafTypeArea`): 38 em across its
    // 800 px, an em 800/38 px of the scan, from the leaf's top-left.
    let facsimile = #"<facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\#(a)" width="1000px" height="1300px"/>"#
      + #"<zone xml:id="textblock" type="textblock" points="420,240 620,240 620,440 420,440"/>"#
      + #"<zone type="leaf" points="100,80 900,80 900,920 100,920"/>"#
      + #"<zone xml:id="z-L1" ulx="400" uly="200" lrx="600" lry="220"/>"#
      + #"<zone xml:id="z1" ulx="500" uly="300" lrx="580" lry="400"/></surface></facsimile>"#
    let cover = ##"<text><body><pb n="1" facs="\##(a)" rend="color(yellow)"/>"##
      + ##"<lb facs="#z-L1"/><note type="binding" subtype="copy">HAMLET</note><figure facs="#z1"/></body></text>"##
    let page = try XCTUnwrap(
      TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + facsimile + cover + "</TEI>").first)
    XCTAssertEqual(page.lines.map(\.text), ["HAMLET", ""])
    XCTAssertEqual(page.lines[0].zone?.id, "z-L1")
    // HAMLET: 200 by 26 scan px at 260 px down, 400 across: 9.5 by 1.235 em, 14.25 em from the leaf's left
    // (300 px), 7.41 em from its top (156 px); the crest 104 px under its bottom (286 px), 4.94 em down from it.
    // HAMLET is capitals, set at its ink's size: its cap height its box's 1.235 em, 1.7297 em, its box and place
    // in that em.
    XCTAssertEqual(page.typeArea?.measure, TEIPage.leafMeasure)
    XCTAssertEqual(
      page.lines.map { TEIRendition.css(from: $0.rend, only: TEIPage.lineSetting.union(["text-align", "font-size"])) },
      [
        "text-align:center;font-size:1.7297em;inline-size:5.4923em;block-size:0.714em;margin-inline-start:8.2385em;margin-block-start:4.284em;",
        "inline-size:3.8em;block-size:6.175em;margin-inline-start:19em;margin-block-start:4.94em;",
      ])
    XCTAssertFalse(page.lines[0].opensParagraph, "a placed line stands at its measured white")
    // Its gilt is the page's ink; its board is never the edition's (user, 2026-10-30: no ground is drawn).
    XCTAssertEqual(page.ink, "yellow")
    // With main text the lines keep their own settings.
    let text = ##"<text><body><pb n="1" facs="\##(a)"/><lb facs="#z-L1"/><p>Words.</p></body></text>"##
    let body = try XCTUnwrap(
      TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + facsimile + text + "</TEI>").first)
    XCTAssertEqual(body.lines.map { TEIRendition.css(from: $0.rend, only: TEIPage.lineSetting) }, [""])
  }

  /// Hamlet Q1's front cover as filed (dev, 2026-10-30, calibration_pages
  /// for p15150coll3:1360): a board lettered in gilt around a traced crest,
  /// no main text, no body type measured (its text block has no
  /// `font-size`) and no work type area in its header. It is set in its
  /// leaf (`TEIPage.leafTypeArea`), so its lettering and its crest stand at
  /// their zones, centered on the board as the scan has them; without it,
  /// nothing on it was placed: its lettering ran at the top left at the
  /// reader's size, its crest at its drawing's own pixels.
  func testACoverWithNoTypeOfItsOwnIsSetOnItsLeafByItsZones() throws {
    let frame = "https://cdm16003.contentdm.oclc.org/iiif/2/p15150coll3:1360"
    let tei = ##"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl><rendition xml:id="ground-333635" scheme="css">background-color:#333635</rendition></tagsDecl></encodingDesc></teiHeader>"##
      + ##"<facsimile><surface rendition="#ground-333635" n="Front cover" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\##(frame)/full/max/0/default.jpg" width="6120px" height="6630px"/>"##
      + ##"<zone xml:id="textblock" type="textblock" points="422.53,239.73 623.51,238 625.51,435.87 424.53,437.6"/>"##
      + ##"<zone type="block" subtype="main" points="422.53,239.73 623.51,238 624.31,317.33 423.33,319.06"/>"##
      + ##"<zone type="line" points="422.53,239.73 623.51,238 623.7,257.01 422.72,258.73"><path type="baseline" points="422.54,241.04 623.52,239.32"/></zone>"##
      + ##"<zone type="leaf" points="144.93,54 891.01,54 891.01,946 144.93,946"/>"##
      + ##"<zone xml:id="z-L2" ulx="422" uly="238" lrx="624" lry="259"/><zone xml:id="z-L3" ulx="435" uly="303" lrx="610" lry="319"/>"##
      + ##"<zone xml:id="z-L6" ulx="478" uly="427" lrx="585" lry="438"/><zone xml:id="z-fig-1" type="figure" ulx="515" uly="348" lrx="548" lry="395"/></surface></facsimile>"##
      + ##"<text><body><pb n="Front cover" facs="\##(frame)" rend="color(yellow)"/><lb facs="#z-L2"/><note type="binding" subtype="copy">HAMLET</note>"##
      + ##"<lb facs="#z-L3"/><note type="binding" subtype="copy">SHAKESPEARE</note>"##
      + ##"<figure facs="#z-fig-1"><graphic url="/mission-control/calibration-figures/z-fig-1.svg" mimeType="image/svg+xml"/></figure>"##
      + ##"<lb facs="#z-L6"/><note type="binding" subtype="copy">LONDON 1603</note></body></text></TEI>"##
    let page = try XCTUnwrap(TEIRenderer.pages(in: tei).first)
    let typeArea = try XCTUnwrap(page.typeArea, "a cover with no type of its own is set in its leaf")
    XCTAssertEqual(typeArea.measure, TEIPage.leafMeasure)
    XCTAssertEqual(typeArea.left, 0)
    XCTAssertEqual(typeArea.head, 0)
    func value(_ line: TEILine, _ property: String) -> Double {
      let css = TEIRendition.css(from: line.rend, only: [property])
      return Double(css.dropFirst(property.count + 1).prefix { $0 != "e" && $0 != "r" && $0 != ";" }) ?? .nan
    }
    XCTAssertEqual(page.lines.map(\.text), ["HAMLET", "SHAKESPEARE", "", "LONDON 1603"])
    // The leaf is 746.08 of the surface's 1000 across, 38 em: each box's middle at its zone's, in em of the
    // page, the board's middle at 19 em.
    let leafWidth = (891.01 - 144.93) * 6120 / 1000
    let scale = TEIPage.leafMeasure / leafWidth
    for (line, zone) in zip(page.lines, [(422.0, 624.0), (435, 610), (515, 548), (478, 585)]) {
      let font = line.text.isEmpty ? 1 : value(line, "font-size")
      let start = value(line, "margin-inline-start") * font
      let width = value(line, "inline-size") * font
      XCTAssertEqual(start, (zone.0 - 144.93) * 6.12 * scale, accuracy: 0.001, line.text)
      XCTAssertEqual(width, (zone.1 - zone.0) * 6.12 * scale, accuracy: 0.001, line.text)
      XCTAssertEqual(start + width / 2, TEIPage.leafMeasure / 2, accuracy: 1.2, "\(line.text) stands centered")
    }
    // The crest at its zone's size, 1.68 by 2.6 em, never its drawing's pixels; the lettering at its ink's,
    // HAMLET's cap height its box's 139 scan px.
    XCTAssertEqual(value(page.lines[2], "inline-size"), 33 * 6.12 * scale, accuracy: 0.001)
    XCTAssertEqual(value(page.lines[2], "block-size"), 47 * 6.63 * scale, accuracy: 0.001)
    XCTAssertEqual(value(page.lines[0], "font-size") * TEIPage.capHeight, 21 * 6.63 * scale, accuracy: 0.001)
    XCTAssertEqual(value(page.lines[0], "line-height"), 21 * 6.63 * scale, accuracy: 0.0001, "its line its box")
  }

  /// The scan's width in the em a page is set in (`TEIPage.scanWidth`, the
  /// reader's overlay's type scale), the type area's own rule (user, 2026-11-03):
  /// Hamlet Q1's front cover as integrated (dev, the work's type area in its
  /// header, 80.61 em across its text pages' photographs) is set in its
  /// leaf, so its scan is its leaf's 38 em over the leaf's share of its
  /// width, its tooled border as wide at that em as its zone; at the work's
  /// em the overlay drew it at 0.63 of the scan's. A page with its own body
  /// type is its scan's width over it, one with none its work's.
  func testAScansWidthInEmIsTheTypeAreasItsLeafsOnACover() throws {
    let frame = "https://cdm16003.contentdm.oclc.org/iiif/2/p15150coll3:1360"
    let header = "<teiHeader><encodingDesc><tagsDecl>"
      + #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:85.44px;inline-size:26.47em;block-size:47.94em;margin:7.42em 13.26em 11.23em 9.33em;max-inline-size:80.61em</rendition>"#
      + "</tagsDecl></encodingDesc></teiHeader>"
    let facsimile = ##"<facsimile><surface n="Front cover" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\##(frame)/full/max/0/default.jpg" width="6120px" height="6630px"/>"##
      + ##"<zone xml:id="p1-z-fig-2" ulx="173" uly="61" lrx="882" lry="938"/><zone xml:id="p1-z-L2" ulx="417" uly="238" lrx="637" lry="259"/>"##
      + ##"<zone xml:id="p1-textblock" type="textblock" points="172.3,64.24 879.57,59.61 884.82,936.85 175.7,941.07"/>"##
      + ##"<zone type="leaf" points="144.85,53.4 890.9,53.4 890.9,945.42 144.85,945.42"/></surface></facsimile>"##
    let body = ##"<text><body><pb n="Front cover" facs="\##(frame)" rend="color(yellow)"/><figure facs="#p1-z-fig-2"/>"##
      + ##"<lb facs="#p1-z-L2"/><note type="binding" subtype="copy">HAMLET</note></body></text>"##
    let leafWidth = 890.9 - 144.85
    for header in [header, ""] {
      let page = try XCTUnwrap(TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + facsimile + body + "</TEI>").first)
      XCTAssertEqual(page.typeArea?.measure, TEIPage.leafMeasure)
      let width = try XCTUnwrap(page.scanWidth, "a cover set in its leaf has its leaf's em")
      XCTAssertEqual(width, TEIPage.leafMeasure * 1000 / leafWidth, accuracy: 1e-9)
      // Its tooled border, set at its zone on the leaf, as wide on the scan at that em as its zone (709 of 1000).
      let set = TEIRendition.css(from: page.lines[0].rend, only: ["inline-size"])
      let em = try XCTUnwrap(Double(set.dropFirst("inline-size:".count).prefix { $0 != "e" }))
      XCTAssertEqual(em * 6120 / width, 709 * 6.12, accuracy: 0.5)
    }
    // A text page: its scan's own body type, else its work's type area's 80.61 em.
    let text = ##"<text><body><pb n="p. 3" facs="\##(frame)"/><p>Words.</p></body></text>"##
    let own = facsimile.replacingOccurrences(of: #"941.07""#, with: #"941.07" style="font-size:85.75px""#)
    let measured = try XCTUnwrap(TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + own + text + "</TEI>").first)
    XCTAssertEqual(try XCTUnwrap(measured.scanWidth), 6120 / 85.75, accuracy: 1e-9)
    let declared = try XCTUnwrap(TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header + facsimile + text + "</TEI>").first)
    XCTAssertEqual(try XCTUnwrap(declared.scanWidth), 80.61, accuracy: 1e-9)
    let none = try XCTUnwrap(TEIRenderer.pages(in: #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + facsimile + text + "</TEI>").first)
    XCTAssertNil(none.scanWidth)
  }

  /// Hamlet Q1's front cover reflowed (user, 2026-11-03): its gilt lettering
  /// is set at its ink's size in boxes of its zones, each line its box's
  /// height, 0.714 of its type (`TEIRendition.leading`), so a line that
  /// wraps sets solid; and each box, its ink's width, runs reflowed about
  /// its middle as far as the leaf's nearer side (`TEIPage.reflowedBox`),
  /// where in its box alone "HAMLET" wrapped its "T" over its "M".
  func testACoversLetteringRunsReflowedAboutItsZonesMiddle() throws {
    let frame = "https://cdm16003.contentdm.oclc.org/iiif/2/p15150coll3:1360"
    let tei = ##"<TEI xmlns="http://www.tei-c.org/ns/1.0"><facsimile><surface n="Front cover" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\##(frame)/full/max/0/default.jpg" width="6120px" height="6630px"/>"##
      + ##"<zone xml:id="p1-z-L2" ulx="417" uly="238" lrx="637" lry="259"/><zone xml:id="p1-z-L6" ulx="464" uly="427" lrx="595" lry="438"/>"##
      + ##"<zone xml:id="p1-textblock" type="textblock" points="172.3,64.24 879.57,59.61 884.82,936.85 175.7,941.07"/>"##
      + ##"<zone type="leaf" points="144.85,53.4 890.9,53.4 890.9,945.42 144.85,945.42"/></surface></facsimile>"##
      + ##"<text><body><pb n="Front cover" facs="\##(frame)" rend="color(yellow)"/>"##
      + ##"<lb facs="#p1-z-L2"/><note type="binding" subtype="copy" style="letter-spacing:0.527em">HAMLET</note>"##
      + ##"<lb facs="#p1-z-L6"/><note type="binding" subtype="copy" style="letter-spacing:0.1004em">LONDON 1603</note></body></text></TEI>"##
    let page = try XCTUnwrap(TEIRenderer.pages(in: tei).first)
    let measure = try XCTUnwrap(page.typeArea?.measure)
    XCTAssertEqual(page.lines.map(\.text), ["HAMLET", "LONDON 1603"])
    let scale = measure / ((890.9 - 144.85) * 6.12)
    for (line, zone) in zip(page.lines, [(417.0, 637.0), (464, 595)]) {
      XCTAssertEqual(try XCTUnwrap(TEIRendition.leading(of: line.rend)), TEIPage.capHeight, accuracy: 0.001, line.text)
      let font = try XCTUnwrap(TEIRendition.fontSize(of: line.rend))
      let box = try XCTUnwrap(TEIPage.reflowedBox(of: line.rend, measure: measure), line.text)
      let middle = ((zone.0 + zone.1) / 2 - 144.85) * 6.12 * scale
      // About the zone's middle, as far as the leaf's nearer side, in the line's own em.
      XCTAssertEqual((box.start + box.size / 2) * font, middle, accuracy: 0.001, line.text)
      XCTAssertEqual(box.size * font, 2 * min(middle, measure - middle), accuracy: 0.001, line.text)
      XCTAssertGreaterThan(box.size * font, (zone.1 - zone.0) * 6.12 * scale, line.text)
    }
    // Never narrower than its box; none for a line with no box of its own.
    let edge = "css:text-align=center css:inline-size=10em css:margin-inline-start=30em"
    XCTAssertEqual(try XCTUnwrap(TEIPage.reflowedBox(of: edge, measure: 38)).start, 30)
    XCTAssertEqual(try XCTUnwrap(TEIPage.reflowedBox(of: edge, measure: 38)).size, 10)
    XCTAssertNil(TEIPage.reflowedBox(of: "css:font-size=2em css:line-height=0.88em", measure: 38))
    XCTAssertNil(TEIPage.reflowedBox(of: "css:inline-size=4em", measure: 38), "a box not centered")
    // A body's leading as written; a percentage; a scale step over its size.
    XCTAssertEqual(TEIRendition.leading(of: "css:font-size=0.9982em css:line-height=1.2614em"), 1.2614)
    XCTAssertEqual(TEIRendition.leading(of: "css:line-height=120%"), 1.2)
    XCTAssertEqual(try XCTUnwrap(TEIRendition.leading(of: "css:font-size=2em css:line-height=1.5rem")), 0.75, accuracy: 1e-12)
    XCTAssertNil(TEIRendition.leading(of: "css:font-size=2em"))
    // A line-height out of bounds is drawn as none (Hamlet Q1 p. 3's heading, 0.7294em): no leading to set solid.
    XCTAssertNil(TEIRendition.leading(of: "css:font-size=1.6739em css:line-height=0.7294em"))
    XCTAssertEqual(TEIRendition.css(from: "css:font-size=1.6739em css:line-height=0.7294em"), "font-size:1.6739em;")
  }

  /// A note's place in a margin is an area around the type area: a side, or a
  /// corner as two; "margin", its side unknown, and any other place none.
  func testANotesMarginalPlaceIsAnAreaAroundTheTypeArea() {
    XCTAssertEqual(TEIRenderer.marginalArea(of: "margin-left"), "margin-left")
    XCTAssertEqual(TEIRenderer.marginalArea(of: "bottom"), "bottom")
    XCTAssertEqual(TEIRenderer.marginalArea(of: "top margin-left"), "top-left")
    XCTAssertEqual(TEIRenderer.marginalArea(of: "margin-right bottom"), "bottom-right")
    XCTAssertNil(TEIRenderer.marginalArea(of: "margin"))
    XCTAssertNil(TEIRenderer.marginalArea(of: "foot"))
    XCTAssertNil(TEIRenderer.marginalArea(of: "top bottom"))
    XCTAssertNil(TEIRenderer.marginalArea(of: ""))
  }

  /// A page genuinely larger than its work's (a foldout: its scan wider
  /// than the body pages' by more than a margin) is its scan's own size, in
  /// the work's em; a page of the body pages' size is its type area and its
  /// marginalia with their margin.
  func testAGenuinelyLargerPageIsItsScansOwnSize() throws {
    let a = "https://example.org/iiif/a/full/1300,/0/default.jpg"
    let b = "https://example.org/iiif/b/full/1300,/0/default.jpg"
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>\
      <rendition xml:id="text-block" scheme="css" selector="text">font-size:20px;inline-size:44em;block-size:55.9em;margin:3em</rendition>\
      </tagsDecl></encodingDesc></teiHeader>
      <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(a)" width="1000px" height="1300px"/>\
      <zone xml:id="p1-textblock" type="textblock" points="60,60 940,60 940,920 60,920" style="font-size:20px"/></surface>\
      <surface n="2" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(b)" width="2400px" height="1300px"/>\
      <zone xml:id="p2-textblock" type="textblock" points="100,100 200,100 200,150 100,150" style="font-size:20px"/></surface></facsimile>
      <text><body><pb n="1" facs="\(a)"/><p>Body.</p><pb n="2" facs="\(b)"/><p>Plate.</p></body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: document)
    XCTAssertEqual(pages[0].typeArea, TEIPageTypeArea(measure: 44, height: 55.9, head: 3, foot: 3, inner: 3, outer: 3))
    XCTAssertEqual(pages[1].typeArea, TEIPageTypeArea(measure: 44, height: 55.9, head: 3, foot: 3, inner: 3, outer: 3, pageWidth: 120, pageHeight: 65))
  }

  /// A page read again is laid into the document with its zones: its body
  /// where the old one stood, its surface in the old one's place, its ids
  /// prefixed with its place (gnorium-python `document_surface`).
  func testAPageReadAgainIsLaidInWithItsZones() throws {
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/>
      <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="https://example.org/iiif/a/full/1300,/0/default.jpg"/><zone xml:id="p1-z1" ulx="1" uly="1" lrx="2" lry="2"/></surface>\
      <surface n="2" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="https://example.org/iiif/b/full/1300,/0/default.jpg"/><zone xml:id="p2-z1" ulx="5" uly="5" lrx="9" lry="9"/></surface></facsimile>
      <text><body><pb n="1" facs="https://example.org/iiif/a/full/1300,/0/default.jpg"/><figure facs="#p1-z1"/>
      <pb n="2" facs="https://example.org/iiif/b/full/1300,/0/default.jpg"/><figure facs="#p2-z1"/></body></text></TEI>
      """
    let old = TEIRenderer.pages(in: document)[1]
    let page = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/><facsimile><surface n="2" ulx="0" uly="0" lrx="1000" lry="1000">\
      <zone xml:id="z1" ulx="100" uly="100" lrx="300" lry="300"/><zone xml:id="z2" ulx="10" uly="10" lrx="20" lry="30"/></surface></facsimile>\
      <text><body><figure facs="#z1"/><p><w><hi rend="initial" facs="#z2">A</hi>nd</w></p></body></text></TEI>
      """
    let laid = try XCTUnwrap(TEIFacsimile.laying(
      page: page, fragment: ##"<figure facs="#z1"/><p><w><hi rend="initial" facs="#z2">A</hi>nd</w></p>"##, over: old,
      position: 2, in: document))
    XCTAssertEqual(Set(TEIFacsimile.zones(in: TEIFacsimile.blocks(in: laid)).keys), ["p1-z1", "p2-z1", "p2-z2"])
    XCTAssertFalse(laid.contains(#"ulx="5""#))
    let pages = TEIRenderer.pages(in: laid)
    guard case .figure(_, let zone, _) = pages[1].lines[0].kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(zone?.corners, "100 100 300 300")
    XCTAssertEqual(pages[1].lines[1].runs[0].zone?.corners, "10 10 20 30")
    guard case .figure(_, let first, _) = pages[0].lines[0].kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(first?.corners, "1 1 2 2")
    XCTAssertTrue(laid.contains(#"<graphic url="https://example.org/iiif/b/full/1300,/0/default.jpg"/><zone xml:id="p2-z1""#))
  }

  private static func laidDocument(_ pages: [String]) -> String {
    let breaks = pages.enumerated().map { index, inner in
      "<pb n=\"\(index + 1)\" facs=\"https://example.org/iiif/p\(index + 1)/full/1300,/0/default.jpg\"/>\n\(inner)\n"
    }
    return """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/>
      <text>
          <front>
      \(breaks.joined())
          </front>
          <body>

          </body>
        </text>
      </TEI>
      """
  }

  /// Each page's range is where its markup stands, the last stopping
  /// before the document's closing structure.
  func testPageRangesHoldEachPagesMarkup() {
    let document = Self.laidDocument(["<p>One.</p>", "", "<p>Three.</p>"])
    let ranges = TEIRenderer.pageRanges(in: document)
    let pages = TEIRenderer.pages(in: document)
    XCTAssertEqual(ranges.count, 3)
    XCTAssertEqual(
      ranges.map { document[$0].trimmingCharacters(in: .whitespacesAndNewlines) }, pages.map(\.markup))
    XCTAssertFalse(document[ranges[2]].contains("</front>"))
  }

  /// A blank page—in the middle, and at the end before `</front>`—is laid
  /// into: its empty markup is in no document, and a search for it skipped
  /// every blank page (prod, 2026-10-10).
  func testAPageIsLaidIntoABlankPage() throws {
    let document = Self.laidDocument(["<p>One.</p>", "", "<p>Three.</p>", ""])
    var laid = document
    for (position, text) in [(2, "Two."), (4, "Four.")] {
      let old = TEIRenderer.pages(in: laid)[position - 1]
      XCTAssertEqual(old.markup, "")
      laid = try XCTUnwrap(
        TEIFacsimile.laying(
          page: "<TEI/>", fragment: "<pb n=\"\(position)\"/>\n<p>\(text)</p>", over: old, position: position, in: laid))
    }
    let pages = TEIRenderer.pages(in: laid)
    XCTAssertEqual(
      pages.map(\.markup), ["<p>One.</p>", "<p>Two.</p>", "<p>Three.</p>", "<p>Four.</p>"])
    XCTAssertEqual(laid.components(separatedBy: "<pb").count, 5, "the side's own break folded into the image's")
    XCTAssertTrue(laid.contains("<p>Four.</p>\n\n    </front>"))
    // A place that reads another image is no place to lay it.
    let other = TEIRenderer.pages(in: document)[1]
    XCTAssertNil(TEIFacsimile.laying(page: "<TEI/>", fragment: "<p>X</p>", over: other, position: 3, in: document))
  }

  /// A page laid in declares its steps in the document's header, beside
  /// those the document declares (`TEIRendition.joining`).
  func testALaidPageJoinsItsRenditionsIntoTheHeader() throws {
    let document = Self.laidDocument(["<p>One.</p>", "<p>Two.</p>"])
    let size = #"<rendition xml:id="size-1" scheme="css">font-size:0.8251rem</rendition>"#
    let page = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"#
      + size + ##"</tagsDecl></encodingDesc></teiHeader><text><body><p rendition="#size-1">Two.</p></body></text></TEI>"##
    let old = TEIRenderer.pages(in: document)[1]
    let laid = try XCTUnwrap(
      TEIFacsimile.laying(page: page, fragment: ##"<p rendition="#size-1">Two.</p>"##, over: old, position: 2, in: document))
    // Written formatted, one element per line (user, 2026-10-26).
    XCTAssertEqual(TEIRendition.renditions(of: laid), size)
    XCTAssertTrue(laid.contains("<tagsDecl>\n") && laid.contains("\n</teiHeader>"), laid)
    XCTAssertEqual(TEIRenderer.pages(in: laid)[1].renditions["size-1"], "css:font-size=0.8251rem")
  }

  /// Pages laid together read as the same pages laid one after another,
  /// their renditions joined and their bodies in place; a place given
  /// twice is laid once.
  func testPagesLaidTogetherAreThePagesLaidInTurn() throws {
    let document = Self.laidDocument(["<p>One.</p>", "<p>Two.</p>", "<p>Three.</p>"])
    let pages = TEIRenderer.pages(in: document)
    func page(_ step: String, _ text: String) -> String {
      #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"#
        + #"<rendition xml:id="size-1" scheme="css">font-size:\#(step)rem</rendition>"#
        + ##"</tagsDecl></encodingDesc></teiHeader><text><body><p rendition="#size-1">"## + text + "</p></body></text></TEI>"
    }
    let layings = [
      TEIFacsimile.Laying(page: page("0.8251", "Uno."), fragment: ##"<p rendition="#size-1">Uno.</p>"##, over: pages[0], position: 1),
      TEIFacsimile.Laying(page: page("1.2000", "Tres."), fragment: ##"<p rendition="#size-1">Tres.</p>"##, over: pages[2], position: 3),
      TEIFacsimile.Laying(page: page("1.2000", "Again."), fragment: "<p>Again.</p>", over: pages[2], position: 3),
    ]
    var inTurn = document
    for laying in layings.prefix(2) {
      inTurn = try XCTUnwrap(
        TEIFacsimile.laying(page: laying.page, fragment: laying.fragment, over: laying.old, position: laying.position, in: inTurn))
    }
    let together = TEIFacsimile.laying(layings, in: document)
    XCTAssertEqual(together.laid, [0, 1])
    XCTAssertEqual(together.document, inTurn)
    XCTAssertEqual(
      TEIRenderer.pages(in: together.document).map(\.markup),
      [##"<p rendition="#size-1">Uno.</p>"##, "<p>Two.</p>", ##"<p rendition="#size-2">Tres.</p>"##])
  }

  /// Identical markup on two pages is two pages: only the named one changes.
  func testLayingChangesOnlyTheNamedPageWhenTwoReadTheSame() throws {
    let document = Self.laidDocument(["<p>Same.</p>", "<p>Same.</p>", "<p>Same.</p>"])
    let old = TEIRenderer.pages(in: document)[1]
    let laid = try XCTUnwrap(
      TEIFacsimile.laying(page: "<TEI/>", fragment: "<p>Changed.</p>", over: old, position: 2, in: document))
    XCTAssertEqual(TEIRenderer.pages(in: laid).map(\.markup), ["<p>Same.</p>", "<p>Changed.</p>", "<p>Same.</p>"])
  }

  /// One `<pb>` per page: a page laid in opening with its side's own
  /// break has it folded into the image's, named as the side and carrying
  /// the image; an opening's later side keeps its own, a mark within the
  /// image's page (gnorium-python `own_page_break`).
  func testLayingFoldsTheSidesOwnBreakIntoTheFrames() throws {
    let document = Self.laidDocument(["<p>One.</p>", "<p>Two.</p>"])
    let one = try XCTUnwrap(TEIRenderer.layingPage(1, with: "<pb n=\"2\"/>\n<p>New.</p>", in: document))
    XCTAssertTrue(one.contains("<pb n=\"2\" facs=\"https://example.org/iiif/p2/full/1300,/0/default.jpg\"/>\n<p>New.</p>"))
    XCTAssertEqual(one.components(separatedBy: "<pb").count, 3)
    let opening = try XCTUnwrap(
      TEIRenderer.layingPage(1, with: "<pb n=\"2a\"/><p>Left.</p><pb n=\"2b\"/><p>Right.</p>", in: document))
    let pages = TEIRenderer.pages(in: opening)
    XCTAssertEqual(pages.map(\.label), ["1", "2a"])
    // Stored formatted (`XMLFormatter.formatted`): the body's children a
    // line each.
    XCTAssertEqual(pages[1].markup, "<p>Left.</p>\n<pb n=\"2b\"/>\n<p>Right.</p>")
    XCTAssertEqual(pages[1].lines.filter { if case .mark = $0.kind { true } else { false } }.map(\.text), ["2b"])
    // A page with no break of its own is laid as it is.
    XCTAssertEqual(
      TEIRenderer.layingPage(1, with: "<p>New.</p>", in: document),
      TEIRenderer.replacingPage(1, with: "<p>New.</p>", in: document))
    XCTAssertNil(TEIRenderer.layingPage(2, with: "<p>New.</p>", in: document))
  }

  /// A formula's MathML as a diff compares and draws it: its drawn content,
  /// read back the same; an unreadable mark a gap.
  func testAFormulaIsComparedAndDrawnAsItsMathML() throws {
    let lines = TEIRenderer.lines(
      in: #"<p><formula notation="mathml"><math xmlns="http://www.w3.org/1998/Math/MathML" display="inline">"#
        + #"<semantics><mrow><mi>sin</mi><mo rspace="0.1667em">\#u{2061}</mo><mi>x</mi><mo>&lt;</mo>"#
        + #"<semantics><mrow/><annotation-xml encoding="application/tei+xml"><gap xmlns="http://www.tei-c.org/ns/1.0" reason="illegible"/></annotation-xml></semantics>"#
        + #"</mrow><annotation encoding="application/x-tex">\sin x &lt; \text{[?]}</annotation></semantics></math></formula></p>"#)
    guard case .math(let formula) = lines[0].runs[0].kind else { return XCTFail("Missing formula") }
    XCTAssertEqual(
      formula.markup,
      #"<math xmlns="http://www.w3.org/1998/Math/MathML" display="inline"><mrow><mi>sin</mi><mo rspace="0.1667em">\#u{2061}</mo><mi>x</mi><mo>&lt;</mo>"#
        + #"<semantics><mrow/><annotation-xml encoding="application/tei+xml"><gap xmlns="http://www.tei-c.org/ns/1.0" reason="illegible"/></annotation-xml></semantics></mrow></math>"#)
    let read = try XCTUnwrap(TEIRenderer.math(markup: formula.markup))
    XCTAssertEqual(read.markup, formula.markup)
    XCTAssertEqual(read.runs.map(\.text), ["sin", "\u{2061}", "x", "<"])
  }

  func testFragmentsNamespacesAndQuotedAttributeDelimiters() {
    let lines = TEIRenderer.lines(
      in:
        "</div><tei:p rend = 'center' n='a > b'>text <tei:hi rend = 'italic'>ſæ</tei:hi></tei:p><div><p>tail"
    )
    XCTAssertEqual(lines.map(\.text), ["text ſæ", "tail"])
    XCTAssertEqual(lines[0].rend, "center")
    XCTAssertEqual(lines[0].runs.last?.rend, "italic")
  }

  func testEmptyMarkersDoNotCaptureFollowingTextAndCDATAIsLiteral() {
    let lines = TEIRenderer.lines(
      in:
        "<p>A<lb>B<!-- ignored --><lb/><![CDATA[<literal> &lt;]]></p><milestone unit='document'/><head>Attached item</head>"
    )
    XCTAssertEqual(lines.map(\.text), ["A", "B", "<literal> &lt;", "", "Attached item"])
    guard case .documentBoundary = lines[3].kind else { return XCTFail("Missing boundary") }
  }

  func testNestedTablesAndReadingWeightIncludeCellContents() {
    let markup =
      "<table><row><cell>Outer<table><row><cell>Inner</cell></row></table></cell><cell>X</cell></row></table>"
    let lines = TEIRenderer.lines(in: markup)
    guard case .table(let outer) = lines.first?.kind else { return XCTFail("Missing outer table") }
    guard case .table = outer.rows[0].cells[0].lines[1].kind else {
      return XCTFail("Missing nested table")
    }
    XCTAssertEqual(TEIRenderer.textWeight(of: markup), "Outer Inner X".count)
  }

  func testSmallTableIsNotReportedAsLiteralBlankText() {
    let markup = "<table><row><cell>OX</cell><cell>XO</cell></row></table>"
    let page = TEIPage(
      label: "7", facsimileURL: "", lines: TEIRenderer.lines(in: markup), markup: markup)
    XCTAssertFalse(TEIRenderer.faults(in: page).contains { $0.kind == .literalBlank })
  }

  func testEnrichedEncodingReadsAsTheSurfaceWithWhatIsBesideIt() {
    let page = #"""
      <p><s><w lemma="the" pos="DET"><choice><abbr>yͤ</abbr><expan>the</expan></choice></w> <w lemma="virtue" pos="NOUN" msd="Number=Sing"><choice><orig>vertue</orig><reg>virtue</reg></choice></w> <w lemma="of" pos="ADP">of</w> <persName><w lemma="John" pos="PROPN">Iohn</w></persName> <w lemma="show" pos="VERB"><g ref="#slong">ſ</g>hewed</w> <w lemma="bank" pos="NOUN">ba<supplied reason="damage">nk</supplied></w><pc>,</pc> <del rend="strikethrough">not</del> <date when="1603"><num value="1603">1603</num></date><pc>.</pc></s><note place="margin"><s><w lemma="mark" pos="VERB">Marke</w></s></note></p><list><item>First</item><item>Second</item></list><handShift new="#h2"/>
      """#
    let lines = TEIRenderer.lines(in: page)
    XCTAssertEqual(
      lines.map(\.text), ["yͤ vertue of Iohn ſhewed ba[nk], not 1603.", "Marke", "First", "Second"])
    let runs = lines[0].runs
    XCTAssertEqual(runs.first { $0.text == "yͤ" }?.alternative, "the")
    XCTAssertEqual(runs.first { $0.text == "vertue" }?.alternative, "virtue")
    XCTAssertEqual(runs.first { $0.text == "of" }?.alternative, "")
    XCTAssertEqual(runs.first { $0.text == "nk" }?.rend, "supplied")
    XCTAssertEqual(runs.first { $0.text == "not" }?.rend, "del")
    guard case .note(let place) = lines[1].kind else { return XCTFail("Lost the marginal note") }
    XCTAssertEqual(place, "margin")
    XCTAssertTrue(lines[2].opensBlock && lines[3].opensBlock)
  }

  func testAnEnrichedPageHasNoFaultsAndWeighsItsReading() {
    let tagged = TEIPage(
      label: "7", facsimileURL: "",
      lines: TEIRenderer.lines(in: #"<pb n="7"/><p><s><w lemma="be" pos="VERB">Been</w> <w lemma="thus" pos="ADV">thus</w><pc>,</pc><lb/><w lemma="encounter" pos="VERB">encountred</w><pc>:</pc></s></p>"#),
      markup: #"<pb n="7"/><p><s><w lemma="be" pos="VERB">Been</w> <w lemma="thus" pos="ADV">thus</w><pc>,</pc><lb/><w lemma="encounter" pos="VERB">encountred</w><pc>:</pc></s></p>"#)
    XCTAssertTrue(TEIRenderer.faults(in: tagged).isEmpty)
    XCTAssertEqual(
      TEIRenderer.textWeight(of: tagged.markup),
      TEIRenderer.textWeight(of: #"<pb n="7"/><p>Been thus,<lb/>encountred:</p>"#))
  }

  func testLinesKnowWhetherTheyShareALineOrJoinAWord() {
    let lines = TEIRenderer.lines(
      in: #"""
        <fw type="pageNum" rend="align(left)">10</fw> <fw type="header" rend="align(center)">On the Goodness</fw>
        <lg><l rend="indent(1)"><s><w lemma="the" pos="DET">The</w> <w lemma="computer" pos="NOUN">compu-<lb break="no"/>ter</w> <w lemma="stand" pos="VERB">stands</w><lb/><w lemma="here" pos="ADV">here</w></s></l></lg>
        <fw type="catch" rend="align(right)">Here,</fw>
        """#)
    XCTAssertEqual(lines.map(\.text), ["10", "On the Goodness", "The compu-", "ter stands", "here", "Here,"])
    XCTAssertEqual(lines.map(\.sharesLine), [false, true, false, false, false, false])
    XCTAssertEqual(lines.map(\.joinsPrevious), [false, false, false, true, false, false])
    XCTAssertEqual(lines.map(\.opensBlock), [true, true, true, false, false, true])
    XCTAssertEqual(lines[2].rend, "indent(1)")
    XCTAssertEqual(lines[5].rend, "align(right)")
  }

  /// A measured line the print sets on another's row names its own zone and
  /// opens no `<lb/>` (gnorium-python `base_tei._rows`): a catchword on the
  /// signature's row, a turnover on the row of the line beside it, each its
  /// own line sharing that row, set at its own place.
  func testALineSetOnAnothersRowSharesItsRowAtItsOwnPlace() {
    let lines = TEIRenderer.lines(
      in: #"""
        <ab><lb facs="#z-L21"/>But who must lie in it?<seg facs="#z-L22" rend="align(left)" style="margin-inline-start:24.25rem">(sir.</seg><lb facs="#z-L23"/>If I should say</ab>
        <lb facs="#z-L38"/><fw type="sig" rend="align(left)" style="margin-inline-start:18rem">C</fw><fw type="catch" facs="#z-L39" rend="align(left)" style="margin-inline-start:23.75rem">Ham.</fw>
        """#)
    XCTAssertEqual(lines.map(\.text), ["But who must lie in it?", "(sir.", "If I should say", "C", "Ham."])
    XCTAssertEqual(lines.map(\.sharesLine), [false, true, false, false, true])
    XCTAssertEqual(lines[1].rend, "align(left) css:margin-inline-start=24.25rem")
    XCTAssertFalse(lines[1].opensBlock)
    XCTAssertTrue(lines[4].rend.contains("css:margin-inline-start=23.75em"))
  }

  /// Hamlet Q1 p. 5's direction line as its stored page keeps it: the
  /// signature on its measured line, the catchword on its row, each at the
  /// place its margin gives in rem, so "B 2" stands center-right and "Hath"
  /// after it at the far right (dev, 2026-11-10: an arbitration set the two
  /// margins as spaces, the catchword's counted from the row's start, and
  /// its render put "Hath" before "B 2").
  func testHamletQ1P5sSignatureAndCatchwordStandWhereTheirMarginsPlaceThem() {
    let lines = TEIRenderer.lines(
      in: #"""
        <lb facs="#p11-z-L38"/>
        <fw type="sig" rend="align(left)" style="margin-inline-start:15.1489rem"><w xml:id="w10.593" lemma="B" class="letter" facs="#p11-wz282">B</w> <num value="2">2</num></fw>
        <fw type="catch" facs="#p11-z-L39" rend="align(left)" style="margin-inline-start:24.0052rem"><w xml:id="w10.594" lemma="have" class="verb" facs="#p11-wz281">Hath</w></fw>
        """#)
    XCTAssertEqual(lines.map(\.text), ["B 2", "Hath"])
    XCTAssertEqual(lines.map(\.sharesLine), [false, true])
    let starts = lines.map { line -> Double? in
      line.rend.split(separator: " ").first { $0.hasPrefix("css:margin-inline-start=") }
        .flatMap { Double($0.dropFirst("css:margin-inline-start=".count).dropLast(2)) }
    }
    XCTAssertEqual(starts, [15.1489, 24.0052], "each at its own margin from the row's start, never after the other")
  }

  /// A title page's parts are blocks, as TEI has them: each starts a line.
  /// A `docAuthor` in a byline is a phrase of it.
  func testATitlePagesPartsStartTheirOwnLines() {
    let lines = TEIRenderer.lines(
      in: "<titlePage><docTitle><titlePart type=\"main\">DICTIONARY</titlePart><titlePart>OF WORDS</titlePart></docTitle>"
        + "<byline>by <docAuthor>W. Skeat</docAuthor></byline><docEdition>Second edition</docEdition>"
        + "<epigraph>Motto</epigraph><docImprint>Oxford: <docDate>1888</docDate></docImprint>"
        + "<docDate>1888</docDate><argument>Argument</argument><imprimatur>Licensed</imprimatur></titlePage>")
    XCTAssertEqual(
      lines.map(\.text),
      ["DICTIONARY", "OF WORDS", "by W. Skeat", "Second edition", "Motto", "Oxford: 1888", "1888", "Argument", "Licensed"])
    XCTAssertTrue(lines.allSatisfy(\.opensBlock))
  }

  /// Laid out over lines and indented, as a person or the formatter writes
  /// it, a page reads as XML text is displayed: one space wherever white
  /// space stood, none at a line's edges, the runs drawn as the line reads.
  func testIndentedMarkupReadsWithOneSpaceAndNoneAtTheEdges() {
    let markup = """
      <titlePage>
        <docImprint>
          <s>
            <persName>
              <w>HENRY</w>
              <w>FROWDE</w></persName><pc>,</pc>
            <w>M.A.</w>
            <lb/>
            <w>LONDON</w>   <w>NEW</w>
            <lb/>
              <w>YORK</w>
          </s>
        </docImprint>
      </titlePage>
      """
    let lines = TEIRenderer.lines(in: markup)
    XCTAssertEqual(lines.map(\.text), ["HENRY FROWDE, M.A.", "LONDON NEW", "YORK"])
    for line in lines {
      XCTAssertEqual(line.runs.map(\.text).joined(), line.text, "The runs draw the line as it reads")
    }
    // As marked words too: each word's runs are its surface.
    let marked = TEIRenderer.lines(in: markup, marksWords: true)
    XCTAssertEqual(marked.map { $0.runs.map(\.text).joined() }, ["HENRY FROWDE, M.A.", "LONDON NEW", "YORK"])
  }

  /// White space inside a name before its close is white space, by XML's
  /// rules: one space before the comma. The cure is markup without it.
  func testWhiteSpaceBeforeAClosingTagStillReadsAsASpace() {
    let markup = "<p><s><persName>\n  <w>HENRY</w>\n  <w>FROWDE</w>\n</persName><pc>,</pc> <w>M.A.</w></s></p>"
    XCTAssertEqual(TEIRenderer.lines(in: markup).map(\.text), ["HENRY FROWDE , M.A."])
  }

  /// Space the source leaves is drawn as that much space, never collapsed;
  /// white space under `xml:space="preserve"` is kept exactly; indentation
  /// elsewhere still collapses.
  func testEncodedSpaceAndPreservedWhiteSpaceAreKept() {
    let spaced = TEIRenderer.lines(in: "<p>\n  <w>one</w><space quantity=\"3\" unit=\"chars\"/><w>two</w>\n</p>")
    XCTAssertEqual(spaced.map(\.text), ["one two"])
    XCTAssertTrue(spaced[0].runs.contains { if case .space(3, "chars") = $0.kind { $0.preserved } else { false } })

    let preserved = TEIRenderer.lines(in: "<p>\n  <seg xml:space=\"preserve\">a  b</seg>\n  <w>c</w>   <w>d</w>\n</p>")
    XCTAssertEqual(preserved.map(\.text), ["a  b c d"])

    // Vertical space is one line of its height, never blank text lines.
    let lines = TEIRenderer.lines(in: #"<p><w>above</w></p><space quantity="2" unit="lines"/><p><w>below</w></p>"#)
    XCTAssertEqual(lines.map(\.text), ["above", " ", "below"])
    guard case .space(let quantity, let unit) = lines[1].kind else { return XCTFail("not a space: \(lines[1].kind)") }
    XCTAssertEqual(quantity, 2)
    XCTAssertEqual(unit, "lines")
    let vertical = TEIRenderer.lines(in: #"<p>a</p><space dim="vertical" quantity="5" unit="mm"/>"#)
    guard case .space(5, "mm") = vertical.last?.kind else { return XCTFail("not 5mm: \(String(describing: vertical.last?.kind))") }
    // A length may be a decimal; whole lines stay whole.
    let decimal = TEIRenderer.lines(in: #"<p>a</p><space dim="vertical" quantity="1.5" unit="em"/><p>b</p>"#)
    guard case .space(1.5, "em") = decimal[1].kind else { return XCTFail("not 1.5em: \(decimal[1].kind)") }
  }

  /// A horizontal space is a gap in its line as wide as it says: so many
  /// characters where it names no unit, a length in its own, a decimal
  /// too. It never empties the page (a decimal did, 2026-10-13).
  func testHorizontalSpaceIsAGapInTheLine() {
    func gaps(_ markup: String) -> [(Double, String)] {
      TEIRenderer.lines(in: markup).flatMap(\.runs).compactMap {
        if case .space(let quantity, let unit) = $0.kind { (quantity, unit) } else { nil }
      }
    }
    for (space, quantity, unit) in [
      (#"<space quantity="3"/>"#, 3.0, "chars"), (#"<space quantity="1.5" unit="chars"/>"#, 1.5, "chars"),
      (#"<space dim="horizontal" quantity="2"/>"#, 2, "chars"), (#"<space dim="horizontal" quantity="0.68" unit="em"/>"#, 0.68, "em"),
      (#"<space quantity="4" unit="mm"/>"#, 4, "mm"), ("<space/>", 1, "chars"),
    ] {
      let markup = "<p><w>one</w>" + space + "<w>two</w></p>"
      XCTAssertEqual(TEIRenderer.lines(in: markup).map(\.text), ["one two"], space)
      XCTAssertEqual(TEIRenderer.lines(in: markup, marksWords: true).map(\.text), ["one two"], space)
      let found = gaps(markup)
      XCTAssertEqual(found.count, 1, space)
      XCTAssertEqual(found.first?.0, quantity, space)
      XCTAssertEqual(found.first?.1, unit, space)
    }
    // At a line's start it stays: an indent the print shows.
    let indented = TEIRenderer.lines(in: #"<p><space quantity="2"/><w>one</w></p>"#)
    XCTAssertEqual(indented.first?.runs.count, 2)
    // A page with one renders, its lines all there.
    let document = #"<TEI><text><body><pb n="1" facs="https://example.org/p1"/><p>a<space dim="horizontal" quantity="1.5"/>b</p></body></text></TEI>"#
    XCTAssertEqual(TEIRenderer.pages(in: document).first?.lines.map(\.text), ["a b"])
  }

  /// A block a column break falls inside runs on into the next column as
  /// a paragraph runs on across a page: initial before the break, final
  /// after it; a break between blocks parts nothing (user, 2026-10-13).
  func testABlockBrokenByAColumnRunsOnIntoTheNext() {
    let note = TEIRenderer.lines(in: #"<note place="foot"><cb/>One<lb/>two<lb/><cb/>three<lb/>four<lb/></note>"#)
    XCTAssertEqual(note.map(\.part), ["I", "I", "F", "F"])
    let blocks = TEIRenderer.lines(in: #"<div><cb/><p>One<lb/></p><cb/><p>two<lb/></p></div>"#)
    XCTAssertEqual(blocks.map(\.part), ["", ""])
    let onward = TEIRenderer.lines(in: #"<p part="I"><cb/>One<lb/><cb/>two<lb/></p>"#)
    XCTAssertEqual(onward.map(\.part), ["I", "M"])
  }

  func testTheFormatterLeavesPreservedWhiteSpaceAlone() {
    let markup = "<div><ab xml:space=\"preserve\"><w>a</w>  <w>b</w>\n   <lb/></ab><p><w>c</w></p></div>"
    let pretty = XMLFormatter.prettified(markup)
    XCTAssertTrue(pretty.contains("<ab xml:space=\"preserve\"><w>a</w>  <w>b</w>\n   <lb/></ab>"), pretty)
  }

  /// A work laid in blank past its reading (user, 2026-10-09): four pages
  /// read of six images. The document's closing structure after the last
  /// page break belongs to no page, so the sixth image reads empty and
  /// unexplicated, as the fifth does; the fourth is read.
  func testTheDocumentsClosingStructureBelongsToNoPage() {
    let xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><front>
      <pb n="1" facs="https://example.org/iiif/p1/full/full/0/default.jpg"/><p>One.</p>
      <pb n="2" facs="https://example.org/iiif/p2/full/full/0/default.jpg"/><p>Two.</p>
      </front><body>
      <pb n="3" facs="https://example.org/iiif/p3/full/full/0/default.jpg"/><p>Three.</p>
      <pb n="4" facs="https://example.org/iiif/p4/full/full/0/default.jpg"/><p>Four.</p>
      <pb n="5" facs="https://example.org/iiif/p5/full/full/0/default.jpg"/>
      <pb n="6" facs="https://example.org/iiif/p6/full/full/0/default.jpg"/>
      </body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: xml)
    XCTAssertEqual(pages.count, 6)
    XCTAssertEqual(pages[3].markup, "<p>Four.</p>")
    XCTAssertEqual(pages[4].markup, "")
    XCTAssertEqual(pages[5].markup, "", "the raw view of the last canvas is empty")
    XCTAssertEqual(pages.map { TEIRenderer.hasMarkup($0.markup) }, [true, true, true, true, false, false])
    // The second page's markup keeps its own content; the structure that
    // follows it is the document's.
    XCTAssertEqual(pages[1].markup, "<p>Two.</p>\n</front><body>")
    XCTAssertEqual(TEIRenderer.withoutTrailingStructure("</front>\n<body>\n</body>"), "")
    XCTAssertEqual(TEIRenderer.withoutTrailingStructure("<p>a</p></div></front><body>"), "<p>a</p></div>")
    // A gap or a figure is markup; breaks alone are not.
    XCTAssertTrue(TEIRenderer.hasMarkup("<gap reason=\"illegible\"/>"))
    XCTAssertTrue(TEIRenderer.hasMarkup("<figure><graphic url=\"x\"/></figure>"))
    XCTAssertFalse(TEIRenderer.hasMarkup("<pb n=\"1v\"/>\n<lb/>"))
    XCTAssertFalse(TEIRenderer.hasMarkup("<div><p></p></div>"))
  }

  func testExcessiveSpaceQuantitiesAreRejectedBeforeExpansion() {
    for quantity in ["9223372036854775807", "9223372036854775808", "999999999999999999999999999999999"] {
      for attributes in ["unit='chars'", "unit='lines'", "dim='vertical'"] {
        let markup = "<p>before<space quantity='\(quantity)' \(attributes)/><w>after</w></p>"
        XCTAssertTrue(TEIRenderer.lines(in: markup).isEmpty)
        XCTAssertTrue(TEIRenderer.lines(in: markup, marksWords: true).isEmpty)
        let document = "<TEI><text><body><pb n='1' facs='https://example.org/p1'/>" + markup + "</body></text></TEI>"
        let page = TEIRenderer.pages(in: document).first
        XCTAssertEqual(page?.markup, markup, "Rejecting an expansion must not rewrite source markup")
        XCTAssertEqual(page?.lines.count, 0)
      }
    }
    XCTAssertTrue(TEIRenderer.lines(in: "<space quantity='4097' unit='chars'/>").isEmpty)
    XCTAssertTrue(TEIRenderer.lines(in: "<space quantity='129' unit='lines'/>").isEmpty)
    // A length is held to a CSS length's bound, as gnorium-python's validator holds it.
    for (unit, vertical) in [("em", false), ("mm", true), ("px", false), ("pt", true)] {
      let bound = TEIRendition.lengthBound(unit: unit)
      let dimension = vertical ? " dim='vertical'" : ""
      XCTAssertFalse(TEIRenderer.lines(in: "<p>a<space quantity='\(bound)' unit='\(unit)'\(dimension)/>b</p>").isEmpty)
      XCTAssertTrue(TEIRenderer.lines(in: "<p>a<space quantity='\(bound + 1)' unit='\(unit)'\(dimension)/>b</p>").isEmpty)
    }
    XCTAssertEqual(TEIRendition.lengthBound(unit: "em"), 64)
    XCTAssertEqual(TEIRendition.lengthBound(unit: "px"), 1024)
  }

  func testSpaceExpansionBudgetIsSharedAcrossNestedTablesAndFigures() {
    let characters = "<space quantity='4096' unit='chars'/>"
    XCTAssertEqual(TEIRenderer.lines(in: "<p>" + String(repeating: characters, count: 16) + "</p>").first?.runs.count, 16)
    let excessiveCharacters = "<table><row><cell>" + String(repeating: characters, count: 16)
      + "</cell><cell><table><row><cell>" + characters + "</cell></row></table></cell></row></table>"
    XCTAssertTrue(TEIRenderer.lines(in: excessiveCharacters).isEmpty)

    let lines = "<space quantity='128' unit='lines'/>"
    XCTAssertEqual(TEIRenderer.lines(in: String(repeating: lines, count: 8)).count, 8)
    let excessiveLines = "<figure><figDesc>" + String(repeating: lines, count: 8) + "</figDesc><head>" + lines + "</head></figure>"
    XCTAssertTrue(TEIRenderer.lines(in: excessiveLines).isEmpty)
  }

  func testTablesInheritPreservedWhitespaceAndHonorDefaultOverrides() throws {
    let markup = "<table xml:space='preserve'><head> caption  text </head><row>"
      + "<cell> a  b <table><head> nested  caption </head><row><cell> c  d </cell>"
      + "<cell xml:space='default'> e  f </cell></row></table></cell>"
      + "<cell xml:space='default'> g  h </cell></row></table>"
    let lines = TEIRenderer.lines(in: markup)
    guard case .table(let table) = try XCTUnwrap(lines.first).kind else { return XCTFail("Missing table") }
    XCTAssertEqual(table.caption.map(\.text), [" caption  text "])
    XCTAssertTrue(table.caption.flatMap(\.runs).allSatisfy(\.preserved))
    XCTAssertEqual(table.rows[0].cells[0].lines[0].text, " a  b ")
    XCTAssertTrue(table.rows[0].cells[0].lines[0].runs.allSatisfy(\.preserved))
    guard case .table(let nested) = table.rows[0].cells[0].lines[1].kind else { return XCTFail("Missing nested table") }
    XCTAssertEqual(nested.caption.map(\.text), [" nested  caption "])
    XCTAssertEqual(nested.rows[0].cells[0].lines.map(\.text), [" c  d "])
    XCTAssertTrue(nested.rows[0].cells[0].lines.flatMap(\.runs).allSatisfy(\.preserved))
    XCTAssertEqual(nested.rows[0].cells[1].lines.map(\.text), ["e f"])
    XCTAssertFalse(nested.rows[0].cells[1].lines.flatMap(\.runs).contains(where: \.preserved))
    XCTAssertEqual(table.rows[0].cells[1].lines.map(\.text), ["g h"])
  }

  func testAdjacentTitlePageAuthorsDatesAndEditionsAreSeparateBlocks() {
    let standalone = TEIRenderer.lines(in: "<titlePage><docAuthor>A</docAuthor><docDate>1888</docDate><docEdition>Second</docEdition></titlePage>")
    XCTAssertEqual(standalone.map(\.text), ["A", "1888", "Second"])
    XCTAssertTrue(standalone.allSatisfy(\.opensBlock))
    let inline = TEIRenderer.lines(in: "<titlePage><byline>by <docAuthor>A</docAuthor> in <docDate>1888</docDate>, <docEdition>Second</docEdition></byline>"
      + "<docImprint><docAuthor>B</docAuthor>, <docDate>1889</docDate>, <docEdition>Third</docEdition></docImprint></titlePage>")
    XCTAssertEqual(inline.map(\.text), ["by A in 1888, Second", "B, 1889, Third"])
  }

  /// Every `<lb/>` ends a line of the reading (user, 2026-10-10): in a
  /// note, on a title page, in a paragraph and in verse alike; a word
  /// broken with `<lb break="no"/>` still joins. The block's setting
  /// (`rend="align(center)"`) is every line's.
  func testEveryLineBreakEndsALineInNotesAndOnTitlePages() {
    let note = TEIRenderer.lines(
      in: #"<p><w>Text</w><note place="foot" rend="align(center)"><w>Bought</w><lb/><w>in</w> <w>1800</w><lb/><w>by</w><lb/><w>me</w></note></p>"#)
    XCTAssertEqual(note.map(\.text), ["Text", "Bought", "in 1800", "by", "me"])
    XCTAssertEqual(note.map(\.opensBlock), [true, true, false, false, false])
    for line in note.dropFirst() {
      guard case .note(place: "foot") = line.kind else { return XCTFail("Not a note's line: \(line.text)") }
      XCTAssertEqual(line.rend, "align(center)")
    }
    let title = TEIRenderer.lines(
      in: #"<titlePage><docTitle rend="align(center)"><titlePart type="main"><w>A</w><lb/><w>DICTIONARY</w><lb/><w>OF THE</w><lb/><w>ENGLISH</w> <w>LAN-</w><lb break="no"/><w>GUAGE</w></titlePart></docTitle></titlePage>"#)
    XCTAssertEqual(title.map(\.text), ["A", "DICTIONARY", "OF THE", "ENGLISH LAN-", "GUAGE"])
    XCTAssertEqual(title.map(\.opensBlock), [true, false, false, false, false])
    XCTAssertEqual(title.map(\.joinsPrevious), [false, false, false, false, true])
    XCTAssertEqual(title.map(\.rend), Array(repeating: "align(center)", count: 5))
  }

  /// A setting on what is no block of its own—a title page, a closer, a
  /// sentence—is its lines' setting; an inline rendition on it is not.
  func testABlockSettingCarriesThroughElementsAroundTheText() {
    let lines = TEIRenderer.lines(
      in: #"<titlePage rend="align(center)"><docTitle><titlePart><w>TITLE</w></titlePart></docTitle></titlePage><closer rend="align(right) italic"><w>Yours</w><lb/><w>truly</w></closer>"#)
    XCTAssertEqual(lines.map(\.text), ["TITLE", "Yours", "truly"])
    XCTAssertEqual(lines.map(\.rend), ["align(center)", "align(right)", "align(right)"])
    XCTAssertEqual(TEIRenderer.blockSetting(of: "italic align(left) indent(2) hanging"), "align(left) indent(2) hanging")
  }

  /// A paragraph's space (user, 2026-10-11): before a paragraph's or a
  /// stanza's first line and after its end, never between verse lines or
  /// after an `<lb/>`.
  func testParagraphsOpenTheirSpace() {
    let lines = TEIRenderer.lines(
      in: "<head>Title</head><p>one<lb/>two</p><p>three</p><lg><l>verse a</l><l>verse b</l></lg><l>after</l>")
    XCTAssertEqual(lines.map(\.text), ["Title", "one", "two", "three", "verse a", "verse b", "after"])
    XCTAssertEqual(lines.map(\.opensParagraph), [false, true, false, true, true, false, true])
  }

  /// An epigraph boxes its lines, set as a whole by its rend; a note
  /// stands a paragraph's space apart (user, 2026-10-11).
  func testAnEpigraphBoxesItsLines() {
    let lines = TEIRenderer.lines(
      in: #"<p>Before</p><epigraph rend="align(center) smaller"><cit><quote><lg><l rend="align(left)">A line<lb/></l></lg></quote><bibl rend="align(right)">Author<lb/></bibl></cit></epigraph><note type="binding" subtype="edition"><stamp>Stamp</stamp></note>"#)
    XCTAssertEqual(lines.map(\.text), ["Before", "A line", "Author", "Stamp"])
    XCTAssertEqual(lines.map(\.box), ["", "align(center) smaller", "align(center) smaller", ""])
    XCTAssertEqual(lines.map(\.rend), ["", "align(left)", "align(right)", ""])
    XCTAssertEqual(lines.map(\.opensParagraph), [true, true, true, true])
  }

  /// A phrase element's ink and size are its words' own (user, 2026-10-11):
  /// a stamp's blue reaches its runs.
  func testAStampsInkReachesItsWords() {
    let lines = TEIRenderer.lines(in: #"<note type="binding" subtype="edition"><stamp rend="color(blue) align(center)">LIBRARY</stamp></note>"#)
    XCTAssertEqual(lines.first?.runs.first?.rend, "color(blue)")
    XCTAssertEqual(TEIRenderer.typeSetting(of: "align(center) color(red) larger spaced"), "color(red) larger")
  }

  /// Copy evidence (`<note type="provenance">` and `<note type="binding" subtype="copy">`)
  /// is omitted from the reading pane and gives its bounding zones on the scan,
  /// while edition and issue binding notes render in the reading pane.
  func testAnOwnersMarkIsOmittedFromTheReadingPaneAndCopyEvidenceGivesItsZones() throws {
    let url = "https://example.org/iiif/cover/full/max/0/default.jpg"
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/>
        <facsimile><surface n="Cover" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(url)"/>\
      <zone xml:id="z-L1" ulx="100" uly="120" lrx="400" lry="160"/>\
      <zone xml:id="z-L2" ulx="150" uly="200" lrx="550" lry="250"/>\
      <zone xml:id="z-L3" ulx="160" uly="260" lrx="520" lry="300"/>\
      <zone xml:id="z-L4" ulx="200" uly="800" lrx="600" lry="840"/></surface></facsimile>
      <text><body><pb n="Cover" facs="\(url)"/>\
      <lb facs="#z-L1"/><note type="binding" subtype="copy">BOUND BY MACDONALD</note>\
      <note type="provenance"><lb facs="#z-L2"/>Ex libris<lb facs="#z-L3"/>69304</note>\
      <note type="binding" subtype="edition">HAMLET</note>\
      <note type="binding" subtype="issue" facs="#z-L4">SECOND ISSUE</note></body></text></TEI>
      """
    let page = try XCTUnwrap(TEIRenderer.pages(in: document).first)
    // The copy's binding lettering is its binder's, set in the reading as
    // well (user, 2026-10-30); the owner's mark is the scan's alone.
    XCTAssertEqual(page.lines.map(\.text), ["BOUND BY MACDONALD", "HAMLET", "SECOND ISSUE"])
    XCTAssertNil(page.ink, "a page that names no ink is in the theme's")
    let zones = TEIRenderer.elementZones(of: page)
    XCTAssertEqual(zones.count, 2)
    XCTAssertEqual(zones[0].zone, TEIZone(id: "z-L1", ulx: 100, uly: 120, lrx: 400, lry: 160))
    XCTAssertEqual(zones[1].zone, TEIZone(id: "z-L2", ulx: 150, uly: 200, lrx: 550, lry: 300))
  }

  /// A page's own ink, its <pb>'s color(NAME), is drawn as encoded (a
  /// cover's gilt lettering, yellow) unless it is black or white, the
  /// theme's (user, 2026-10-30); its lines carry none of it.
  func testAPagesOwnInkIsItsBreaksUnlessATheme() throws {
    func page(_ rend: String) throws -> TEIPage {
      try XCTUnwrap(
        TEIRenderer.pages(
          in: """
            <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/><text><body>\
            <pb n="Front cover" facs="https://example.org/iiif/cover/full/max/0/default.jpg" rend="\(rend)"/>\
            <lb/><note type="binding" subtype="copy">HAMLET</note></body></text></TEI>
            """
        ).first)
    }
    let gilt = try page("color(yellow)")
    XCTAssertEqual(gilt.ink, "yellow")
    XCTAssertEqual(gilt.lines.map(\.text), ["HAMLET"])
    XCTAssertFalse(gilt.lines.contains { $0.rend.contains("color(") || $0.runs.contains { $0.rend.contains("color(") } })
    XCTAssertNil(try page("color(black)").ink)
    XCTAssertNil(try page("color(white)").ink)
    XCTAssertNil(try page("color(gold)").ink, "no ink the rend grammar names")
    XCTAssertEqual(try page("color(gray)").ink, "gray")
  }

  /// A page's surface given its text block where the document keeps none:
  /// into the surface its figures have, its graphic sized, or a surface of
  /// its own; a derived one (the work's type area placed on a page with no main
  /// text) read back as derived and never counted in the work's type area. The
  /// surface is replaced only as found.
  func testATextBlockIsPlacedWhereTheDocumentKeepsNone() throws {
    let a = "https://example.org/iiif/a/full/max/0/default.jpg"
    let b = "https://example.org/iiif/b/full/max/0/default.jpg"
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader/>
        <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(a)"/><zone xml:id="p1-z1" ulx="100" uly="100" lrx="200" lry="200"/></surface></facsimile>
      <text><body><pb n="1" facs="\(a)"/><p>One <figure facs="#p1-z1"/></p><pb n="2" facs="\(b)"/><note type="provenance" place="bottom">2</note></body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: document)
    let first = """
      <surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(a)" width="1000px" height="1300px"/><zone xml:id="p1-z1" ulx="100" uly="100" lrx="200" lry="200"/><zone xml:id="p1-textblock" type="textblock" points="50,50 950,50 950,950 50,950" style="font-size:20px"/></surface>
      """
    let second = """
      <surface n="2" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\(b)" width="2820px" height="3781px"/><zone xml:id="p2-textblock" type="textblock" subtype="derived" points="56.23,41.1 943.77,41.1 943.77,958.9 56.23,958.9" style="font-size:45.89px"/></surface>
      """
    let standing = TEIFacsimile.surface(of: pages[0], in: document)
    var placed = try XCTUnwrap(TEIFacsimile.replacingSurface(standing, with: first, of: pages[0], in: document))
    placed = try XCTUnwrap(TEIFacsimile.replacingSurface("", with: second, of: pages[1], in: placed))
    let blocks = TEIFacsimile.textBlocks(in: placed)
    XCTAssertEqual(blocks.map(\.id), ["p1-textblock", "p2-textblock"])
    XCTAssertEqual(blocks.map(\.derived), [false, true])
    XCTAssertEqual(TEIRenderer.pages(in: placed)[1].textBlock?.derived, true)
    XCTAssertEqual(TEIFacsimile.workTypeArea(in: placed)?.body, 20)
    // Only as found: a surface changed since is refused; backwards, it is as it was.
    XCTAssertNil(TEIFacsimile.replacingSurface("", with: second, of: pages[1], in: placed))
    XCTAssertNil(TEIFacsimile.replacingSurface(standing, with: first, of: pages[0], in: placed))
    var back = try XCTUnwrap(TEIFacsimile.replacingSurface(second, with: "", of: pages[1], in: placed))
    back = try XCTUnwrap(TEIFacsimile.replacingSurface(first, with: standing, of: pages[0], in: back))
    XCTAssertEqual(back, document)
  }

  func testADocumentDeclaresItsHeaderAsWritten() throws {
    let document = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>T</title></titleStmt></fileDesc>
      <encodingDesc><tagsDecl>
      <rendition xml:id="size-1" scheme="css">font-size:0.8251rem</rendition>
      </tagsDecl></encodingDesc></teiHeader><text><body><pb n="1"/><p>A</p></body></text></TEI>
      """
    let header = try XCTUnwrap(TEIRenderer.declaredHeader(of: document))
    XCTAssertTrue(header.hasPrefix("<teiHeader>"))
    XCTAssertTrue(header.hasSuffix("</teiHeader>"))
    XCTAssertTrue(header.contains("size-1"))
    XCTAssertFalse(header.contains("<body>"))
  }

  func testAHeaderThatDeclaresNoTypeIsNone() {
    XCTAssertNil(TEIRenderer.declaredHeader(of: "<TEI><text><body/></text></TEI>"))
    XCTAssertNil(TEIRenderer.declaredHeader(of: "<TEI><teiHeader/><text/></TEI>"))
    XCTAssertNil(
      TEIRenderer.declaredHeader(
        of: "<TEI><teiHeader><fileDesc><titleStmt><title>A</title></titleStmt></fileDesc></teiHeader><text/></TEI>"))
  }

  /// A negative vertical space is lines set closer than their leading (user, 2026-10-28: a tuned "no gap" a
  /// hair below zero blanked Hamlet Q1's pages): the reading keeps it, never rejected; a negative space
  /// across a line is no reading still.
  func testANegativeVerticalSpaceIsKeptAndANegativeSpaceInALineIsNot() {
    let closer = TEIRenderer.lines(
      in: #"<p>A<lb/><space dim="vertical" quantity="-0.25" unit="em"/>B<lb/></p>"#)
    XCTAssertTrue(closer.contains { line in
      if case .space(let quantity, let unit) = line.kind { return quantity == -0.25 && unit == "em" }
      return false
    })
    XCTAssertTrue(closer.contains { $0.text.contains("B") })
    XCTAssertTrue(TEIRenderer.lines(in: #"<p>A<space quantity="-2" unit="chars"/>B<lb/></p>"#).isEmpty)
  }

  /// A figure keeps its own setting (gnorium-python `base_tei._figure`: its size and its place across as the
  /// scan has them, user 2026-10-28), which a page set in its type area draws it at.
  func testAFigureKeepsItsSizeAndPlace() {
    let lines = TEIRenderer.lines(
      in: ##"<figure facs="#z-fig-1" style="inline-size:18.9em;block-size:21.5em;margin-inline-start:8.9em"/><p>A</p>"##)
    let figure = lines.first { line in
      if case .figure = line.kind { return true }
      return false
    }
    XCTAssertNotNil(figure)
    for token in ["css:inline-size=18.9em", "css:block-size=21.5em", "css:margin-inline-start=8.9em"] {
      XCTAssertTrue(figure?.rend.contains(token) ?? false, figure?.rend ?? "")
    }
  }

  /// On a measured page (its line breaks name their zones) a speaker, a
  /// stage direction, a verse line, a stanza and a head name what their
  /// words are and never move a line (user, 2026-11-09): the page encoded
  /// as a play sets the same lines, each at its zone, with the same
  /// openings and spacing, as the flat page Calibration measured. Off a
  /// measured page each is still a block of its own.
  func testSpeechAndVerseNeverMoveAMeasuredLine() throws {
    let zones = (1...5).map { ##"<zone xml:id="z-L\##($0)" ulx="100" uly="\##($0 * 50)" lrx="900" lry="\##($0 * 50 + 40)"/>"## }
      .joined()
    func page(_ body: String) -> String {
      ##"<TEI xmlns="http://www.tei-c.org/ns/1.0"><facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"##
        + zones + ##"</surface></facsimile><text><body><pb n="p. 8" facs="https://example.org/iiif/p8/full/max/0/default.jpg"/>"##
        + body + "</body></text></TEI>"
    }
    let flat = page(
      ##"<ab><lb facs="#z-L1"/>Hor. Most like, it harrowes me with feare,"##
        + ##"<lb facs="#z-L2"/>Mar. It would be spoke too."##
        + ##"<lb facs="#z-L3"/>Enter the Ghoſt."##
        + ##"<lb facs="#z-L4"/>The Tragedie of Hamlet"##
        + ##"<lb facs="#z-L5"/>To be, or not to be, I there's the point,</ab>"##)
    let encoded = page(
      ##"<ab><sp who="#horatio"><lb facs="#z-L1"/><speaker rend="italic">Hor.</speaker> Most like, it harrowes me with feare,</sp>"##
        + ##"<sp who="#marcellus"><lb facs="#z-L2"/><speaker>Mar.</speaker> It would be spoke too.</sp>"##
        + ##"<stage type="entrance"><lb facs="#z-L3"/>Enter the Ghoſt.</stage>"##
        + ##"<head><lb facs="#z-L4"/>The Tragedie of Hamlet</head>"##
        + ##"<lg type="stanza"><l><lb facs="#z-L5"/>To be, or not to be, I there's the point,</l></lg></ab>"##)
    let flatLines = try XCTUnwrap(TEIRenderer.pages(in: flat).first).lines
    let encodedLines = try XCTUnwrap(TEIRenderer.pages(in: encoded).first).lines
    func shape(_ lines: [TEILine]) -> [String] {
      lines.map { "\($0.zone?.id ?? "-")|\($0.text)|\($0.opensParagraph)|\($0.sharesLine)|\($0.rend)" }
    }
    XCTAssertEqual(shape(encodedLines), shape(flatLines))
    XCTAssertEqual(encodedLines.count, 5)
    // The speaker's own type is its words', never a block's.
    let prefix = try XCTUnwrap(encodedLines[0].runs.first { $0.text.contains("Hor.") })
    XCTAssertTrue(prefix.rend.contains("italic"), prefix.rend)
    // Unmeasured, a speaker is a line of its own, as a TEI reader sets it.
    let unmeasured = try XCTUnwrap(TEIRenderer.pages(in: page(
      ##"<sp><speaker>Hor.</speaker><p>Most like.</p></sp>"##)).first).lines
    XCTAssertEqual(unmeasured.map(\.text), ["Hor.", "Most like."])
  }

  /// A page as an arbitration renders its draft (gnorium-python
  /// `TEIReview.with_lines`): its lines name their zones by the ids its
  /// document gives them (`p11-z-L1`, prefixed with the page's place), its
  /// surface holding them after its text block. It is measured: each line at
  /// its zone, each speaker in its line (dev, 2026-11-10: a p. 5 arbitration
  /// cleared its `<lb facs>`, and its page rendered unmeasured, a speaker a
  /// line of its own).
  func testAnArbitrationsDraftNamingItsDocumentsZoneIdsIsMeasured() throws {
    func page(_ body: String) -> String {
      ##"<TEI xmlns="http://www.tei-c.org/ns/1.0"><facsimile><surface n="p. 5" ulx="0" uly="0" lrx="1000" lry="1000">"##
        + ##"<graphic url="https://cdm16003.contentdm.oclc.org/iiif/2/p15150coll3:1370/full/max/0/default.jpg" width="6313px" height="6642px"/>"##
        + ##"<zone xml:id="textblock" type="textblock" points="310.39,165.84 672.65,160.23 683.27,778.25 321,783.87" style="font-size:85.47px"/>"##
        + ##"<zone xml:id="p11-z-L1" ulx="434" uly="161" lrx="562" lry="182"/>"##
        + ##"<zone xml:id="p11-z-L2" ulx="338" uly="185" lrx="516" lry="205"/>"##
        + ##"<zone xml:id="p11-z-L3" ulx="338" uly="201" lrx="508" lry="219"/></surface></facsimile><text><body>"##
        + ##"<pb n="p. 5" facs="https://cdm16003.contentdm.oclc.org/iiif/2/p15150coll3:1370/full/max/0/default.jpg"/>"##
        + body + "</body></text></TEI>"
    }
    let draft = page(
      ##"<lb facs="#p11-z-L1"/><fw type="header" rend="align(center)">Prince of Denmarke.</fw>"##
        + ##"<sp who="#marcellus"><lb facs="#p11-z-L2"/><speaker rend="italic">Mar.</speaker> Is it not like the King?</sp>"##
        + ##"<sp who="#horatio"><lb facs="#p11-z-L3"/><speaker rend="italic">Hor.</speaker> As thou art to thy ſelfe,</sp>"##)
    let lines = try XCTUnwrap(TEIRenderer.pages(in: draft).first).lines
    XCTAssertEqual(lines.map { $0.zone?.id ?? "-" }, ["p11-z-L1", "p11-z-L2", "p11-z-L3"])
    XCTAssertEqual(lines.map(\.text), ["Prince of Denmarke.", "Mar. Is it not like the King?", "Hor. As thou art to thy ſelfe,"])
    // Its line breaks cleared, it is unmeasured: each speaker a line of its own.
    let cleared = try XCTUnwrap(TEIRenderer.pages(in: draft.replacingOccurrences(
      of: ##"<lb facs="#p11-z-L(\d)"/>"##, with: "<lb/>", options: .regularExpression)).first).lines
    XCTAssertTrue(cleared.allSatisfy { $0.zone == nil })
    XCTAssertTrue(cleared.contains { $0.text == "Mar." }, cleared.map(\.text).joined(separator: " | "))
  }

  /// The valid measured form of a speech (user, 2026-11-09): the block's
  /// settings move from its `<ab rendition>` onto its `<sp rendition>`, its
  /// prefix run in before its first line, each verse line an `<l>` opening
  /// with its line break: every line set where the measured `<ab>` set it,
  /// in the same settings.
  func testASpeechCarryingItsBlocksSettingsSetsItsLinesAsTheBlockDid() throws {
    let zones = (1...3).map { ##"<zone xml:id="z-L\##($0)" ulx="100" uly="\##($0 * 50)" lrx="900" lry="\##($0 * 50 + 40)"/>"## }
      .joined()
    let header = ##"<teiHeader><encodingDesc><tagsDecl><rendition xml:id="size-4" scheme="css">font-size:0.9em;text-indent:1em;margin-block-start:0.5em</rendition></tagsDecl></encodingDesc></teiHeader>"##
    func page(_ body: String) -> String {
      ##"<TEI xmlns="http://www.tei-c.org/ns/1.0">"## + header
        + ##"<facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"##
        + zones + ##"</surface></facsimile><text><body><pb n="p. 8" facs="https://example.org/iiif/p8/full/max/0/default.jpg"/>"##
        + body + "</body></text></TEI>"
    }
    let flat = page(
      ##"<ab rendition="#size-4" rend="align(left)"><lb facs="#z-L1"/>Hor. Most like, it harrowes me with feare,"##
        + ##"<lb facs="#z-L2"/>And wonder: it would be spoke too."##
        + ##"<lb facs="#z-L3"/>Question it Horatio.</ab>"##)
    let speech = page(
      ##"<sp who="#horatio" rendition="#size-4" rend="align(left)"><lb facs="#z-L1"/><speaker rend="italic">Hor.</speaker> "##
        + ##"<l>Most like, it harrowes me with feare,</l>"##
        + ##"<l><lb facs="#z-L2"/>And wonder: it would be spoke too.</l>"##
        + ##"<l><lb facs="#z-L3"/>Question it Horatio.</l></sp>"##)
    let flatLines = try XCTUnwrap(TEIRenderer.pages(in: flat).first).lines
    let speechLines = try XCTUnwrap(TEIRenderer.pages(in: speech).first).lines
    func shape(_ lines: [TEILine]) -> [String] {
      lines.map {
        "\($0.zone?.id ?? "-")|\($0.text)|\($0.opensBlock)|\($0.opensParagraph)|\($0.sharesLine)|\($0.rend)|\($0.box)"
      }
    }
    XCTAssertEqual(shape(speechLines), shape(flatLines))
    XCTAssertEqual(speechLines.count, 3)
    // The block's settings reach its lines in both.
    XCTAssertTrue(flatLines[0].rend.contains("size-4") || flatLines[0].rend.contains("font-size"), flatLines[0].rend)
  }

  /// A prose speech on a measured page, its prefix run in before its
  /// block (`<sp rendition><lb/><speaker>Fort.</speaker> <ab>…</ab></sp>`,
  /// or a `<p>`): the block continues the prefix's line, every line where
  /// the measured block set it (user, 2026-11-09: Hamlet Q1 p. 8). Only a
  /// line break places a line.
  func testARunInProseSpeechKeepsItsMeasuredLines() throws {
    let zones = (1...3).map { ##"<zone xml:id="z-L\##($0)" ulx="100" uly="\##($0 * 50)" lrx="900" lry="\##($0 * 50 + 40)"/>"## }
      .joined()
    let header = ##"<teiHeader><encodingDesc><tagsDecl><rendition xml:id="size-2" scheme="css">font-size:1em;text-indent:1.352em</rendition></tagsDecl></encodingDesc></teiHeader>"##
    func page(_ body: String) -> String {
      ##"<TEI xmlns="http://www.tei-c.org/ns/1.0">"## + header
        + ##"<facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"## + zones
        + ##"</surface></facsimile><text><body><pb n="p. 8" facs="https://example.org/iiif/p8/full/max/0/default.jpg"/>"##
        + body + "</body></text></TEI>"
    }
    func shape(_ tei: String) throws -> [String] {
      try XCTUnwrap(TEIRenderer.pages(in: tei).first).lines.map {
        "\($0.zone?.id ?? "-")|\($0.text)|\($0.opensBlock)|\($0.opensParagraph)|\($0.rend)"
      }
    }
    let flat = try shape(page(
      ##"<ab rendition="#size-2"><lb facs="#z-L1"/>Fort. Where is this bloudy fight?</ab>"##
        + ##"<ab rendition="#size-2"><lb facs="#z-L2"/>Amb. So iarring and so dismall,<lb facs="#z-L3"/>and so abrupt.</ab>"##))
    for block in ["ab", "p"] {
      let speech = try shape(page(
        ##"<sp who="#fortinbras" rendition="#size-2"><lb facs="#z-L1"/><speaker>Fort.</speaker> "##
          + "<\(block)>Where is this bloudy fight?</\(block)></sp>"
          + ##"<sp who="#ambassador" rendition="#size-2"><lb facs="#z-L2"/><speaker>Amb.</speaker> "##
          + "<\(block)>So iarring and so dismall,<lb facs=\"#z-L3\"/>and so abrupt.</\(block)></sp>"))
      XCTAssertEqual(speech, flat, block)
    }
  }

  /// A line set in two parts on a measured page—a speech and its exit, the
  /// exit's part its own zone, set at its measured margin (`<seg facs>`)—
  /// is one line, however speech and stage wrap them: only a line break
  /// places a line, and a block that opens within a line holding no break
  /// of its own continues it (dev, 2026-11-10: Hamlet Q1 p. 6's "2. Tis
  /// heere." and its "exit Ghoſt.", the exit moved into an `<ab>` of its
  /// own after the speech, set a line low and every line after it).
  func testAPartOfAMeasuredLineStaysOnItsLineWhateverWrapsIt() throws {
    let zones = ##"<zone xml:id="z-L1" ulx="100" uly="50" lrx="300" lry="90"/>"##
      + ##"<zone xml:id="z-L1-2" ulx="600" uly="50" lrx="800" lry="90"/>"##
      + ##"<zone xml:id="z-L2" ulx="100" uly="100" lrx="900" lry="140"/>"##
    func shape(_ body: String) throws -> [String] {
      let tei = ##"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"##
        + ##"<rendition xml:id="size-4" scheme="css">font-size:0.999rem</rendition>"##
        + ##"<rendition xml:id="leading-4" scheme="css">line-height:1.2607rem</rendition>"##
        + ##"<rendition xml:id="indent-4" scheme="css">text-indent:1.4rem</rendition>"##
        + ##"</tagsDecl></encodingDesc></teiHeader><facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"##
        + zones + ##"</surface></facsimile><text><body><pb n="p. 6" facs="https://example.org/iiif/p6/full/max/0/default.jpg"/>"##
        + body + "</body></text></TEI>"
      return try XCTUnwrap(TEIRenderer.pages(in: tei).first).lines.map {
        "\($0.zone?.id ?? "-")|\($0.text)|\($0.sharesLine)|\($0.opensBlock)|\($0.rend)"
      }
    }
    let exit = ##"<seg facs="#z-L1-2" rend="align(left)" style="margin-inline-start:14rem">exit Ghoſt.</seg>"##
    let set = ##" rendition="#size-4 #leading-4 #indent-4""##
    let next = ##"<ab rendition="#size-4 #leading-4"><lb facs="#z-L2"/>Hor. Tis heere.</ab>"##
    let flat = try shape("<ab" + set + ##"><lb facs="#z-L1"/>2. Tis heere."## + exit + "</ab>" + next)
    let staged = try shape(
      ##"<sp who="#barnardo""## + set + ##"><lb facs="#z-L1"/><speaker>2.</speaker> <l>Tis heere.</l><stage>"##
        + exit + "</stage></sp>" + next)
    let blocked = try shape(
      ##"<sp who="#barnardo""## + set + ##"><lb facs="#z-L1"/><speaker>2.</speaker> <l>Tis heere.</l></sp>"##
        + ##"<ab rendition="#size-4 #leading-4">"## + exit + "</ab>" + next)
    XCTAssertEqual(staged, flat)
    XCTAssertEqual(blocked, flat)
  }

  /// A speech's first-line indent is its first line's alone: a verse line
  /// that begins a later line of it, setting no indent of its own, is set
  /// flush, as the same line a later line of a block is (dev, 2026-11-10:
  /// Hamlet Q1 p. 6's "This preſent obiect made probation.", the last of
  /// Horatio's verse lines, was set at his speech's 1.6 em).
  func testAVerseLineBegunInASpeechTakesNoneOfItsFirstLineIndent() throws {
    let zones = (1...4).map { ##"<zone xml:id="z-L\##($0)" ulx="100" uly="\##($0 * 50)" lrx="900" lry="\##($0 * 50 + 40)"/>"## }
      .joined()
    func shape(_ body: String) throws -> [String] {
      let tei = ##"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"##
        + ##"<rendition xml:id="size-4" scheme="css">font-size:0.999rem</rendition>"##
        + ##"<rendition xml:id="leading-4" scheme="css">line-height:1.2607rem</rendition>"##
        + ##"<rendition xml:id="indent-2" scheme="css">text-indent:0.2807rem</rendition>"##
        + ##"<rendition xml:id="indent-4" scheme="css">text-indent:1.5858rem</rendition>"##
        + ##"</tagsDecl></encodingDesc></teiHeader><facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"##
        + zones + ##"</surface></facsimile><text><body><pb n="p. 6" facs="https://example.org/iiif/p6/full/max/0/default.jpg"/>"##
        + body + "</body></text></TEI>"
      // Each line and the indent it is set at: a block's first line its text-indent, a later line none.
      return try XCTUnwrap(TEIRenderer.pages(in: tei).first).lines.map { line in
        let indent = line.rend.split(separator: " ").first { $0.hasPrefix("css:text-indent=") }
        return "\(line.zone?.id ?? "-")|\(line.text)|\(line.opensBlock ? indent.map(String.init) ?? "flush" : "flush")"
      }
    }
    let flat = try shape(
      ##"<ab rendition="#size-4 #leading-4 #indent-4"><lb facs="#z-L1"/>Hor. And then it faded,</ab>"##
        + ##"<ab rendition="#size-4 #leading-4 #indent-2"><lb facs="#z-L2"/>To his confines,<lb facs="#z-L3"/>This preſent obiect.</ab>"##
        + ##"<ab rendition="#size-4 #leading-4 #indent-4"><lb facs="#z-L4"/>Mar. It faded.</ab>"##)
    let speech = try shape(
      ##"<sp who="#horatio" rendition="#size-4 #leading-4 #indent-4"><lb facs="#z-L1"/><speaker>Hor.</speaker> <l>And then it faded,</l>"##
        + ##"<l rendition="#size-4 #leading-4 #indent-2"><lb facs="#z-L2"/>To his confines,</l>"##
        + ##"<l rendition="#size-4 #leading-4"><lb facs="#z-L3"/>This preſent obiect.</l></sp>"##
        + ##"<sp who="#marcellus" rendition="#size-4 #leading-4 #indent-4"><lb facs="#z-L4"/><speaker>Mar.</speaker> <l>It faded.</l></sp>"##)
    XCTAssertEqual(speech, flat)
  }

  /// Measured lines take the leading of the nearest rendition that sets
  /// them, whatever speech or verse wraps them (user, 2026-11-10: Hamlet Q1
  /// p. 5, its `<ab rendition="#leading-…">` moved onto `<sp>`, `<lg>` or
  /// `<l>`, set every line at the default leading and ran 13 em past the
  /// type area). The page is laid out over lines, as documents are: white
  /// space between its elements neither begins a line nor sets one.
  func testMeasuredLinesKeepTheirBlocksLeadingWhateverSpeechAndVerseWrapThem() throws {
    let zones = (1...3).map { ##"<zone xml:id="z-L\##($0)" ulx="100" uly="\##($0 * 50)" lrx="900" lry="\##($0 * 50 + 40)"/>"## }
      .joined()
    let header = "<teiHeader><encodingDesc><tagsDecl>"
      + ##"<rendition xml:id="size-4" scheme="css">font-size:0.999rem</rendition>"##
      + ##"<rendition xml:id="leading-4" scheme="css">line-height:1.2607rem</rendition>"##
      + ##"<rendition xml:id="indent-3" scheme="css">text-indent:1.3433rem</rendition>"##
      + "</tagsDecl></encodingDesc></teiHeader>"
    func page(_ body: String) -> String {
      ##"<TEI xmlns="http://www.tei-c.org/ns/1.0">"## + header
        + ##"<facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">"## + zones
        + ##"</surface></facsimile><text><body><pb n="p. 5" facs="https://example.org/iiif/p5/full/max/0/default.jpg"/>\##n"##
        + body + "\n</body></text></TEI>"
    }
    func lines(_ body: String) throws -> [TEILine] { try XCTUnwrap(TEIRenderer.pages(in: page(body)).first).lines }
    func shape(_ lines: [TEILine]) -> [String] {
      lines.map { "\($0.zone?.id ?? "-")|\($0.text)|\($0.opensBlock)|\($0.opensParagraph)|\($0.sharesLine)|\($0.rend)" }
    }
    let settings = ##"rendition="#size-4 #leading-4 #indent-3""##
    let flat = try lines(
      ##"<ab \##(settings)><lb facs="#z-L1"/>Mar. Is it not like the King?</ab>\##n"##
        + ##"<ab \##(settings)><lb facs="#z-L2"/>Hor. As thou art to thy ſelfe,\##n<lb facs="#z-L3"/>Such was the very armor</ab>"##)
    // Each block opens its speech, every line at its leading.
    XCTAssertEqual(flat.map(\.opensBlock), [true, true, false])
    XCTAssertTrue(flat.allSatisfy { $0.rend.contains("css:line-height=1.262em") }, shape(flat).joined(separator: "\n"))
    let encodings = [
      // The block's settings on the speech, its lines verse lines.
      ##"<sp who="#marcellus" \##(settings)><lb facs="#z-L1"/><speaker>Mar.</speaker> <l>Is it not like the King?</l></sp>\##n"##
        + ##"<sp who="#horatio" \##(settings)><lb facs="#z-L2"/><speaker>Hor.</speaker> <l>As thou art to thy ſelfe,</l>\##n"##
        + ##"<l><lb facs="#z-L3"/>Such was the very armor</l></sp>"##,
      // On the speech, its lines in a stanza.
      ##"<sp who="#marcellus" \##(settings)><lb facs="#z-L1"/><speaker>Mar.</speaker> <lg><l>Is it not like the King?</l></lg></sp>\##n"##
        + ##"<sp who="#horatio" \##(settings)><lb facs="#z-L2"/><speaker>Hor.</speaker> <lg><l>As thou art to thy ſelfe,</l>\##n"##
        + ##"<l><lb facs="#z-L3"/>Such was the very armor</l></lg></sp>"##,
      // On the stanza a speech holds.
      ##"<sp who="#marcellus"><lg \##(settings)><l><lb facs="#z-L1"/><speaker>Mar.</speaker> Is it not like the King?</l></lg></sp>\##n"##
        + ##"<sp who="#horatio"><lg \##(settings)><l><lb facs="#z-L2"/><speaker>Hor.</speaker> As thou art to thy ſelfe,</l>\##n"##
        + ##"<l><lb facs="#z-L3"/>Such was the very armor</l></lg></sp>"##,
    ]
    for encoded in encodings {
      XCTAssertEqual(shape(try lines(encoded)), shape(flat), encoded)
    }
    // On every verse line: each line at its leading.
    let everyLine = try lines(
      ##"<sp who="#marcellus"><lb facs="#z-L1"/><speaker>Mar.</speaker> <l rendition="#size-4 #leading-4">Is it not like the King?</l></sp>\##n"##
        + ##"<sp who="#horatio"><l rendition="#size-4 #leading-4"><lb facs="#z-L2"/><speaker>Hor.</speaker> As thou art to thy ſelfe,</l>\##n"##
        + ##"<l rendition="#size-4 #leading-4"><lb facs="#z-L3"/>Such was the very armor</l></sp>"##)
    XCTAssertEqual(everyLine.map(\.text), flat.map(\.text))
    XCTAssertTrue(
      everyLine[1...].allSatisfy { $0.rend.contains("css:line-height=1.262em") }, shape(everyLine).joined(separator: "\n"))
    // A verse line begun within its line (after its run-in prefix) moves nothing: only its type is its words'.
    XCTAssertEqual(everyLine[0].rend, "")
    let run = try XCTUnwrap(everyLine[0].runs.first { $0.text.contains("King") })
    XCTAssertTrue(run.rend.contains("css:font-size"), run.rend)
    // A second speech begun within the line sets nothing of it.
    let shared = try lines(
      ##"<sp who="#marcellus" \##(settings)><lb facs="#z-L1"/><speaker>Mar.</speaker> Is it,</sp> "##
        + ##"<sp who="#horatio" rendition="#leading-4"><speaker>Hor.</speaker> No.</sp>"##)
    XCTAssertEqual(shared.map(\.text), ["Mar. Is it, Hor. No."])
    XCTAssertEqual(shared[0].rend, flat[0].rend)
    // A speech whose vertical space stands before its first line break begins a line too.
    let spaced = try lines(
      ##"<ab \##(settings)><lb facs="#z-L1"/>Mar. Is it not like the King?</ab>\##n"##
        + ##"<sp who="#horatio" \##(settings)><space dim="vertical" quantity="0.45" unit="em"/><lb facs="#z-L2"/>"##
        + ##"<speaker>Hor.</speaker> <l>As thou art to thy ſelfe,</l></sp>"##)
    let horatio = try XCTUnwrap(spaced.last)
    XCTAssertEqual(horatio.rend, flat[1].rend)
    XCTAssertTrue(horatio.opensBlock)
  }

  /// A block's rend as its words carry it inside a measured line: its
  /// type and ink, never what places it.
  func testABlocksRendAsInlineKeepsTypeAndInkOnly() {
    XCTAssertEqual(
      TEIRendition.asInline("italic color(red) align(center) css:margin-block-start=1em css:text-indent=2em css:font-size=0.8em"),
      "italic color(red) css:font-size=0.8em")
  }
}

