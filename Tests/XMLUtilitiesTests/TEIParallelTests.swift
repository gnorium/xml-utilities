import XCTest
import XMLUtilities

/// A translation as a TEI parallel text: the source's skeleton, every
/// element pointing back at its source with `@corresp`, only the text
/// replaced — and a translation that loses a placeholder refused.
final class TEIParallelTests: XCTestCase {
  let source = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><div type="book">\
    <pb n="1r" facs="https://example.org/iiif/p1/full/1300,/0/default.jpg"/>\
    <head>Libro di abacho</head>\
    <p xml:id="rule">Qui comincia la regola<lb/>del <hi rend="italic">tre</hi>, x <formula notation="TeX">x^2</formula>.</p>\
    <fw type="catch">Della</fw>\
    <pb n="1v" facs="https://example.org/iiif/p2/full/1300,/0/default.jpg"/>\
    <p>Della compagnia.</p></div></body></text></TEI>
    """

  private func english() -> [[String: String]] {
    [
      ["s1": "Book of the abacus", "s2": "Here begins the rule⟦1⟧of ⟦2⟧three⟦3⟧, x ⟦4⟧."],
      ["s1": "On partnership."],
    ]
  }

  func testAPageIsReadAsItsBlocksWithEveryInnerElementAPlaceholder() {
    let parallel = TEIParallel(source: source)
    XCTAssertEqual(parallel.pages.count, 2)
    let first = parallel.pages[0].segments
    XCTAssertEqual(first.map(\.key), ["s1", "s2"], "The catchword is kept whole, not translated.")
    XCTAssertEqual(first.map(\.element), ["head", "p"])
    XCTAssertEqual(first[0].text, "Libro di abacho")
    XCTAssertEqual(first[1].text, "Qui comincia la regola⟦1⟧del ⟦2⟧tre⟦3⟧, x ⟦4⟧.")
    XCTAssertEqual(first[1].placeholders, 4)
  }

  func testATranslationKeepsTheSkeletonAndPointsAtItsSourceOneToOne() throws {
    let parallel = TEIParallel(source: source)
    let texts = english()
    let pages = try parallel.pages.indices.map { try parallel.translatedPage($0, texts: texts[$0]) }
    let translation = parallel.document(
      pages: pages, title: "Libro di abacho, in English",
      responsibility: .init(
        language: "en", languageName: "English", translator: "gnorium madrigal m1", model: "deepseek/x",
        source: "proposal p1"))

    XCTAssertEqual(TEIParallel.check(translation: translation, of: source), [])
    XCTAssertEqual(TEIParallel.skeleton(of: translation), TEIParallel.skeleton(of: source))
    XCTAssertTrue(translation.contains(#"<text xml:lang="en" type="translation">"#))
    XCTAssertTrue(translation.contains(##"<head corresp="#p1.e2">Book of the abacus</head>"##))
    XCTAssertTrue(translation.contains(##"<p xml:id="rule" corresp="#rule">Here begins the rule<lb corresp="#p1.e4"/>"##))
    XCTAssertTrue(translation.contains(##"<formula notation="TeX" corresp="#p1.e6">x^2</formula>"##), "A formula is kept.")
    XCTAssertTrue(translation.contains(##"<fw type="catch" corresp="#p1.e7">Della</fw>"##))
    XCTAssertTrue(translation.contains("<langUsage><language ident=\"en\">English</language>"))
    XCTAssertTrue(translation.contains("<bibl>proposal p1</bibl>"))
    XCTAssertTrue(translation.contains(##"<div type="book" corresp="#e1">"##), "Before the first page.")
    XCTAssertTrue(translation.contains(##"<p corresp="#p2.e2">On partnership.</p>"##), "Pointers count by page.")

    // Read as the reader reads it: a heading is a heading in either.
    let read = TEIRenderer.pages(in: translation)
    XCTAssertEqual(read.count, 2)
    XCTAssertEqual(read[0].lines.first?.text, "Book of the abacus")
    XCTAssertEqual(
      "\(read[0].lines.first?.kind ?? .text)", "\(TEIRenderer.pages(in: source)[0].lines.first?.kind ?? .text)")
  }

  func testATranslationThatLosesAPlaceholderOrASegmentIsRefused() {
    let parallel = TEIParallel(source: source)
    let lost = ["s1": "Book of the abacus", "s2": "Here begins the rule of three, x ⟦4⟧."]
    XCTAssertThrowsError(try parallel.translatedPage(0, texts: lost))
    XCTAssertEqual(
      TEIParallel.violations(of: ["s1": "On partnership.", "s9": "?"], for: parallel.pages[1].segments),
      ["segment s9 is not on the page"])
    XCTAssertEqual(
      TEIParallel.violations(of: [:], for: parallel.pages[1].segments), ["segment s1 (p) is missing"])
  }

  func testTranslatedTextCanAddNoMarkup() throws {
    let parallel = TEIParallel(source: source)
    let page = try parallel.translatedPage(1, texts: ["s1": "On <b>partnership</b> & shares."])
    XCTAssertTrue(page.contains("On &lt;b&gt;partnership&lt;/b&gt; &amp; shares."))
  }

  /// A dictionary entry carries its definitions and its English prose, and
  /// keeps its forms, its quotations and their sources, its equivalents and
  /// its labels as they are.
  func testADictionaryEntryCarriesOnlyItsDefinitionsAndEnglishProse() throws {
    let entry = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><entry xml:id="haus">\
      <form type="lemma"><orth>Haus</orth><pron>haʊs</pron></form>\
      <gramGrp><pos>noun</pos></gramGrp>\
      <sense xml:id="haus-1"><usg type="dom">architecture</usg>\
      <def>A building for people to <hi rend="italic">live</hi> in.</def>\
      <cit type="translation"><quote>house</quote></cit>\
      <cit type="quotation"><quote>Das Haus ist alt.</quote><bibl><date when="1905">1905</date></bibl></cit>\
      </sense>\
      <etym>From Middle High German <mentioned>hūs</mentioned>.</etym>\
      </entry></body></text></TEI>
      """
    let parallel = TEIParallel(source: entry, profile: .dictionary)
    XCTAssertEqual(parallel.pages.count, 1, "An entry has no pages: it is one.")
    let segments = parallel.pages[0].segments
    XCTAssertEqual(segments.map(\.element), ["def", "etym"])
    XCTAssertEqual(segments[0].text, "A building for people to ⟦1⟧live⟦2⟧ in.")
    XCTAssertEqual(segments[1].text, "From Middle High German ⟦1⟧.")

    let german = try parallel.translatedPage(
      0, texts: ["s1": "Ein Gebäude, in dem Menschen ⟦1⟧wohnen⟦2⟧.", "s2": "Aus dem Mittelhochdeutschen ⟦1⟧."])
    let translation = parallel.document(
      pages: [german], title: "Haus",
      responsibility: .init(language: "de", languageName: "German", translator: "t", model: "m", source: "s"))
    XCTAssertEqual(TEIParallel.check(translation: translation, of: entry), [])
    // Carried: the definition and the etymology's prose.
    XCTAssertTrue(translation.contains(">Ein Gebäude, in dem Menschen <hi rend=\"italic\" corresp=\"#e10\">wohnen</hi>.</def>"))
    XCTAssertTrue(translation.contains(">Aus dem Mittelhochdeutschen <mentioned corresp=\"#e18\">hūs</mentioned>.</etym>"))
    // Untouched: the forms, the headword, the equivalent, the quotation and
    // its source, the labels.
    for kept in [">Haus</orth>", ">haʊs</pron>", ">noun</pos>", ">architecture</usg>", ">house</quote>",
      ">Das Haus ist alt.</quote>", ">1905</date>"]
    {
      XCTAssertTrue(translation.contains(kept), kept)
    }
  }

  func testACheckFindsABrokenAlignment() {
    let parallel = TEIParallel(source: source)
    let pages = (try? parallel.pages.indices.map { try parallel.translatedPage($0, texts: english()[$0]) }) ?? []
    let translation = parallel.document(
      pages: pages, title: "t",
      responsibility: .init(language: "en", languageName: "English", translator: "t", model: "m", source: "s"))
    let broken = translation.replacingOccurrences(of: ##"corresp="#p1.e2""##, with: ##"corresp="#p1.e4""##)
    XCTAssertFalse(TEIParallel.check(translation: broken, of: source).isEmpty)
  }
}
