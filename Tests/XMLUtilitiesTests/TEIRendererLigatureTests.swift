import XCTest
import XMLUtilities

/// Ligatures as typeset (user, 2026-10-31): a `<g ref>` naming a ligature
/// draws its letters as one run carrying `ligature`, inside a word and an
/// italic run alike; its text stays the plain letters, and a long s's `<g>`
/// is no ligature.
final class TEIRendererLigatureTests: XCTestCase {
  func testALigatureIsARunOfItsLettersCarryingLigature() {
    let lines = TEIRenderer.lines(
      in: ##"<body><ab><lb facs="#z-L1"/><w>Mo<g ref="#slongt">ſt</g></w> <w><g ref="#slong">ſ</g>o</w> <hi rend="italic"><w>o<g ref="#ff">ff</g>ice</w></hi> <w>a<g ref="#ct">ct</g></w></ab></body>"##)
    XCTAssertEqual(lines.map(\.text), ["Moſt ſo office act"])
    let ligatures = lines[0].runs.filter { $0.rend.split(separator: " ").contains("ligature") }
    XCTAssertEqual(ligatures.map(\.text), ["ſt", "ff", "ct"])
    XCTAssertTrue(ligatures[1].rend.contains("italic"))
    XCTAssertFalse(lines[0].runs.contains { $0.text == "ſ" && $0.rend.contains("ligature") })
  }

  func testEveryLigatureRefIsALigatureAndTheLetterFormsAreNot() {
    XCTAssertEqual(TEIRenderer.ligatures.count, 16)
    XCTAssertFalse(TEIRenderer.ligatures.contains("slong"))
    XCTAssertFalse(TEIRenderer.ligatures.contains("rrot"))
    XCTAssertTrue(TEIRenderer.ligatures.isSuperset(of: ["ct", "st", "slongt", "fi", "slongslongi"]))
  }

  func testAPresentationFormIsItsLettersToASearch() {
    XCTAssertEqual(TEIRenderer.unligatured("\u{FB01}re mo\u{FB05} \u{FB00}"), "fire moſt ff")
    XCTAssertEqual(TEIRenderer.unligatured("fire"), "fire")
    XCTAssertEqual(TEIRenderer.presentationForms.count, 7)
    XCTAssertNil(TEIRenderer.presentationForms["ct"])
  }
}
