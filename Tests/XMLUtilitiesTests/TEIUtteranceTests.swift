import XCTest
import XMLUtilities

/// An utterance read in its testament: its sentence (joined across a page
/// break) and its word set apart in the reading, counted as the concordance
/// counts a page. The offsets below are gnorium-python's `diplomatic_text`
/// of the same pages.
final class TEIUtteranceTests: XCTestCase {
  let document = """
    <TEI><text><body>\
    <pb n="1" facs="https://example.org/iiif/p0/full/1300,/0/default.jpg"/><p><s>Before.</s></p>\
    <pb n="2" facs="https://example.org/iiif/p1/full/1300,/0/default.jpg"/>\
    <p><s>First <supplied>very</supplied> sentence<lb/>here.</s> <s part="I">A split <w lemma="word">word</w></s></p>\
    <pb n="3" facs="https://example.org/iiif/p2/full/1300,/0/default.jpg"/>\
    <p><s part="F">goes on here.</s> <s>Last <choice><abbr>yͤ</abbr><expan>the</expan></choice> one.</s></p>\
    <pb n="4" facs="https://example.org/iiif/p3/full/1300,/0/default.jpg"/><p><s>After.</s></p>\
    </body></text></TEI>
    """

  func testAnExcerptKeepsThePagesAroundOneAsTheDocumentHasThem() throws {
    let excerpt = try XCTUnwrap(TEIRenderer.excerpt(of: document, around: "https://example.org/iiif/p1"))
    let pages = TEIRenderer.pages(in: excerpt)
    XCTAssertEqual(pages.map(\.label), ["1", "2", "3"])
    XCTAssertEqual(pages.map(\.markup), Array(TEIRenderer.pages(in: document).prefix(3).map(\.markup)))
    // At an edge, fewer.
    let last = try XCTUnwrap(TEIRenderer.excerpt(of: document, around: "https://example.org/iiif/p3"))
    XCTAssertEqual(TEIRenderer.pages(in: last).map(\.label), ["3", "4"])
    XCTAssertNil(TEIRenderer.excerpt(of: document, around: "https://example.org/iiif/nowhere"))
  }

  func testASplitSentenceIsHighlightedOnBothPagesAndItsWordMoreStrongly() throws {
    let pages = TEIRenderer.pages(in: document)
    let highlights = TEIRenderer.utterance(
      in: pages, canvasID: "https://example.org/iiif/p1", passage: 22..<34, headword: 30..<34)
    XCTAssertEqual(highlights["https://example.org/iiif/p1"], [.init(22..<34, kind: .sentence), .init(30..<34, kind: .headword)])
    XCTAssertEqual(highlights["https://example.org/iiif/p2"], [.init(0..<13, kind: .sentence)])
    XCTAssertNil(highlights["https://example.org/iiif/p0"])

    let read = TEIRenderer.pages(in: document, highlights: highlights)
    func marked(_ page: TEIPage) -> [String] {
      page.lines.flatMap(\.runs).map { run in
        switch run.highlight {
        case .headword?: return "<<\(run.text)>>"
        case .sentence?: return "<\(run.text)>"
        case nil: return run.text
        }
      }
    }
    XCTAssertEqual(marked(read[1]), ["First ", "[", "very", "]", " sentence", "here.", " ", "<A split >", "<<word>>"])
    XCTAssertEqual(marked(read[2]), ["<goes on here.>", " ", "Last ", "yͤ", " one."])
    XCTAssertEqual(marked(read[0]), ["Before."])
  }

  func testAWordInNoSentenceHighlightsItsPassage() {
    let pages = TEIRenderer.pages(in: document)
    // "Last yͤ one." read past its <s>'s end: no <s> holds 14..<27.
    let highlights = TEIRenderer.utterance(
      in: pages, canvasID: "https://example.org/iiif/p2", passage: 14..<27, headword: 14..<27)
    XCTAssertEqual(highlights["https://example.org/iiif/p2"], [.init(14..<27, kind: .sentence), .init(14..<27, kind: .headword)])
  }

  func testTheWholeSentenceOfAnUnsplitWord() {
    let pages = TEIRenderer.pages(in: document)
    // "sentence" in "First  sentence\nhere.": the supplied word is not counted.
    let highlights = TEIRenderer.utterance(
      in: pages, canvasID: "https://example.org/iiif/p1", passage: 0..<21, headword: 7..<15)
    XCTAssertEqual(highlights["https://example.org/iiif/p1"], [.init(0..<21, kind: .sentence), .init(7..<15, kind: .headword)])
    let read = TEIRenderer.pages(in: document, highlights: highlights)
    let runs = read[1].lines.flatMap(\.runs)
    XCTAssertEqual(runs.filter { $0.highlight == .headword }.map(\.text), ["sentence"])
    // The supplied word stands inside the sentence, so it is the sentence's.
    XCTAssertEqual(runs.first { $0.text == "very" }?.highlight, .sentence)
  }
}
