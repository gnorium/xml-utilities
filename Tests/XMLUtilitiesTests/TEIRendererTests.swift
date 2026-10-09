import XCTest
import XMLUtilities

final class TEIRendererTests: XCTestCase {
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
    guard case .figure(_, let zone) = lines[0].kind else { return XCTFail("Missing crop") }
    XCTAssertEqual(zone?.corners, "10 20 40 60")
    guard case .table = lines[2].kind else { return XCTFail("Missing figure table") }
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

  func testFigureWithoutDescriptionStillCarriesItsCrop() throws {
    let lines = TEIRenderer.lines(in: Self.facsimile + "<figure facs=\"#z1\"/>")
    XCTAssertEqual(lines.count, 1)
    guard case .figure(_, let zone) = lines.first?.kind else { return XCTFail("Missing figure") }
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
    guard case .figure(_, let zone) = pages[0].lines[0].kind else { return XCTFail("Missing figure") }
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
    let laid = TEIFacsimile.laying(
      page: page, fragment: ##"<figure facs="#z1"/><p><w><hi rend="initial" facs="#z2">A</hi>nd</w></p>"##, over: old,
      position: 2, in: document)
    XCTAssertEqual(Set(TEIFacsimile.zones(in: TEIFacsimile.blocks(in: laid)).keys), ["p1-z1", "p2-z1", "p2-z2"])
    XCTAssertFalse(laid.contains(#"ulx="5""#))
    let pages = TEIRenderer.pages(in: laid)
    guard case .figure(_, let zone) = pages[1].lines[0].kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(zone?.corners, "100 100 300 300")
    XCTAssertEqual(pages[1].lines[1].runs[0].zone?.corners, "10 10 20 30")
    guard case .figure(_, let first) = pages[0].lines[0].kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(first?.corners, "1 1 2 2")
    XCTAssertTrue(laid.contains(#"<graphic url="https://example.org/iiif/b/full/1300,/0/default.jpg"/><zone xml:id="p2-z1""#))
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
    XCTAssertEqual(TEIRenderer.readingWeight(of: markup), "Outer Inner X".count)
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
      TEIRenderer.readingWeight(of: tagged.markup),
      TEIRenderer.readingWeight(of: #"<pb n="7"/><p>Been thus,<lb/>encountred:</p>"#))
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
    XCTAssertEqual(spaced.map(\.text), ["one   two"])
    XCTAssertTrue(spaced[0].runs.contains { $0.preserved && $0.text == "   " })

    let preserved = TEIRenderer.lines(in: "<p>\n  <seg xml:space=\"preserve\">a  b</seg>\n  <w>c</w>   <w>d</w>\n</p>")
    XCTAssertEqual(preserved.map(\.text), ["a  b c d"])

    let lines = TEIRenderer.lines(in: #"<p><w>above</w></p><space quantity="2" unit="lines"/><p><w>below</w></p>"#)
    XCTAssertEqual(lines.map(\.text), ["above", " ", " ", "below"])
  }

  func testTheFormatterLeavesPreservedWhiteSpaceAlone() {
    let markup = "<div><ab xml:space=\"preserve\"><w>a</w>  <w>b</w>\n   <lb/></ab><p><w>c</w></p></div>"
    let pretty = XMLFormatter.prettified(markup)
    XCTAssertTrue(pretty.contains("<ab xml:space=\"preserve\"><w>a</w>  <w>b</w>\n   <lb/></ab>"), pretty)
  }

  /// A work laid in blank past its reading (user, 2026-10-09): four pages
  /// read of six canvases. The document's closing structure after the last
  /// page break belongs to no page, so the sixth canvas reads empty and
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
  }

  func testSpaceExpansionBudgetIsSharedAcrossNestedTablesAndFigures() {
    let characters = "<space quantity='4096' unit='chars'/>"
    XCTAssertEqual(TEIRenderer.lines(in: "<p>" + String(repeating: characters, count: 16) + "</p>").first?.text.count, 65_536)
    let excessiveCharacters = "<table><row><cell>" + String(repeating: characters, count: 16)
      + "</cell><cell><table><row><cell>" + characters + "</cell></row></table></cell></row></table>"
    XCTAssertTrue(TEIRenderer.lines(in: excessiveCharacters).isEmpty)

    let lines = "<space quantity='128' unit='lines'/>"
    XCTAssertEqual(TEIRenderer.lines(in: String(repeating: lines, count: 8)).count, 1_024)
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
}
