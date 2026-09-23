import XCTest
import XMLUtilities

final class TEIRendererTests: XCTestCase {
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

  func testTeXRemainsOneRunBetweenSurroundingText() {
    let lines = TEIRenderer.lines(
      in: #"<p>Let <formula notation="TeX">x_{a.b}=\frac{u+v}{w}</formula> hold.</p>"#)
    XCTAssertEqual(lines.count, 1)
    XCTAssertEqual(lines[0].runs.map(\.text), ["Let ", #"x_{a.b}=\frac{u+v}{w}"#, " hold."])
    guard case .tex(display: false) = lines[0].runs[1].kind else {
      return XCTFail("Lost inline formula")
    }
  }

  func testDisplayMathRetainsXMLUnescapedMatrixSeparators() {
    let lines = TEIRenderer.lines(
      in:
        #"<p><formula notation="latex" rend="display">\begin{matrix}a &amp; b \\ c &amp; d\end{matrix}</formula></p>"#
    )
    XCTAssertEqual(lines[0].runs[0].text, #"\begin{matrix}a & b \\ c & d\end{matrix}"#)
    guard case .tex(display: true) = lines[0].runs[0].kind else {
      return XCTFail("Lost display formula")
    }
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

  func testTableInsideFigureIsNotSwallowedByDescription() {
    let lines = TEIRenderer.lines(
      in:
        "<figure bbox=\"10 20 30 40\"><figDesc>Device</figDesc><head>Original caption</head><table><row><cell>OXOX</cell></row></table></figure>"
    )
    XCTAssertEqual(lines.map(\.text), ["Device", "Original caption", "OXOX"])
    guard case .figure(_, let bbox) = lines[0].kind else { return XCTFail("Missing crop") }
    XCTAssertEqual(bbox, "10 20 30 40")
    guard case .table = lines[2].kind else { return XCTFail("Missing figure table") }
  }

  func testFigureWithoutDescriptionStillCarriesItsCrop() {
    let lines = TEIRenderer.lines(in: "<figure bbox=\"10 20 30 40\"/>")
    XCTAssertEqual(lines.count, 1)
    guard case .figure(_, let bbox) = lines.first?.kind else { return XCTFail("Missing figure") }
    XCTAssertEqual(bbox, "10 20 30 40")
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
}
