#if SERVER
  import Foundation

  /// Reconcile two changes to one page, when they do not touch the same lines.
  ///
  /// Two readers find two faults on a page and ask for both. Neither knew of
  /// the other, so each correction was made from the same starting text: one
  /// spells out the side labels, the other replaces a literal "blank". Both are
  /// right, and refusing the second because the first arrived first would make
  /// the order of two clicks decide what the record says.
  ///
  /// So: a line-wise three-way merge, the one a version control system does.
  /// Where only one side changed a line, that side wins. Where both changed the
  /// same line to different text, nothing is guessed—the merge fails and a
  /// person decides, because a merge of two transcriptions is a third
  /// transcription that nobody made and nobody reviewed.
  public enum ThreeWayMerge {
    public enum Outcome: Sendable {
      /// The two changes touch different lines; this is both of them.
      case merged(String)
      /// They disagree about the same line. The lines in question are named so
      /// the page can say where.
      case conflict(lines: [String])
    }

    /// `exact` keeps each line as written: a prompt's indentation is its
    /// Markdown. Otherwise a line is compared, and kept, without the
    /// whitespace around it—a page's markup, indented by its formatter.
    public static func merge(base: String, ours: String, theirs: String, exact: Bool = false) -> Outcome {
      if ours == theirs { return .merged(ours) }
      if ours == base { return .merged(theirs) }
      if theirs == base { return .merged(ours) }

      let baseLines = lines(of: base, exact: exact)
      let ourLines = lines(of: ours, exact: exact)
      let theirLines = lines(of: theirs, exact: exact)

      // Line-wise, anchored on the lines all three still share. Anything else
      // is a guess about intent.
      let common = longestCommonSubsequence(baseLines, ourLines, theirLines)
      guard !common.isEmpty || baseLines.isEmpty else {
        return .conflict(lines: [])
      }

      var merged: [String] = []
      var conflicts: [String] = []
      var baseIndex = 0
      var ourIndex = 0
      var theirIndex = 0

      for anchor in common + [nil] {
        let baseRun = run(of: baseLines, from: &baseIndex, until: anchor)
        let ourRun = run(of: ourLines, from: &ourIndex, until: anchor)
        let theirRun = run(of: theirLines, from: &theirIndex, until: anchor)

        if ourRun == baseRun {
          merged.append(contentsOf: theirRun)
        } else if theirRun == baseRun {
          merged.append(contentsOf: ourRun)
        } else if ourRun == theirRun {
          merged.append(contentsOf: ourRun)
        } else if let both = disjoint(base: baseRun, ours: ourRun, theirs: theirRun) {
          merged.append(contentsOf: both)
        } else {
          conflicts.append(contentsOf: baseRun.isEmpty ? ourRun : baseRun)
          merged.append(contentsOf: ourRun)
        }

        if let anchor {
          merged.append(anchor)
          baseIndex += 1
          ourIndex += 1
          theirIndex += 1
        }
      }

      guard conflicts.isEmpty else { return .conflict(lines: conflicts) }
      return .merged(merged.joined(separator: "\n"))
    }

    /// A change to a stretch of the base: the lines `range` replaced by
    /// `lines` (an insertion where the range is empty).
    struct Hunk: Equatable {
      let range: Range<Int>
      let lines: [String]
    }

    /// Both sides' changes to one stretch between anchors, where they touch
    /// different lines: two neighboring lines each changed by one side
    /// (a page's two paragraphs, laid out a line each) are both kept. Nil
    /// where they change a line in common, or insert at the same place, or
    /// one inserts inside what the other replaces: which goes first, or
    /// what stands, is a guess.
    static func disjoint(base: [String], ours: [String], theirs: [String]) -> [String]? {
      let ourHunks = hunks(from: base, to: ours)
      let theirHunks = hunks(from: base, to: theirs).filter { !ourHunks.contains($0) }
      for our in ourHunks {
        for their in theirHunks {
          let overlapping = our.range.lowerBound < their.range.upperBound && their.range.lowerBound < our.range.upperBound
          if overlapping || our.range.lowerBound == their.range.lowerBound { return nil }
        }
      }
      var out: [String] = []
      var index = 0
      for hunk in (ourHunks + theirHunks).sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        out.append(contentsOf: base[index..<hunk.range.lowerBound])
        out.append(contentsOf: hunk.lines)
        index = hunk.range.upperBound
      }
      out.append(contentsOf: base[index...])
      return out
    }

    /// What changed from `base` to `other`, by their longest common
    /// subsequence: each stretch of the base not in it, and what replaced it.
    static func hunks(from base: [String], to other: [String]) -> [Hunk] {
      // lengths[i][j]: the longest common subsequence of base[i...] and other[j...].
      var lengths = Array(repeating: Array(repeating: 0, count: other.count + 1), count: base.count + 1)
      for i in stride(from: base.count - 1, through: 0, by: -1) {
        for j in stride(from: other.count - 1, through: 0, by: -1) {
          lengths[i][j] = base[i] == other[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
        }
      }
      var out: [Hunk] = []
      var i = 0
      var j = 0
      var start: (Int, Int)?
      func close() {
        if let (baseStart, otherStart) = start {
          out.append(Hunk(range: baseStart..<i, lines: Array(other[otherStart..<j])))
          start = nil
        }
      }
      while i < base.count || j < other.count {
        if i < base.count, j < other.count, base[i] == other[j] {
          close()
          i += 1
          j += 1
        } else {
          if start == nil { start = (i, j) }
          if j < other.count && (i == base.count || lengths[i][j + 1] >= lengths[i + 1][j]) {
            j += 1
          } else {
            i += 1
          }
        }
      }
      close()
      return out
    }

    static func lines(of text: String, exact: Bool = false) -> [String] {
      text.split(separator: "\n", omittingEmptySubsequences: false).map {
        exact ? String($0) : String($0).trimmingCharacters(in: .whitespaces)
      }
    }

    /// The lines from `index` up to the next anchor, moving the index with it.
    static func run(of lines: [String], from index: inout Int, until anchor: String?) -> [String] {
      var out: [String] = []
      while index < lines.count {
        if let anchor, lines[index] == anchor { break }
        out.append(lines[index])
        index += 1
      }
      return out
    }

    /// Lines every version still has, in order: the fixed points a merge can
    /// be anchored on.
    static func longestCommonSubsequence(_ a: [String], _ b: [String], _ c: [String]) -> [String] {
      let shared = Set(a).intersection(Set(b)).intersection(Set(c))
      var out: [String] = []
      var cursorB = 0
      var cursorC = 0
      for line in a where shared.contains(line) && !line.isEmpty {
        guard let inB = index(of: line, in: b, from: cursorB) else { continue }
        guard let inC = index(of: line, in: c, from: cursorC) else { continue }
        out.append(line)
        cursorB = inB + 1
        cursorC = inC + 1
      }
      return out
    }

    static func index(of line: String, in lines: [String], from start: Int) -> Int? {
      var index = start
      while index < lines.count {
        if lines[index] == line { return index }
        index += 1
      }
      return nil
    }
  }
#endif
