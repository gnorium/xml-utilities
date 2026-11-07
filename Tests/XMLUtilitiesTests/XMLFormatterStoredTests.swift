import XCTest

@testable import XMLUtilities

/// `XMLFormatter.formatted`, the one formatter stored TEI is written with
/// (user, 2026-11-05: "store it formatted"): element-only containers one
/// child a line, mixed content byte for byte, the reading, the words, the
/// `xml:id`s and the rendering unchanged, and formatting it again changes
/// nothing. On real pages: Hamlet Q1 (dev madrigal
/// 01A1946C-E748-8060-B4D7-1B8B13227FB0), its title page, p. 3 and p. 35.
final class XMLFormatterStoredTests: XCTestCase {
  /// The Hamlet fixture: three pages of the madrigal as a document.
  struct Hamlet: Decodable {
    let madrigal: String
    let pages: [String]
    let document: String
  }

  static func hamlet() throws -> Hamlet {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "hamlet-q1-pages", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(Hamlet.self, from: Data(contentsOf: url))
  }

  /// Everything kept whole, in order: each mixed-content element (and every
  /// other element the formatter does not lay out) as written, every tag of
  /// a container it lays out, comments, CDATA and text. Only the white space
  /// between a laid-out container's children is left out: the one thing
  /// `formatted` may change.
  private func kept(_ markup: String) -> [String] {
    func walk(_ node: PrettyNode) -> [String] {
      switch node.kind {
      case .text: return node.raw.allSatisfy(PrettyNode.isSpace) ? [] : [node.raw]
      case .cdata, .other: return [node.raw]
      case .element:
        if !node.name.isEmpty && node.isWhole { return [node.verbatim] }
        return [node.raw] + node.children.flatMap(walk) + [node.close ?? ""]
      }
    }
    let root = PrettyNode.tree(of: markup)
    // Text at the top level: kept as given, whole.
    return root.holdsText ? [markup] : walk(root)
  }

  private func ids(_ markup: String) -> [String] {
    let expression = try! NSRegularExpression(pattern: #"\bxml:id\s*=\s*("[^"]*"|'[^']*')"#)
    return expression.matches(in: markup, range: NSRange(markup.startIndex..., in: markup)).compactMap {
      Range($0.range(at: 1), in: markup).map { String(markup[$0]) }
    }
  }

  /// The proof for one fragment: whitespace-safe, the same reading and
  /// rendering, the same words and ids, idempotent.
  private func assertStoredSafely(_ markup: String, file: StaticString = #filePath, line: UInt = #line) {
    let formatted = XMLFormatter.formatted(markup)
    XCTAssertEqual(kept(formatted), kept(markup), "Mixed content changed:\n\(formatted)", file: file, line: line)
    for marksWords in [false, true] {
      XCTAssertEqual(
        TEIRenderer.lines(in: formatted, marksWords: marksWords).map { String(reflecting: $0) },
        TEIRenderer.lines(in: markup, marksWords: marksWords).map { String(reflecting: $0) },
        "Rendered lines or runs changed:\n\(formatted)", file: file, line: line)
    }
    XCTAssertEqual(
      TEIRenderer.lines(in: formatted).map(\.text), TEIRenderer.lines(in: markup).map(\.text), file: file, line: line)
    XCTAssertEqual(
      TEIProjection.of(markup: formatted).units.map { "\($0.line).\($0.number)=\($0.surface)" },
      TEIProjection.of(markup: markup).units.map { "\($0.line).\($0.number)=\($0.surface)" },
      "An anchor moved:\n\(formatted)", file: file, line: line)
    XCTAssertEqual(ids(formatted), ids(markup), file: file, line: line)
    XCTAssertEqual(XMLFormatter.formatted(formatted), formatted, "Not idempotent", file: file, line: line)
  }

  /// Element-only containers open a child a line; mixed content, a title
  /// part's, stays as written, white space and all.
  func testATitlePageIsLaidOutAndItsPartsKeptAsWritten() {
    XCTAssertEqual(
      XMLFormatter.formatted(XMLFormatterTests.titlePage),
      """
      <titlePage>
        <docTitle rend="align(center)">
          <titlePart type="main"><s ana="#autonomy-0"><w lemma="an" class="article" msd="Definite=Ind|PronType=Art">AN</w> <w lemma="etymological" class="adjective" msd="Degree=Pos">ETYMOLOGICAL</w><lb/><w lemma="dictionary" class="noun">DICTIONARY</w><lb/></s></titlePart>
        </docTitle>
        <docImprint><s><w lemma="Frowde">FROWDE</w><pc>,</pc> <persName><w>Henry</w></persName><pc>.</pc></s></docImprint>
      </titlePage>
      """)
    assertStoredSafely(XMLFormatterTests.titlePage)
  }

  /// Not a space added, removed or changed in mixed content: a soft wrap,
  /// an indent, a break after `<lb/>` none stood after, all as written,
  /// where `prettified` lays them out for reading.
  func testMixedContentIsKeptByteForByte() {
    let markup = "<div>\n<p>\n    <s><w>a</w>\n      <w>b</w>  <hi>c\n d</hi></s>\n</p><ab><lb/><w>x</w><lb/>\n   <w>y</w></ab></div>"
    XCTAssertEqual(
      XMLFormatter.formatted(markup),
      "<div>\n  <p>\n    <s><w>a</w>\n      <w>b</w>  <hi>c\n d</hi></s>\n</p>\n  <ab><lb/><w>x</w><lb/>\n   <w>y</w></ab>\n</div>")
    XCTAssertNotEqual(XMLFormatter.prettified(markup), XMLFormatter.formatted(markup))
    assertStoredSafely(markup)
    // A paragraph alone, even holding only elements, is mixed content.
    let paragraph = ##"<p><s><lb/><hi rend="italic"><w>This</w> <w>book</w></hi> <w>a</w><pc>.</pc></s></p>"##
    XCTAssertEqual(XMLFormatter.formatted(paragraph), paragraph)
    // Text at a fragment's top level: nothing to lay out.
    let loose = "<lb/>more text <hi>here</hi>\n  <lb/>end"
    XCTAssertEqual(XMLFormatter.formatted(loose), loose)
  }

  /// White space between an element-only container's children is
  /// replaced; none is put where a break would join or split a word.
  func testElementOnlyWhiteSpaceIsReplacedAndNoWordIsJoined() {
    let markup = "<body>\n      <lg>  <l>one</l><l>two</l>\n</lg><p>x</p>\n\n<figure><graphic url=\"a\"/><figDesc>A</figDesc></figure></body>"
    XCTAssertEqual(
      XMLFormatter.formatted(markup),
      "<body>\n  <lg>\n    <l>one</l>\n    <l>two</l>\n  </lg>\n  <p>x</p>\n  <figure>\n    <graphic url=\"a\"/>\n    <figDesc>A</figDesc>\n  </figure>\n</body>")
    assertStoredSafely(markup)
    // Title parts whose letters abut keep abutting: no break between them.
    let abutting = "<titlePage><docTitle><titlePart>A</titlePart><titlePart>B</titlePart></docTitle></titlePage>"
    XCTAssertTrue(XMLFormatter.formatted(abutting).contains("<titlePart>A</titlePart><titlePart>B</titlePart>"))
    assertStoredSafely(abutting)
  }

  /// Every fragment the prettifier's tests read: the same proof.
  func testEveryKnownMarkupIsStoredSafely() {
    for markup in [XMLFormatterTests.titlePage] + XMLFormatterTests.markups + XMLFormatterTests.edges {
      assertStoredSafely(markup)
    }
  }

  /// Hamlet Q1's title page, p. 3 and p. 35, as the madrigal stores them
  /// (each one line): the title page laid out a part a line, every page
  /// read, worded and rendered as before, and formatted once for good.
  func testHamletsPagesAreStoredSafely() throws {
    let hamlet = try Self.hamlet()
    let pages = TEIRenderer.pages(in: hamlet.document)
    XCTAssertGreaterThanOrEqual(pages.count, hamlet.pages.count)
    for page in pages {
      assertStoredSafely(page.markup)
    }
    // p. 3, a run of anonymous blocks (`ab`), one a line.
    let three = XMLFormatter.formatted(pages[1].markup)
    XCTAssertTrue(pages[1].markup.contains("</ab><"))
    XCTAssertFalse(three.contains("</ab><"), three)
    let title = XMLFormatter.formatted(pages[0].markup)
    XCTAssertFalse(pages[0].markup.contains("\n"), "the fixture's title page is stored on one line")
    XCTAssertTrue(title.hasPrefix("<titlePage>\n  <docTitle>\n    <titlePart type=\"main\""), String(title.prefix(200)))
    XCTAssertGreaterThan(title.split(separator: "\n").count, 5)
  }

  /// A whole document formatted page by page (`TEIRenderer.formattingPages`):
  /// every byte outside its pages kept (its header recorded byte for
  /// byte), each page as `formatted` lays it, the pages read the same, and
  /// formatted again it is unchanged. Given what it was, only the pages
  /// that changed are formatted.
  func testADocumentIsFormattedPageByPage() throws {
    let document = try Self.hamlet().document
    let formatted = TEIRenderer.formattingPages(in: document)
    XCTAssertNotEqual(formatted, document)
    XCTAssertEqual(TEIRenderer.formattingPages(in: formatted), formatted, "Not idempotent")
    let before = TEIRenderer.pages(in: document), after = TEIRenderer.pages(in: formatted)
    XCTAssertEqual(after.map(\.markup), before.map { XMLFormatter.formatted($0.markup) })
    XCTAssertEqual(after.map { $0.lines.map { String(reflecting: $0) } }, before.map { $0.lines.map { String(reflecting: $0) } })
    XCTAssertEqual(after.map(TEIRenderer.words(of:)), before.map(TEIRenderer.words(of:)))
    // Outside the pages, byte for byte.
    func outside(_ xml: String) -> String {
      var out = xml
      for range in TEIRenderer.pageRanges(in: xml).reversed() { out.removeSubrange(range) }
      return out
    }
    XCTAssertEqual(outside(formatted), outside(document))
    // Only what changed since: a page laid anew is formatted, the rest kept.
    let laid = try XCTUnwrap(TEIRenderer.replacingPage(2, with: before[2].markup, in: document))
    XCTAssertEqual(TEIRenderer.pages(in: laid)[2].markup, XMLFormatter.formatted(before[2].markup))
    XCTAssertEqual(TEIRenderer.pages(in: laid)[0].markup, before[0].markup, "a page left as it stood is not formatted")
    let spliced = laid.replacingOccurrences(of: ">THE<", with: ">THE <")
    let since = TEIRenderer.formattingPages(in: spliced, since: laid)
    XCTAssertEqual(TEIRenderer.pages(in: since)[0].markup, XMLFormatter.formatted(before[0].markup.replacingOccurrences(of: ">THE<", with: ">THE <")))
    XCTAssertEqual(TEIRenderer.pages(in: since)[1].markup, before[1].markup, "an unchanged page stays as stored")
  }

  /// A calibrated frame's own TEI, whose break names no image: its body is
  /// its one page; its header and facsimile are kept.
  func testAFramesOwnDocumentFormatsItsBody() {
    let header = #"<teiHeader><encodingDesc><tagsDecl><rendition xml:id="size-1" scheme="css">font-size:1rem</rendition></tagsDecl></encodingDesc></teiHeader>"#
    let document = #"<TEI xmlns="http://www.tei-c.org/ns/1.0">"# + header
      + #"<text><body><pb n="1"/><titlePage><docTitle><titlePart>A<lb/></titlePart></docTitle></titlePage><p>x <hi>y</hi></p></body></text></TEI>"#
    let formatted = TEIRenderer.formattingPages(in: document)
    XCTAssertTrue(formatted.contains(header))
    XCTAssertTrue(
      formatted.contains("<body><pb n=\"1\"/>\n<titlePage>\n  <docTitle>\n    <titlePart>A<lb/></titlePart>\n  </docTitle>\n</titlePage>\n<p>x <hi>y</hi></p></body>"),
      formatted)
    XCTAssertEqual(TEIRenderer.formattingPages(in: formatted), formatted)
    XCTAssertEqual(TEIRenderer.formattingPages(in: document, since: document), document)
  }
}
