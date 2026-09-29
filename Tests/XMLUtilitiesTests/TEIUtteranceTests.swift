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

  /// A page's words as an anchor counts them: by line and place in the
  /// line, the supplied word left out, the word broken over the page break
  /// its part here and none of the next page's.
  func testAPagesWordsAreCountedAsAnAnchorCountsThem() {
    let pages = TEIRenderer.pages(in: document)
    let second = TEIRenderer.words(of: pages[1])
    XCTAssertEqual(second.map(\.surface), ["First", "sentence", "here", "A", "split", "word"])
    XCTAssertEqual(second.map(\.place.line), [1, 1, 2, 2, 2, 2])
    XCTAssertEqual(second.map(\.place.word), [1, 2, 1, 2, 3, 4])
    XCTAssertEqual(TEIRenderer.words(of: pages[2]).first?.surface, "goes")
    // What its <w> says of it; nothing of a token no <w> covers.
    XCTAssertEqual(second.last?.lemma, "word")
    XCTAssertEqual(second.first?.lemma, "")
  }

  /// Read word by word, each run says which word it is of, as an anchor
  /// counts the page: a word broken over a line is one word on both lines,
  /// what an editor supplies inside a word is of that word, and the space
  /// and punctuation between words are of none.
  func testARunSaysWhichWordItIsOf() {
    let markup = """
      <p><w lemma="the" type="article" msd="Definite=Def|PronType=Art">The</w> \
      <w lemma="computer" type="noun" msd="Number=Plur">Compu-<lb break="no"/>tors</w><pc>,</pc> \
      <w lemma="very" type="adverb">v<supplied>e</supplied>ry</w></p>
      """
    let lines = TEIRenderer.lines(in: markup, marksWords: true)
    let runs = lines.flatMap(\.runs)
    func place(of text: String) -> TEIWordPlace? { runs.first { $0.text == text }?.word }
    XCTAssertEqual(place(of: "The"), .init(line: 1, word: 1))
    XCTAssertEqual(place(of: "Compu-"), .init(line: 1, word: 2))
    XCTAssertEqual(place(of: "tors"), .init(line: 1, word: 2))
    XCTAssertEqual(place(of: "e"), .init(line: 2, word: 1))
    XCTAssertEqual(place(of: "ry"), .init(line: 2, word: 1))
    XCTAssertNil(place(of: ","))
    let words = TEIRenderer.words(of: .init(label: "", facsimileURL: "", lines: [], markup: markup))
    XCTAssertEqual(words.map(\.surface), ["The", "Compu-tors", "vry"])
    XCTAssertEqual(words[1].type, "noun")
    XCTAssertEqual(words[1].element, "w")
    XCTAssertEqual(words[1].morphology, "Number=Plur")
    XCTAssertEqual(words.map(\.language), ["", "", ""])
    XCTAssertFalse(words[1].isFragment)
    let mentioned = TEIRenderer.words(
      of: .init(
        label: "", facsimileURL: "", lines: [],
        markup: #"<p xml:lang="eng">from <mentioned xml:lang="grc"><m type="prefix" lemma="μετα-">με-</m></mentioned> <w lemma="measure" type="noun"><m type="root" lemma="meas">meas</m>ure</w></p>"#))
    XCTAssertEqual(mentioned.map(\.surface), ["from", "με-", "measure"], "an <m> in a <w> is part of it")
    XCTAssertEqual(mentioned.map(\.language), ["", "grc", "eng"], "a token no <w> covers says nothing")
    XCTAssertEqual(mentioned.map(\.element), ["", "m", "w"])
    XCTAssertEqual(mentioned.map(\.isFragment), [false, true, false])
    XCTAssertEqual(mentioned.map(\.type), ["", "prefix", "noun"])
    // Read whole, no run is of a word.
    XCTAssertTrue(TEIRenderer.lines(in: markup).flatMap(\.runs).allSatisfy { $0.word == nil })
  }

  func testASplitSentenceIsHighlightedOnBothPagesAndItsWordMoreStrongly() throws {
    let pages = TEIRenderer.pages(in: document)
    // "word": line 2 (after the <lb/>), after "here", "A" and "split".
    let word = TEIWordPosition(line: 2, word: 4, surface: "word")
    let highlights = try XCTUnwrap(
      TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/p1", start: word, end: word))
    XCTAssertEqual(highlights["https://example.org/iiif/p1"], [.init(22..<34, kind: .sentence), .init(30..<34, kind: .title)])
    XCTAssertEqual(highlights["https://example.org/iiif/p2"], [.init(0..<13, kind: .sentence)])
    XCTAssertNil(highlights["https://example.org/iiif/p0"])

    let read = TEIRenderer.pages(in: document, highlights: highlights)
    func marked(_ page: TEIPage) -> [String] {
      page.lines.flatMap(\.runs).map { run in
        switch run.highlight {
        case .title?: return "<<\(run.text)>>"
        case .sentence?: return "<\(run.text)>"
        case nil: return run.text
        }
      }
    }
    XCTAssertEqual(marked(read[1]), ["First ", "[", "very", "]", " sentence", "here.", " ", "<A split >", "<<word>>"])
    XCTAssertEqual(marked(read[2]), ["<goes on here.>", " ", "Last ", "yͤ", " one."])
    XCTAssertEqual(marked(read[0]), ["Before."])
  }

  func testAWordInNoSentenceHighlightsItsLines() throws {
    let document = """
      <TEI><text><body>\
      <pb n="1" facs="https://example.org/iiif/q0/full/1300,/0/default.jpg"/><p>No sentence<lb/>here at all</p>\
      </body></text></TEI>
      """
    let here = TEIWordPosition(line: 2, word: 1, surface: "here")
    let highlights = try XCTUnwrap(
      TEIRenderer.utterance(
        in: TEIRenderer.pages(in: document), canvasID: "https://example.org/iiif/q0", start: here, end: here))
    XCTAssertEqual(highlights["https://example.org/iiif/q0"], [.init(11..<24, kind: .sentence), .init(12..<16, kind: .title)])
  }

  func testTheWholeSentenceOfAnUnsplitWord() throws {
    let pages = TEIRenderer.pages(in: document)
    // "sentence" in "First  sentence\nhere.": the supplied word is not counted.
    let sentence = TEIWordPosition(line: 1, word: 2, surface: "sentence")
    let highlights = try XCTUnwrap(
      TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/p1", start: sentence, end: sentence))
    XCTAssertEqual(highlights["https://example.org/iiif/p1"], [.init(0..<21, kind: .sentence), .init(7..<15, kind: .title)])
    let read = TEIRenderer.pages(in: document, highlights: highlights)
    let runs = read[1].lines.flatMap(\.runs)
    XCTAssertEqual(runs.filter { $0.highlight == .title }.map(\.text), ["sentence"])
    // The supplied word stands inside the sentence, so it is the sentence's.
    XCTAssertEqual(runs.first { $0.text == "very" }?.highlight, .sentence)
  }

  func testSeveralWordsAreHighlightedFromTheFirstToTheLast() throws {
    let pages = TEIRenderer.pages(in: document)
    let highlights = try XCTUnwrap(
      TEIRenderer.utterance(
        in: pages, canvasID: "https://example.org/iiif/p1",
        start: .init(line: 2, word: 2, surface: "A"), end: .init(line: 2, word: 4, surface: "word")))
    XCTAssertEqual(highlights["https://example.org/iiif/p1"]?.last, .init(22..<34, kind: .title))
  }

  func testAWordThatReadsOtherwiseIsNotHighlighted() {
    let pages = TEIRenderer.pages(in: document)
    let moved = TEIWordPosition(line: 2, word: 3, surface: "word")
    XCTAssertNil(TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/p1", start: moved, end: moved))
    let absent = TEIWordPosition(line: 9, word: 1, surface: "word")
    XCTAssertNil(TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/p1", start: absent, end: absent))
    let word = TEIWordPosition(line: 2, word: 4, surface: "word")
    XCTAssertNil(TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/nowhere", start: word, end: word))
  }

  /// The same pages as gnorium-python's `units` counts them
  /// (tests/test_concordance.py `TAGGED`, test_anchor_alignment.py).
  func testWordsAreCountedAsTheConcordanceCountsThem() throws {
    let tagged = """
      <TEI><text><body><pb n="1" facs="https://example.org/iiif/t0/full/1300,/0/default.jpg"/><p>\
      <w lemma="the" pos="DET">The</w> <w lemma="computer" pos="NOUN">Computors</w> \
      <w lemma="compute" pos="VERB">computed</w>; <w lemma="computer" pos="NOUN">compu-<lb/>ter</w> \
      <hi rend="italic"><w lemma="computer" pos="NOUN">computor</w></hi> \
      <w lemma="computer" pos="VERB">computer</w>.</p>\
      <pb n="2" facs="https://example.org/iiif/t1/full/1300,/0/default.jpg"/><p>\
      <w>The</w> <w part="I">compu-</w></p>\
      <pb n="3" facs="https://example.org/iiif/t2/full/1300,/0/default.jpg"/><p>\
      <w part="F">ter</w> <w>won</w> Roſæ</p>\
      </body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: tagged)
    let computor = TEIWordPosition(line: 2, word: 1, surface: "computor")
    XCTAssertEqual(
      TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/t0", start: computor, end: computor)?[
        "https://example.org/iiif/t0"]?.last?.kind, .title)
    // A word broken over a page is counted where it starts, its surface both parts.
    let broken = TEIWordPosition(line: 1, word: 2, surface: "compu-ter")
    XCTAssertNotNil(TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/t1", start: broken, end: broken))
    // The next page counts from its own first word; untagged text is counted by its tokens.
    let won = TEIWordPosition(line: 1, word: 1, surface: "won")
    let rosae = TEIWordPosition(line: 1, word: 2, surface: "rosæ")
    XCTAssertNotNil(TEIRenderer.utterance(in: pages, canvasID: "https://example.org/iiif/t2", start: won, end: rosae))
  }
  /// A figure's `<figDesc>` and an incident's `<desc>` are the encoder's
  /// words about the page, never a word of it: the same page as
  /// gnorium-python `test_the_encoders_descriptions_are_not_words`.
  func testTheEncodersDescriptionsAreNotWords() {
    let page = """
      <TEI><text><body><pb n="1" facs="https://example.org/iiif/f0/full/1300,/0/default.jpg"/>\
      <p>A woodcut <figure bbox="1 2 3 4"><head>Fig. 1</head>\
      <figDesc>Bones of a right hand</figDesc></figure> of the hand<lb/>\
      and <incident><desc>a cough</desc></incident>more</p>\
      </body></text></TEI>
      """
    let words = TEIRenderer.words(of: TEIRenderer.pages(in: page)[0])
    XCTAssertEqual(words.map(\.surface), ["A", "woodcut", "Fig", "of", "the", "hand", "and", "more"])
    XCTAssertEqual(words.map(\.place.line), [1, 1, 2, 2, 2, 2, 3, 3])
    XCTAssertEqual(words.map(\.place.word), [1, 2, 1, 2, 3, 4, 1, 2])
  }

  /// A line starts after each `<lb/>` and at each verse line, block and a
  /// speech's first child, once text was read since the last start; the same
  /// page as gnorium-python `test_verse_lines_and_blocks_start_lines_without_line_breaks`.
  func testVerseAndBlocksStartLinesWithoutLineBreaks() throws {
    let verse = """
      <TEI><text><body><pb n="1" facs="https://example.org/iiif/v0/full/1300,/0/default.jpg"/>\
      <fw type="header"><w lemma="the">The</w> <w lemma="tragedy">Tragedy</w></fw>\
      <sp><speaker><w lemma="king">King.</w></speaker>\
      <l><w lemma="take">Take</w> <w lemma="thy">thy</w></l>\
      <l><w lemma="and">And</w> <w lemma="king">king</w><lb/></l>\
      <l><lb/><w lemma="but">But</w></l></sp>\
      </body></text></TEI>
      """
    let pages = TEIRenderer.pages(in: verse)
    let page = "https://example.org/iiif/v0"
    for (line, word, surface) in [(1, 2, "Tragedy"), (2, 1, "King."), (3, 2, "thy"), (4, 2, "king"), (5, 1, "But")] {
      let at = TEIWordPosition(line: line, word: word, surface: surface)
      XCTAssertNotNil(
        TEIRenderer.utterance(in: pages, canvasID: page, start: at, end: at), "\(surface) is not line \(line), word \(word)")
    }
    // The <lb/> ending line 4 and the one opening the next verse line are one line.
    let none = TEIWordPosition(line: 6, word: 1, surface: "But")
    XCTAssertNil(TEIRenderer.utterance(in: pages, canvasID: page, start: none, end: none))
  }
}
