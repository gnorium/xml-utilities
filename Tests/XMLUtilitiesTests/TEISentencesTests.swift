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

  /// A sentence split into parts on its page (verse over two blocks, a
  /// sentence leaving a `<hi>`) is one sentence; a part the page opens with
  /// continues the page before and is one of its own here.
  func testPartsOfASentenceOnAPageAreOne() throws {
    let document = """
      <TEI><text><body><pb n="1" facs="https://example.org/iiif/s0/full/1300,/0/default.jpg"/>\
      <ab><lb/><s xml:id="s-L1-1" part="F">Within</s> <s xml:id="s-L1-2" part="I">O that</s></ab>\
      <ab><lb/><s xml:id="s-L2-1" part="F">Would melt.</s> <s xml:id="s-L2-2" part="I">He said</s> \
      <hi rend="italic"><s xml:id="s-L2-3" part="F">done.</s> <s xml:id="s-L2-4" part="I">Now</s></hi> \
      <s xml:id="s-L2-5" part="M">we</s></ab><ab><lb/><s xml:id="s-L3-1" part="F">goe</s></ab></body></text></TEI>
      """
    let page = try XCTUnwrap(TEIRenderer.pages(in: document).first)
    let sentences = TEIRenderer.sentences(of: page)
    let named = TEIRenderer.words(of: page).map { "\($0.surface)=\(sentences[$0.place].map(String.init) ?? "-")" }
    XCTAssertEqual(
      named, ["Within=0", "O=1", "that=1", "Would=1", "melt=1", "He=2", "said=2", "done=2", "Now=3", "we=3", "goe=3"])
  }
}
