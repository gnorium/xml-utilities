import XCTest
import XMLUtilities

/// A gloss reads everything the markup encodes of what was opened (user,
/// 2026-10-08): the elements around a word, its own, and those within it,
/// a `<choice>`'s every reading among them; and the page's elements that
/// are no word—a gap, a running head's page number, a number—open by their
/// place in document order, which the reading carries on their lines and runs.
final class TEIEncodingTests: XCTestCase {
  let document = """
    <TEI><text><body>\
    <pb n="1" facs="https://example.org/iiif/p0/full/1300,/0/default.jpg"/>\
    <fw type="pageNum">12</fw>\
    <p><s><persName ref="https://viaf.org/viaf/1"><w lemma="john" type="proper_noun">Iohn</w></persName> \
    <w lemma="the" type="article"><choice><abbr>yͤ</abbr><expan>the</expan></choice></w> \
    <w lemma="word" msd="Number=Sing" ana="#x"><hi rend="italic">wor</hi><supplied reason="damage">d</supplied></w> \
    <choice><sic><w lemma="the">teh</w></sic><corr>the</corr></choice> \
    <date when="1611">1611</date>.</s></p>\
    <gap reason="illegible"/>\
    </body></text></TEI>
    """

  func testAWordReadsEverythingAroundAndWithinIt() throws {
    let page = try XCTUnwrap(TEIRenderer.pages(in: document).first)
    let words = TEIRenderer.words(of: page)
    XCTAssertEqual(words.map(\.surface), ["Iohn", "yͤ", "wor", "teh"], "what is supplied is not on the surface")

    let john = try XCTUnwrap(TEIRenderer.encoding(of: page, at: words[0].place))
    XCTAssertEqual(john.map(\.element), ["p", "s", "persName", "w"])
    XCTAssertEqual(john.first { $0.element == "persName" }?.attribute("ref"), "https://viaf.org/viaf/1")
    XCTAssertEqual(john.first { $0.element == "persName" }?.relation, .around)
    XCTAssertEqual(john.last?.relation, .own)
    XCTAssertEqual(john.first { $0.element == "p" }?.text, "", "a block's text is not the gloss's")

    let the = try XCTUnwrap(TEIRenderer.encoding(of: page, at: words[1].place))
    XCTAssertEqual(the.filter { $0.relation == .within }.map(\.element), ["choice", "abbr", "expan"])
    XCTAssertEqual(the.first { $0.element == "expan" }?.text, "the")

    let word = try XCTUnwrap(TEIRenderer.encoding(of: page, at: words[2].place))
    XCTAssertEqual(word.filter { $0.relation == .within }.map(\.element), ["hi", "supplied"])
    XCTAssertEqual(word.first { $0.element == "hi" }?.attribute("rend"), "italic")
    XCTAssertEqual(word.first { $0.element == "supplied" }?.text, "d")
    XCTAssertEqual(word.first { $0.element == "w" }?.attribute("ana"), "#x")

    // A choice around a word brings its correction with it.
    let teh = try XCTUnwrap(TEIRenderer.encoding(of: page, at: words[3].place))
    XCTAssertEqual(teh.map(\.element), ["p", "s", "choice", "sic", "w", "corr"])
    XCTAssertEqual(teh.first { $0.element == "corr" }?.text, "the")
  }

  func testWhatIsNoWordOpensByItsPlace() throws {
    let page = try XCTUnwrap(TEIRenderer.pages(in: document, marksWords: true).first)
    // The running head's page number, the date: runs of no word.
    let runs = page.lines.flatMap(\.runs)
    let folio = try XCTUnwrap(runs.first { $0.text == "12" }?.element)
    let date = try XCTUnwrap(runs.first { $0.text == "1611" }?.element)
    XCTAssertNil(runs.first { $0.text == "Iohn" }?.element, "a word's runs open the word")
    let gap = try XCTUnwrap(page.lines.first { if case .gap = $0.kind { return true } else { return false } }?.element)

    let fw = try XCTUnwrap(TEIRenderer.encoding(of: page, element: folio))
    XCTAssertEqual(fw.map(\.element), ["fw"])
    XCTAssertEqual(fw.first?.attribute("type"), "pageNum")
    XCTAssertEqual(fw.first?.text, "12")
    let when = try XCTUnwrap(TEIRenderer.encoding(of: page, element: date))
    XCTAssertEqual(when.map(\.element), ["p", "s", "date"])
    XCTAssertEqual(when.last?.attribute("when"), "1611")
    XCTAssertEqual(TEIRenderer.encoding(of: page, element: gap)?.first?.attribute("reason"), "illegible")
    XCTAssertNil(TEIRenderer.encoding(of: page, element: 999))
  }

  /// A figure's gloss reads its caption (`<head>`) and its description.
  func testAFigureReadsItsCaption() throws {
    let tei = """
      <TEI><text><body><pb n="1" facs="https://example.org/iiif/p1/full/1300,/0/default.jpg"/>\
      <figure type="illustration"><head>The Globe, 1612</head><figDesc>A round playhouse.</figDesc></figure>\
      </body></text></TEI>
      """
    let page = try XCTUnwrap(TEIRenderer.pages(in: tei, marksWords: true).first)
    let figure = try XCTUnwrap(
      page.lines.first { if case .figure = $0.kind { return true } else { return false } }?.element)
    let encoding = try XCTUnwrap(TEIRenderer.encoding(of: page, element: figure))
    XCTAssertEqual(encoding.map(\.element), ["figure", "head", "figDesc"])
    XCTAssertEqual(encoding.first { $0.element == "head" }?.text, "The Globe, 1612")
    XCTAssertEqual(encoding.first { $0.element == "figDesc" }?.text, "A round playhouse.")
    // The caption's words open their own glosses; what is no word, the figure's.
    let runs = page.lines.flatMap(\.runs)
    XCTAssertNil(runs.first { $0.text == "Globe" }?.element)
    XCTAssertEqual(runs.first { $0.text.hasPrefix(",") }?.element, figure)
  }
}
