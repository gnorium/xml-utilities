import XCTest
import XMLUtilities

/// Each word of a page names the sentence it is read in (user, 2026-11-01):
/// the smallest `<s>` holding it, by its place among the page's sentences,
/// from 0; a word no `<s>` holds names none.
final class TEISentencesTests: XCTestCase {
  func testEachWordNamesItsSentence() throws {
    let document = """
      <TEI><text><body><pb n="1" facs="https://example.org/iiif/s0/full/1300,/0/default.jpg"/>\
      <p><s><w lemma="the">The</w> <w lemma="scratchword">scratchwords</w> <w lemma="stand">stood</w><pc>.</pc></s> \
      <s><w lemma="they">They</w> <w lemma="fall"><choice><abbr>fel</abbr><expan>fell</expan></choice></w><pc>.</pc></s> \
      Loose</p></body></text></TEI>
      """
    let page = try XCTUnwrap(TEIRenderer.pages(in: document).first)
    let sentences = TEIRenderer.sentences(of: page)
    let words = TEIRenderer.words(of: page)
    let named = words.map { "\($0.surface)=\(sentences[$0.place].map(String.init) ?? "-")" }
    XCTAssertEqual(named, ["The=0", "scratchwords=0", "stood=0", "They=1", "fel=1", "Loose=-"])
  }
}
