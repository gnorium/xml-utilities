import XCTest
import XMLUtilities

final class TEIHeaderRendererTests: XCTestCase {
  /// A copy of design-notes/skeat/header.xml (Skeat's declared scale), as
  /// the renditions of a header.
  static let skeatRenditions = #"""
    <rendition xml:id="text-block" scheme="css" selector="text">font-size:45.89px;inline-size:54.54em;block-size:75.62em;margin:3.99em;max-inline-size:61.45em</rendition>
    <rendition xml:id="size-1" scheme="css">font-size:0.8251rem</rendition>
    <rendition xml:id="size-2" scheme="css">font-size:1.0029rem</rendition>
    <rendition xml:id="size-3" scheme="css">font-size:1.2025rem</rendition>
    <rendition xml:id="leading-1" scheme="css">line-height:1.2857rem</rendition>
    <rendition xml:id="leading-2" scheme="css">line-height:1.569rem</rendition>
    <rendition xml:id="indent-1" scheme="css">text-indent:0.9588rem</rendition>
    <rendition xml:id="gap-1" scheme="css">margin-block-start:0.7845rem</rendition>
    <rendition xml:id="gap-16" scheme="css">margin-block-start:12.5519rem</rendition>
    """#

  static let skeat = """
    <teiHeader xmlns="http://www.tei-c.org/ns/1.0">
      <fileDesc>
        <titleStmt><title>An Etymological Dictionary of the English Language</title><author>Walter W. Skeat</author></titleStmt>
        <extent><measure unit="image" quantity="780"/><measure unit="year" type="span" atLeast="1879" atMost="1882"/></extent>
        <publicationStmt><publisher>Gnorium</publisher><idno type="sha256">abc123</idno></publicationStmt>
        <sourceDesc><bibl>Oxford: Clarendon Press, 1882</bibl></sourceDesc>
      </fileDesc>
      <encodingDesc>
        <samplingDecl><p>Every image was measured; none was sampled.</p></samplingDecl>
        <tagsDecl>
    \(skeatRenditions)
          <namespace name="http://www.tei-c.org/ns/1.0"><tagUsage gi="pb" occurs="780"/><tagUsage gi="hi"/></namespace>
        </tagsDecl>
        <appInfo>
          <application ident="layout-analysis" version="3"><label>sha256:deadbeef</label></application>
          <application ident="cluster" version="1"/>
        </appInfo>
      </encodingDesc>
      <profileDesc><langUsage><language ident="eng" usage="97">English</language><language ident="enm"/></langUsage></profileDesc>
      <revisionDesc><change when="2026-10-18" who="#gnorium">Calibrated &amp; filed.</change></revisionDesc>
    </teiHeader>
    """

  private func entry(_ label: String, in entries: [TEIHeaderEntry]) throws -> TEIHeaderEntry {
    try XCTUnwrap(entries.first { $0.label == label }, "no \(label) entry in \(entries.map(\.label))")
  }

  func testTitleStmtAndExtent() throws {
    let entries = TEIHeaderRenderer.entries(of: Self.skeat)
    XCTAssertEqual(try entry("Title", in: entries).value, "An Etymological Dictionary of the English Language")
    XCTAssertEqual(try entry("Author", in: entries).value, "Walter W. Skeat")
    let extent = try entry("Extent", in: entries)
    XCTAssertEqual(extent.entries.map(\.label), ["Image", "Year span"])
    XCTAssertEqual(extent.entries.map(\.value), ["780", "1879–1882"])
    XCTAssertEqual(try entry("Publisher", in: entries).value, "Gnorium")
    XCTAssertEqual(try entry("Identifier (sha256)", in: entries).value, "abc123")
    XCTAssertEqual(try entry("Source", in: entries).value, "Oxford: Clarendon Press, 1882")
  }

  func testScaleIsATablePerAxisInOrderWithEmValues() throws {
    let scale = try entry("Scale", in: TEIHeaderRenderer.entries(of: Self.skeat))
    XCTAssertEqual(scale.tables.map(\.title), ["Size", "Leading", "Indent", "Gap"])
    XCTAssertEqual(scale.tables[0].columns, ["Step", "Em"])
    XCTAssertEqual(scale.tables[0].rows, [["size-1", "0.8251"], ["size-2", "1.0029"], ["size-3", "1.2025"]])
    XCTAssertEqual(scale.tables[3].rows.last, ["gap-16", "12.5519"])
    let frame = try XCTUnwrap(scale.entries.first)
    XCTAssertEqual(frame.label, "Frame")
    XCTAssertEqual(frame.paragraphs.first, "Font size: 45.89px")
    XCTAssertTrue(frame.paragraphs.contains("Max inline size: 61.45em"))
  }

  func testTrackingFollowsGapAndCountsAreOptional() throws {
    let header = """
      <teiHeader><fileDesc><titleStmt><title>T</title></titleStmt></fileDesc><encodingDesc><tagsDecl>
      <rendition xml:id="tracking-1" scheme="css" n="42">letter-spacing:0.131rem</rendition>
      <rendition xml:id="gap-1" scheme="css">margin-block-start:0.5rem</rendition>
      <rendition xml:id="tracking-2" scheme="css">letter-spacing:-0.02rem</rendition>
      </tagsDecl></encodingDesc></teiHeader>
      """
    let scale = try entry("Scale", in: TEIHeaderRenderer.entries(of: header))
    XCTAssertEqual(scale.tables.map(\.title), ["Gap", "Tracking"])
    XCTAssertEqual(scale.tables[0].columns, ["Step", "Em"])
    XCTAssertEqual(scale.tables[1].columns, ["Step", "Em", "Count"])
    XCTAssertEqual(scale.tables[1].rows, [["tracking-1", "0.131", "42"], ["tracking-2", "-0.02", "—"]])
  }

  func testSamplingToolsLanguagesRevisionsAndTagUsage() throws {
    let entries = TEIHeaderRenderer.entries(of: Self.skeat)
    XCTAssertEqual(try entry("Sampling", in: entries).paragraphs, ["Every image was measured; none was sampled."])
    let tools = try entry("Tools", in: entries).tables[0]
    XCTAssertEqual(tools.columns, ["Application", "Version", "Label"])
    XCTAssertEqual(tools.rows, [["layout-analysis", "3", "sha256:deadbeef"], ["cluster", "1", "—"]])
    XCTAssertEqual(
      try entry("Languages", in: entries).tables[0].rows, [["English (eng)", "97%"], ["enm", "—"]])
    XCTAssertEqual(
      try entry("Revisions", in: entries).tables[0].rows, [["2026-10-18", "gnorium", "Calibrated & filed."]])
    XCTAssertEqual(try entry("Tag usage", in: entries).tables[0].rows, [["pb", "780"], ["hi", "—"]])
  }

  /// A lexico concordance header: no scale, a sampling table, no biblio words.
  func testConcordanceHeaderReusesTheSameRenderer() throws {
    let header = """
      <teiHeader><fileDesc><titleStmt><title>Concordance of “computer”</title></titleStmt>
      <extent><measure unit="quotation" quantity="12034"/></extent></fileDesc>
      <encodingDesc><samplingDecl><p>Significant: an explicit marker.</p>
      <table rend="selection"><row role="label"><cell>Reason</cell><cell>Count</cell></row><row><cell>earliest</cell><cell>1</cell></row><row><cell/><cell>2</cell></row></table>
      </samplingDecl></encodingDesc></teiHeader>
      """
    let entries = TEIHeaderRenderer.entries(of: header)
    XCTAssertNil(entries.first { $0.label == "Scale" })
    let sampling = try entry("Sampling", in: entries)
    XCTAssertEqual(sampling.paragraphs, ["Significant: an explicit marker."])
    XCTAssertEqual(sampling.tables[0].title, "Selection")
    XCTAssertEqual(sampling.tables[0].columns, ["Reason", "Count"])
    XCTAssertEqual(sampling.tables[0].rows, [["earliest", "1"], ["—", "2"]])
  }

  func testAnEmptyHeaderIsATitleOfEmDash() {
    XCTAssertEqual(TEIHeaderRenderer.entries(of: ""), [TEIHeaderEntry(label: "Title")])
    XCTAssertEqual(TEIHeaderRenderer.entries(of: "<teiHeader/>").map(\.value), ["—"])
    XCTAssertEqual(TEIRenderer.header(of: "<TEI><text/></TEI>").first?.value, "—")
  }

  func testAnEmptyExtentAndSamplingAreEmDashes() throws {
    let entries = TEIHeaderRenderer.entries(
      of: "<teiHeader><fileDesc><extent/></fileDesc><encodingDesc><samplingDecl/></encodingDesc></teiHeader>")
    XCTAssertEqual(try entry("Extent", in: entries).value, "—")
    XCTAssertEqual(try entry("Sampling", in: entries).value, "—")
  }

  func testAHeaderInsideADocumentIsFound() throws {
    let document = "<TEI>" + Self.skeat + "<text><body/></text></TEI>"
    XCTAssertEqual(TEIHeaderRenderer.entries(of: document), TEIHeaderRenderer.entries(of: Self.skeat))
  }
}
