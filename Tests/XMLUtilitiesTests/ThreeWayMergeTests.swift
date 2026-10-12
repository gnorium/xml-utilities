import XCTest

@testable import XMLUtilities

/// `ThreeWayMerge`: two corrections from one text merge where they touch
/// different lines, neighboring lines too; where they touch the same, a
/// person decides.
final class ThreeWayMergeTests: XCTestCase {
  static let base = "<div>\n  <p>One</p>\n  <p>Two</p>\n  <p>Three</p>\n</div>"

  private func merged(_ ours: String, _ theirs: String) -> String? {
    if case .merged(let text) = ThreeWayMerge.merge(base: Self.base, ours: ours, theirs: theirs) { return text }
    return nil
  }

  /// A page's paragraphs laid out a line each: one side changes the
  /// first, the other the second; both stand.
  func testNeighboringLinesMerge() {
    let ours = Self.base.replacingOccurrences(of: "One", with: "Uno")
    let theirs = Self.base.replacingOccurrences(of: "Two", with: "Dos")
    XCTAssertEqual(merged(ours, theirs), "<div>\n<p>Uno</p>\n<p>Dos</p>\n<p>Three</p>\n</div>")
    XCTAssertEqual(merged(theirs, ours), "<div>\n<p>Uno</p>\n<p>Dos</p>\n<p>Three</p>\n</div>")
  }

  func testALineAddedBesideALineChangedMerges() {
    let ours = Self.base.replacingOccurrences(of: "<p>One</p>", with: "<p>Uno</p>")
    let theirs = Self.base.replacingOccurrences(of: "  <p>Three</p>", with: "  <p>Two and a half</p>\n  <p>Three</p>")
    XCTAssertEqual(merged(ours, theirs), "<div>\n<p>Uno</p>\n<p>Two</p>\n<p>Two and a half</p>\n<p>Three</p>\n</div>")
  }

  func testTheSameLineChangedTwoWaysConflicts() {
    XCTAssertNil(merged(
      Self.base.replacingOccurrences(of: "Two", with: "Dos"), Self.base.replacingOccurrences(of: "Two", with: "Deux")))
  }

  /// Two lines put in at one place: which goes first is a guess.
  func testTwoInsertionsAtOnePlaceConflict() {
    XCTAssertNil(merged(
      Self.base.replacingOccurrences(of: "  <p>Two</p>", with: "  <p>A</p>\n  <p>Two</p>"),
      Self.base.replacingOccurrences(of: "  <p>Two</p>", with: "  <p>B</p>\n  <p>Two</p>")))
  }

  /// One side replaces two lines, the other changes one of them.
  func testAChangeInsideAnotherConflicts() {
    XCTAssertNil(merged(
      Self.base.replacingOccurrences(of: "  <p>One</p>\n  <p>Two</p>", with: "  <p>One and two</p>"),
      Self.base.replacingOccurrences(of: "Two", with: "Dos")))
  }
}
