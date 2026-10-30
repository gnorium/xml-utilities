import XCTest
import XMLUtilities

/// Hamlet Q1 p. 9 (dev, 2026-10-30, calibration_pages for p15150coll3:1374):
/// an italic run ends at its `</hi>`, across `<w>` words, `<lb>`s and blocks.
/// The trace that drew all of "Marc. My good Lord." in italic drew its TEI
/// as filed: the transcription had the whole line in one `<hi>`.
final class TEIRendererItalicRunTests: XCTestCase {
  func testAnItalicRunEndsAtItsCloseTagAcrossLinesAndBlocks() {
    let lines = TEIRenderer.lines(
      in: ##"<body><ab rendition="#size-2 #leading-2"><lb facs="#z-L32"/>but what make you from <hi rend="italic">Wittenberg Horatio?</hi></ab><ab rendition="#size-1 #leading-1"><lb facs="#z-L33"/>Marcellus.</ab><ab rendition="#size-2 #leading-2"><lb facs="#z-L34"/><hi rend="italic">Marc.</hi> My good Lord.<lb facs="#z-L35"/><hi rend="italic">Ham.</hi> I am very glad to <g ref="#slong">ſ</g>ee you,</ab></body>"##)
    let italic = lines.map { $0.runs.filter { $0.rend.contains("italic") }.map(\.text).joined() }
    let roman = lines.map { $0.runs.filter { !$0.rend.contains("italic") }.map(\.text).joined() }
    XCTAssertEqual(lines.map(\.text), [
      "but what make you from Wittenberg Horatio?", "Marcellus.", "Marc. My good Lord.",
      "Ham. I am very glad to ſee you,",
    ])
    XCTAssertEqual(italic, ["Wittenberg Horatio?", "", "Marc.", "Ham."])
    XCTAssertEqual(roman, ["but what make you from ", "Marcellus.", " My good Lord.", " I am very glad to ſee you,"])
  }

  func testAnItalicRunOfWordsEndsAtItsCloseTag() {
    let lines = TEIRenderer.lines(
      in: ##"<body><ab rendition="#size-2 #leading-2 #indent-1"><lb facs="#z-L34"/><hi rend="italic"><w facs="#wz254">Marc</w>.</hi> <w facs="#wz255">My</w> <w facs="#wz256">good</w> <w facs="#wz257">Lord</w>.</ab></body>"##)
    XCTAssertEqual(lines.map(\.text), ["Marc. My good Lord."])
    XCTAssertEqual(lines[0].runs.filter { $0.rend.contains("italic") }.map(\.text).joined(), "Marc.")
    XCTAssertEqual(lines[0].runs.filter { !$0.rend.contains("italic") }.map(\.text).joined(), " My good Lord.")
  }
}
