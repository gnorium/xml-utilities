import XCTest
import XMLUtilities

/// A page's phrases: each `<phr>` with its words as an anchor counts them,
/// its type, lemma and language; the smallest holding a word is its phrase.
final class TEIPhrasesTests: XCTestCase {
  func testAPhraseHoldsItsWordsAndTheSmallestIsAWordsPhrase() {
    let page = TEIPage(
      label: "", facsimileURL: "", lines: [],
      markup: """
        <p xml:lang="eng"><w lemma="he">He</w> \
        <phr type="idiom" lemma="kick the bucket"><w lemma="kick">kicked</w> <w lemma="the">the</w><lb/>\
        <w lemma="bucket">bucket</w></phr> <phr type="phrase" lemma="at last"><w>at</w> \
        <phr type="phrase" lemma="last"><w>last</w></phr></phr></p>
        """)
    let phrases = TEIRenderer.phrases(of: page)
    XCTAssertEqual(phrases.map(\.lemma), ["kick the bucket", "at last", "last"])
    XCTAssertEqual(phrases[0].type, "idiom")
    XCTAssertEqual(phrases[0].language, "eng")
    XCTAssertEqual(phrases[0].surface, "kicked the bucket")
    XCTAssertEqual(
      phrases[0].words, [.init(line: 1, word: 2), .init(line: 1, word: 3), .init(line: 2, word: 1)])
    XCTAssertEqual(TEIRenderer.phrase(of: page, at: .init(line: 2, word: 1))?.lemma, "kick the bucket")
    XCTAssertEqual(TEIRenderer.phrase(of: page, at: .init(line: 2, word: 3))?.lemma, "last")
    XCTAssertEqual(TEIRenderer.phrase(of: page, at: .init(line: 2, word: 2))?.lemma, "at last")
    XCTAssertNil(TEIRenderer.phrase(of: page, at: .init(line: 1, word: 1)))
  }
}
