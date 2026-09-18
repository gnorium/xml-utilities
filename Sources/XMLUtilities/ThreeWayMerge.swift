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
  /// same line to different text, nothing is guessed — the merge fails and a
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

    public static func merge(base: String, ours: String, theirs: String) -> Outcome {
      if ours == theirs { return .merged(ours) }
      if ours == base { return .merged(theirs) }
      if theirs == base { return .merged(ours) }

      let baseLines = lines(of: base)
      let ourLines = lines(of: ours)
      let theirLines = lines(of: theirs)

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

    static func lines(of text: String) -> [String] {
      text.split(separator: "\n", omittingEmptySubsequences: false).map {
        String($0).trimmingCharacters(in: .whitespaces)
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
