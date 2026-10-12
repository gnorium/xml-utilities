import XCTest

@testable import XMLUtilities

/// `ThreeWayMerge`: two corrections from one text merge, as diff3 merges
/// them, where an unchanged line stands between them; where they touch the
/// same or neighboring lines, a person decides.
final class ThreeWayMergeTests: XCTestCase {
  static let base = "<div>\n  <p>One</p>\n  <p>Two</p>\n  <p>Three</p>\n</div>"

  private func merged(_ ours: String, _ theirs: String) -> String? {
    if case .merged(let text) = ThreeWayMerge.merge(base: Self.base, ours: ours, theirs: theirs) { return text }
    return nil
  }

  /// Lines with an unchanged line between them merge; neighboring lines
  /// conflict, as in diff3 and Git.
  func testOnlyLinesApartMerge() {
    let one = Self.base.replacingOccurrences(of: "One", with: "Uno")
    XCTAssertEqual(
      merged(one, Self.base.replacingOccurrences(of: "Three", with: "Tres")),
      "<div>\n<p>Uno</p>\n<p>Two</p>\n<p>Tres</p>\n</div>")
    XCTAssertNil(merged(one, Self.base.replacingOccurrences(of: "Two", with: "Dos")))
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
