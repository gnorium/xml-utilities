#if SERVER
  extension TEIRenderer {
    /// The most lines an initial drops through: a deeper zone is a
    /// woodcut's block, never a letter's.
    static let dropLimit = 8

    /// The lines with each initial dropped as the print sets it (Hamlet Q1
    /// p. 3, user 2026-11-01: the S of "1. STand: who is that?" two lines
    /// deep, "2. Tis I." beside it). An initial is the first letter of its
    /// word (`<hi rend="initial" facs="#…">`, its zone the initial's box on
    /// the surface); the lines after its own whose zones it covers half of or
    /// more (`covers`), in the same column, stand beside it: the initial's
    /// run spans its line and those (`TEILine.Run.drop`), and each of them
    /// begins its text after it (`TEILine.hang`). The first line below the
    /// initial ends the count.
    static func dropped(_ lines: [TEILine]) -> [TEILine] {
      var lines = lines
      for index in lines.indices {
        guard let run = lines[index].runs.firstIndex(where: { isInitial($0) }),
          let initial = lines[index].runs[run].zone
        else { continue }
        var beside: [Int] = []
        var next = index + 1
        while next < lines.count, beside.count < dropLimit - 1, lines[next].column == lines[index].column,
          let zone = lines[next].zone, covers(initial, zone)
        {
          beside.append(next)
          next += 1
        }
        guard !beside.isEmpty else { continue }
        let drop = beside.count + 1
        var runs = lines[index].runs
        runs[run].drop = drop
        lines[index].runs = runs
        let hang = TEILine.Hang(letter: runs[run].text, lines: drop)
        for line in beside { lines[line].hang = hang }
      }
      return lines
    }

    /// Whether a run is an initial with its box: `<hi rend="initial">`
    /// naming a zone.
    static func isInitial(_ run: TEILine.Run) -> Bool {
      guard run.zone != nil, case .text = run.kind else { return false }
      return run.rend.split(whereSeparator: \.isWhitespace).contains("initial")
    }

    /// Whether an initial's zone covers half of a line's height or more.
    static func covers(_ initial: TEIZone, _ line: TEIZone) -> Bool {
      let height = line.lry - line.uly
      guard height > 0 else { return false }
      return (min(initial.lry, line.lry) - max(initial.uly, line.uly)) / height >= 0.5
    }
  }
#endif
