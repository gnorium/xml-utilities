#if SERVER
  import Foundation

  /// What is wrong with a page, by the rules a diplomatic transcript is held to.
  ///
  /// Every fault here was found in a vouched document, and every one of them is
  /// mechanical to state: a reader should not have to know the rules to see that
  /// a page breaks them. Each carries the instruction that would put it right,
  /// so the page can offer to have it corrected rather than only complain.
  public struct TEIFault: Sendable {
    public enum Kind: String, Sendable {
      /// `<pb n="B1v"/>` where the rendition is named "B1 verso".
      case shorthandLabel
      /// An opening that names two sides and marks neither.
      case sidesUnmarked
      /// The word "blank" standing as if it were transcribed text.
      case literalBlank
      /// Prose about a surface — its binding, its tooling — in place of a
      /// transcription of what is written on it.
      case description
      /// An element opened and not closed, or closed and not opened.
      case unbalanced

      public var summary: String {
        switch self {
        case .shorthandLabel: return "Side labelled in catalogue shorthand"
        case .sidesUnmarked: return "Opening does not mark its sides"
        case .literalBlank: return "\"blank\" transcribed as text"
        case .description: return "Described rather than transcribed"
        case .unbalanced: return "Markup does not balance"
        }
      }

      /// What to ask for. The agent is given this verbatim.
      public var instruction: String {
        switch self {
        case .shorthandLabel:
          return
            "Spell every side label as the rendition names it — \"B1 verso\", not \"B1v\"."
        case .sidesUnmarked:
          return
            "This opening names two sides but marks neither. Give each side its own <pb n=\"…\"/> "
            + "before its content, spelled as the rendition names it."
        case .literalBlank:
          return
            "The word \"blank\" is standing here as if it were transcribed text. A surface with "
            + "nothing on it carries <gap reason=\"blank\"/> instead."
        case .description:
          return
            "This is a description of the surface rather than a transcription of it. Transcribe "
            + "what is written; mark decoration as <figure> with a few words of <desc>; a surface "
            + "bearing no text carries <gap reason=\"blank\"/>."
        case .unbalanced:
          return "An element here is opened and not closed, or closed and not opened. Repair it."
        }
      }
    }

    public let kind: Kind
    /// What in the page shows it, when quoting helps.
    public let detail: String?

    public init(kind: Kind, detail: String? = nil) {
      self.kind = kind
      self.detail = detail
    }
  }

  extension TEIRenderer {
    /// Read one page against the rules and report what it breaks.
    public static func faults(in page: TEIPage) -> [TEIFault] {
      var faults: [TEIFault] = []
      let markup = page.markup
      let sides = sideLabels(in: markup)

      if let shorthand = sides.first(where: { isShorthand($0) }) {
        faults.append(.init(kind: .shorthandLabel, detail: shorthand))
      }
      if page.label.contains("–"), sides.count < 2 {
        faults.append(.init(kind: .sidesUnmarked, detail: page.label))
      }
      if markup.range(of: ">blank<", options: .caseInsensitive) != nil
        || markup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "blank"
      {
        faults.append(.init(kind: .literalBlank, detail: nil))
      }
      if let prose = descriptiveProse(in: markup) {
        faults.append(.init(kind: .description, detail: prose))
      }
      if let tag = unbalancedElement(in: markup) {
        faults.append(.init(kind: .unbalanced, detail: tag))
      }
      return faults
    }

    static func sideLabels(in markup: String) -> [String] {
      var labels: [String] = []
      var cursor = markup.startIndex
      while let open = markup.range(of: "<pb", range: cursor..<markup.endIndex) {
        guard let close = markup.range(of: ">", range: open.upperBound..<markup.endIndex) else {
          break
        }
        let tag = String(markup[open.lowerBound..<close.upperBound])
        let label = XMLFormatter.attribute("n", in: tag)
        if !label.isEmpty { labels.append(label) }
        cursor = close.upperBound
      }
      return labels
    }

    /// `A1v`, `front endleaf 2v` — a side written the way a catalogue writes it.
    static func isShorthand(_ label: String) -> Bool {
      guard let last = label.last, last == "r" || last == "v" else { return false }
      let stem = label.dropLast()
      guard let previous = stem.last, previous.isNumber else { return false }
      return true
    }

    /// A long unbroken sentence about the page, where lines of a transcription
    /// would be. A transcript keeps its line breaks; prose about a binding has
    /// none to keep.
    static func descriptiveProse(in markup: String) -> String? {
      var cursor = markup.startIndex
      while let open = markup.range(of: "<p>", range: cursor..<markup.endIndex) {
        guard let close = markup.range(of: "</p>", range: open.upperBound..<markup.endIndex)
        else { break }
        let paragraph = String(markup[open.upperBound..<close.lowerBound])
        cursor = close.upperBound
        guard !paragraph.contains("<lb") else { continue }
        let text = XMLFormatter.decodingEntities(
          paragraph.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 160 {
          return String(text.prefix(120)) + "…"
        }
      }
      return nil
    }

    static func unbalancedElement(in markup: String) -> String? {
      let voids: Set<String> = ["pb", "lb", "gap", "cb", "space", "milestone"]
      var open: [String: Int] = [:]
      var closed: [String: Int] = [:]
      var cursor = markup.startIndex
      while let start = markup.range(of: "<", range: cursor..<markup.endIndex) {
        guard let end = markup.range(of: ">", range: start.upperBound..<markup.endIndex) else {
          break
        }
        let tag = String(markup[start.upperBound..<end.lowerBound])
        cursor = end.upperBound
        guard !tag.hasPrefix("!"), !tag.hasPrefix("?") else { continue }
        if tag.hasPrefix("/") {
          let name = String(tag.dropFirst()).trimmingCharacters(in: .whitespaces)
          closed[name, default: 0] += 1
          continue
        }
        guard !tag.hasSuffix("/") else { continue }
        let name = tag.split(separator: " ").first.map(String.init) ?? tag
        guard !voids.contains(name) else { continue }
        open[name, default: 0] += 1
      }
      for name in Set(open.keys).union(closed.keys)
      where open[name, default: 0] != closed[name, default: 0] {
        return name
      }
      return nil
    }
  }
#endif
