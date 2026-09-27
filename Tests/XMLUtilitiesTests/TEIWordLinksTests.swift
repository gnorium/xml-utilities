import XCTest
import XMLUtilities

/// A standoff word link merged into a transcript for export: the `<w>` whose
/// projected span is the link's, found on its page, gains the attributes;
/// nothing else in the document changes.
final class TEIWordLinksTests: XCTestCase {
  let document = """
    <TEI><text><body>
    <pb n="1" facs="https://example.org/iiif/p0/full/1300,/0/default.jpg"/><p><s><w>Before</w>.</s></p>
    <pb n="2" facs="https://example.org/iiif/p1/full/1300,/0/default.jpg"/>
    <p><s>First <supplied>very</supplied> sentence<lb/>here.</s> <s part="I">A split <w lemma="word">word</w></s></p>
    </body></text></TEI>
    """

  func testAWordGainsItsLinkAndNothingElseChanges() {
    let link = TEIWordLink(
      canvasID: "https://example.org/iiif/p1", range: 30..<34,
      attributes: [.init("lemmaRef", "https://gnorium.com/lexico-records/en/word/noun"),
                   .init("ana", "#a #b&c")])
    let (linked, unmatched) = TEIRenderer.linkingWords(in: document, links: [link])
    XCTAssertEqual(unmatched, [])
    XCTAssertEqual(
      linked,
      document.replacingOccurrences(
        of: #"<w lemma="word">"#,
        with: ##"<w lemma="word" lemmaRef="https://gnorium.com/lexico-records/en/word/noun" ana="#a #b&amp;c">"##))
    // The reading is the same with the link as without it.
    XCTAssertEqual(
      TEIRenderer.pages(in: linked).map { $0.lines.flatMap(\.runs).map(\.text) },
      TEIRenderer.pages(in: document).map { $0.lines.flatMap(\.runs).map(\.text) })
  }

  func testAWordOnAnotherPageCountsFromItsOwnPage() {
    let link = TEIWordLink(
      canvasID: "https://example.org/iiif/p0", range: 0..<6, attributes: [.init("lemmaRef", "r")])
    let (linked, unmatched) = TEIRenderer.linkingWords(in: document, links: [link])
    XCTAssertEqual(unmatched, [])
    XCTAssertTrue(linked.contains(#"<w lemmaRef="r">Before</w>"#))
  }

  func testALinkThatNamesNoWordIsReturnedNotDropped() {
    let misses = [
      TEIWordLink(canvasID: "https://example.org/iiif/p1", range: 29..<34, attributes: [.init("lemmaRef", "r")]),
      TEIWordLink(canvasID: "https://example.org/iiif/nowhere", range: 0..<6, attributes: [.init("lemmaRef", "r")]),
    ]
    let (linked, unmatched) = TEIRenderer.linkingWords(in: document, links: misses)
    XCTAssertEqual(linked, document)
    XCTAssertEqual(unmatched, misses)
  }

  func testAWordKeepsAnAttributeItAlreadyHas() {
    let link = TEIWordLink(
      canvasID: "https://example.org/iiif/p1", range: 30..<34,
      attributes: [.init("lemma", "other"), .init("lemmaRef", "r")])
    let (linked, _) = TEIRenderer.linkingWords(in: document, links: [link])
    XCTAssertTrue(linked.contains(#"<w lemma="word" lemmaRef="r">word</w>"#))
  }
}
