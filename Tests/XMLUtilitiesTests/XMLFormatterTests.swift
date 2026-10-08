import XCTest
import XMLUtilities

/// `XMLFormatter.prettified`: text stays on its line as written, elements
/// holding only elements open one child per line, and nothing a reader
/// reads changes.
final class XMLFormatterTests: XCTestCase {
  /// Each line a reading sets, its kind and its text with white space
  /// collapsed, as a browser draws it.
  private func reading(_ markup: String) -> [String] {
    func collapsed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    func described(_ lines: [TEILine]) -> [String] {
      lines.flatMap { line -> [String] in
        let kind: String
        switch line.kind {
        case .table(let table):
          var out: [String] = ["table"] + described(table.caption)
          for row in table.rows {
            out.append("row")
            for cell in row.cells { out += described(cell.lines) }
          }
          return out
        case .text: kind = "text"
        default: kind = "\(line.kind)"
        }
        let flags = "\(line.rend)|\(line.opensBlock)|\(line.joinsPrevious)|"
        return [kind + "|" + flags + collapsed(line.text)]
      }
    }
    return described(TEIRenderer.lines(in: markup))
  }

  private func assertSameReading(_ markup: String, file: StaticString = #filePath, line: UInt = #line) {
    let pretty = XMLFormatter.prettified(markup)
    XCTAssertEqual(reading(pretty), reading(markup), "The reading changed:\n\(pretty)", file: file, line: line)
    XCTAssertEqual(XMLFormatter.prettified(pretty), pretty, "Not idempotent", file: file, line: line)
  }

  static let titlePage =
    ##"<titlePage><docTitle rend="align(center)"><titlePart type="main"><s ana="#autonomy-0">"##
    + ##"<w lemma="an" type="article" msd="Definite=Ind|PronType=Art">AN</w> "##
    + ##"<w lemma="etymological" type="adjective" msd="Degree=Pos">ETYMOLOGICAL</w><lb/>"##
    + ##"<w lemma="dictionary" type="noun">DICTIONARY</w><lb/></s></titlePart></docTitle>"##
    + ##"<docImprint><s><w lemma="Frowde">FROWDE</w><pc>,</pc> <persName><w>Henry</w></persName><pc>.</pc></s></docImprint>"##
    + ##"</titlePage>"##

  /// A title page as recognition writes it, each title line ended by its
  /// `<lb/>`. (Without one, the reading runs `docTitle` into `docImprint`—
  /// neither is a block to `TEIRenderer`—so no break is put there either.)
  func testATitlePageOpensOneChildPerLine() {
    XCTAssertEqual(
      XMLFormatter.prettified(Self.titlePage),
      """
      <titlePage>
        <docTitle rend="align(center)">
          <titlePart type="main">
            <s ana="#autonomy-0">
              <w lemma="an" type="article" msd="Definite=Ind|PronType=Art">AN</w>
              <w lemma="etymological" type="adjective" msd="Degree=Pos">ETYMOLOGICAL</w>
              <lb/>
              <w lemma="dictionary" type="noun">DICTIONARY</w>
              <lb/>
            </s>
          </titlePart>
        </docTitle>
        <docImprint>
          <s>
            <w lemma="Frowde">FROWDE</w><pc>,</pc>
            <persName>
              <w>Henry</w></persName><pc>.</pc>
          </s>
        </docImprint>
      </titlePage>
      """)
    assertSameReading(Self.titlePage)
  }

  /// No white space is put where there was none between two things a
  /// reader reads together: a word and its punctuation, a name and its.
  func testPunctuationStaysWithItsWord() {
    let markup = ##"<p><s><w>FROWDE</w><pc>,</pc> <persName><w>Iohn</w></persName><pc>;</pc> <w>end</w><pc>.</pc></s></p>"##
    let pretty = XMLFormatter.prettified(markup)
    XCTAssertTrue(pretty.contains("<w>FROWDE</w><pc>,</pc>"), pretty)
    XCTAssertTrue(pretty.contains("</persName><pc>;</pc>"), pretty)
    XCTAssertTrue(pretty.contains("<w>end</w><pc>.</pc>"), pretty)
    XCTAssertEqual(reading(pretty), ["text||true|false|FROWDE, Iohn; end."])
    assertSameReading(markup)
  }

  func testMixedContentStaysOnOneLineAsWritten() {
    let markup = "<div><p>text <hi rend=\"italic\">x  y</hi> more</p><p>a\n  b</p></div>"
    XCTAssertEqual(
      XMLFormatter.prettified(markup),
      "<div>\n  <p>text <hi rend=\"italic\">x  y</hi> more</p>\n  <p>a\n  b</p>\n</div>")
    XCTAssertEqual(XMLFormatter.prettified(##"<hi rend="italic">This book is a gift to</hi>"##), ##"<hi rend="italic">This book is a gift to</hi>"##)
    assertSameReading(markup)
  }

  func testNestedHiAroundWordsOpens() {
    let markup = ##"<p><s><lb/><hi rend="italic"><w>This</w> <w>book</w> <w>is</w></hi> <w>a</w> <w>gift</w><pc>.</pc></s></p>"##
    XCTAssertEqual(
      XMLFormatter.prettified(markup),
      """
      <p>
        <s>
          <lb/>
          <hi rend="italic">
            <w>This</w>
            <w>book</w>
            <w>is</w>
          </hi>
          <w>a</w>
          <w>gift</w><pc>.</pc>
        </s>
      </p>
      """)
    assertSameReading(markup)
  }

  func testCommentsInstructionsCDATAAndEntitiesAreKept() {
    let markup = "<?xml version=\"1.0\"?><div><!-- a <note> --><p>Fish &amp; chips<![CDATA[ <raw> ]]></p><ab><![CDATA[x]]></ab></div>"
    let pretty = XMLFormatter.prettified(markup)
    XCTAssertEqual(
      pretty,
      "<?xml version=\"1.0\"?>\n<div>\n  <!-- a <note> -->\n  <p>Fish &amp; chips<![CDATA[ <raw> ]]></p>\n  <ab><![CDATA[x]]></ab>\n</div>")
    XCTAssertEqual(XMLFormatter.prettified(pretty), pretty)
  }

  /// A page cut out of a document: a closing tag of what opened before it,
  /// an element still open at its end.
  func testAFragmentKeepsItsStrayTags() {
    let markup = ##"<s part="F"><w>ended</w><pc>.</pc></s></p><p><s><w>Next</w> <w>one</w>"##
    let pretty = XMLFormatter.prettified(markup)
    XCTAssertEqual(
      pretty,
      """
      <s part="F">
          <w>ended</w><pc>.</pc>
        </s>
      </p>
      <p>
        <s>
          <w>Next</w>
          <w>one</w>
      """)
    assertSameReading(markup)
  }

  func testIdempotence() {
    for markup in [Self.titlePage] + Self.ordinances {
      let once = XMLFormatter.prettified(markup)
      XCTAssertEqual(XMLFormatter.prettified(once), once)
    }
  }

  /// Ordinances as recognition writes them: one line, words spaced, notes,
  /// footnotes, verse, furniture, choices, figures, tables.
  static let ordinances = [
    ##"<fw type="header" place="top"><w>THE</w> <w>PREFACE</w><pc>.</pc></fw><fw type="pageNum" place="top-right">vii</fw><div type="preface"><head><w>PREFACE</w></head><p><s><w lemma="the" pos="DET"><choice><abbr>yͤ</abbr><expan>the</expan></choice></w> <w lemma="virtue" pos="NOUN"><choice><orig>vertue</orig><reg>virtue</reg></choice></w> <w lemma="of" pos="ADP">of</w> <persName><w lemma="John" pos="PROPN">Iohn</w></persName> <w lemma="show" pos="VERB"><g ref="#slong">ſ</g>hewed</w> <w lemma="bank" pos="NOUN">ba<supplied reason="damage">nk</supplied></w><pc>,</pc> <del rend="strikethrough">not</del> <date when="1603"><num value="1603">1603</num></date><pc>.</pc><note place="foot" n="1"><s><w>See</w> <w>below</w><pc>.</pc></s></note></s><note place="margin"><s><w lemma="mark" pos="VERB">Marke</w></s></note></p><list><item>First</item><item>Second</item></list><handShift new="#h2"/></div><fw type="catch" place="bottom">THE</fw>"##,
    ##"<pb n="7"/><p><s><w lemma="be" pos="VERB">Been</w> <w lemma="thus" pos="ADV">thus</w><pc>,</pc><lb/><w lemma="encounter" pos="VERB">encountred</w><pc>:</pc></s></p>"##,
    ##"<lg><l rend="indent(1)"><s><w lemma="the" pos="DET">The</w> <w lemma="computer" pos="NOUN">compu-<lb break="no"/>ter</w> <w lemma="stand" pos="VERB">stands</w><lb/><w lemma="here" pos="ADV">here</w></s></l><l><s><w>And</w> <w>there</w><pc>.</pc></s></l></lg><sp><speaker><w>HAM</w><pc>.</pc></speaker><p><s><w>To</w> <w>be</w></s><s><w>or</w> <w>not</w><pc>.</pc></s></p></sp><stage><w>Exit</w><pc>.</pc></stage>"##,
    ##"<div><p><s part="F">was flooded.</s></p><note place="foot"><s>After.</s></note><figure><head><w>Plate</w> <w>I</w></head><figDesc>A map</figDesc></figure><table><row role="label"><cell><w>Year</w></cell><cell><w>Sum</w></cell></row><row><cell><num>1603</num></cell><cell><num>12</num></cell></row></table><p><gap reason="illegible"/><w>torn</w></p></div>"##,
    ##"<p><s><w>Let</w> <formula notation="mathml"><math xmlns="http://www.w3.org/1998/Math/MathML" display="inline"><semantics><mrow><mi>x</mi><mo>=</mo><mi>a</mi></mrow><annotation encoding="application/x-tex">x=a</annotation></semantics></math></formula> <w>hold</w><pc>.</pc></s></p>"##,
  ]

  func testOrdinancesReadTheSameFormatted() {
    for markup in Self.ordinances { assertSameReading(markup) }
  }

  /// A reading that marks words counts the same words formatted.
  func testWordsAreTheSameFormatted() {
    for markup in Self.ordinances {
      // Each word's place and its text, white space collapsed.
      let words = { (text: String) -> [String] in
        var out: [String: String] = [:]
        for run in TEIRenderer.lines(in: text, marksWords: true).flatMap(\.runs) {
          guard let word = run.word else { continue }
          out["\(word)", default: ""] += run.text
        }
        return out.map { "\($0.key)=\($0.value.split(whereSeparator: \.isWhitespace).joined(separator: " "))" }.sorted()
      }
      XCTAssertEqual(words(XMLFormatter.prettified(markup)), words(markup))
    }
  }
}
