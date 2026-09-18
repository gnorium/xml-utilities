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
      /// A side named something the rendition does not call it.
      case labelMismatch
      /// An opening that names two sides and marks neither.
      case sidesUnmarked
      /// A surface whose whole reading is one word standing in for absence.
      ///
      /// The prompt once asked for `<p>blank</p>`, so documents carry it; but
      /// the fault is general — a transcription that says a page is empty is
      /// not a transcription of that page, whatever word it uses.
      case literalBlank
      /// Prose about a surface — its binding, its tooling — in place of a
      /// transcription of what is written on it.
      case description
      /// An element opened and not closed, or closed and not opened.
      case unbalanced

      public var summary: String {
        switch self {
        case .labelMismatch: return "Side named differently from the rendition"
        case .sidesUnmarked: return "Opening does not mark its sides"
        case .literalBlank: return "\"blank\" transcribed as text"
        case .description: return "Described rather than transcribed"
        case .unbalanced: return "Markup does not balance"
        }
      }

      /// What to ask for. The agent is given this verbatim.
      public var instruction: String {
        switch self {
        case .labelMismatch:
          return
            "A side here is named something the rendition is not called. Name each side exactly "
            + "as the rendition names it, using its own words and spelling."
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
    /// How much transcribed text a page carries, in characters.
    ///
    /// A change replaces a whole page, so it can take readings away as easily
    /// as it can mend them — a model that loses its place returns a shorter
    /// page and says nothing about it. Comparing this before and against after
    /// is how a reader is told, before they accept, that a correction of a
    /// label also dropped four lines of verse.
    public static func readingWeight(of markup: String) -> Int {
      lines(in: markup)
        .filter { line in
          switch line.kind {
          case .text, .heading, .speaker, .stage: return true
          case .mark, .forme, .gap: return false
          }
        }
        .reduce(0) { $0 + $1.text.count }
    }
  }

  extension TEIRenderer {
    /// Read one page against the rules and report what it breaks.
    public static func faults(in page: TEIPage) -> [TEIFault] {
      var faults: [TEIFault] = []
      let markup = page.markup
      let sides = sideLabels(in: markup)

      // The rendition's label is the authority on what its sides are called —
      // whatever the manifest that produced it happens to call them. No rule
      // here knows "recto" from "verso", or expects a Western signature: a side
      // is wrong when it is named something this rendition is not called.
      let named = namedSides(of: page.label)
      if let stray = sides.first(where: { side in
        !named.contains { matches($0, side) }
      }) {
        faults.append(.init(kind: .labelMismatch, detail: stray))
      }
      if named.count > 1, sides.count < named.count {
        faults.append(.init(kind: .sidesUnmarked, detail: page.label))
      }
      // A reading that is one short word and nothing else is a statement about
      // the page rather than a transcription of it. The threshold is what makes
      // this general: no list of words to keep in step with a prompt.
      let reading = readingWeight(of: markup)
      let readingLines = lines(in: markup).filter { line in
        if case .text = line.kind { return true }
        return false
      }
      if reading > 0, reading <= 12, readingLines.count <= 2 {
        faults.append(
          .init(kind: .literalBlank, detail: readingLines.map(\.text).joined(separator: " ")))
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

    /// The sides a rendition's own label names.
    ///
    /// A label for more than one surface joins them with a dash or a slash —
    /// "A1 verso – A2 recto", "12/13", "表/裏". A label that joins nothing names
    /// one surface, and that surface is the rendition itself.
    public static func namedSides(of label: String) -> [String] {
      let separators: [String] = [" – ", " — ", " - ", "–", "—", " / ", "/", "|"]
      for separator in separators where label.contains(separator) {
        let parts = label.components(separatedBy: separator)
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
        if parts.count > 1 { return parts }
      }
      let trimmed = label.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? [] : [trimmed]
    }

    /// Two names for one surface, allowing for spacing and case only. Anything
    /// further — knowing that "B1v" and "B1 verso" are the same leaf — is a
    /// convention, and a rule that assumed one would be wrong about every
    /// source that does not follow it.
    static func matches(_ a: String, _ b: String) -> Bool {
      func normalised(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
          .replacingOccurrences(of: ".", with: "")
      }
      return normalised(a) == normalised(b)
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
