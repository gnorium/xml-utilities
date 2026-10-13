#if SERVER
import Foundation

/// A bounded subset of standard TEI CSS rendition, describing source layout.
/// No positioning, text coordinates, URLs, arbitrary selectors or fonts.
public enum TEIRendition {
  public static let properties = [
    "font-size", "line-height", "letter-spacing", "word-spacing", "text-indent", "margin-top", "margin-bottom",
    "margin-left", "margin-right", "margin-block-start", "margin-block-end", "margin-inline-start",
    "margin-inline-end", "text-align", "font-weight", "font-style", "font-variant-caps", "column-gap",
    "inline-size", "block-size", "border-style", "padding", "padding-block", "padding-inline", "padding-block-start",
    "padding-block-end", "padding-inline-start", "padding-inline-end",
  ]

  /// The properties CSS inherits: a child's own declaration of one
  /// overrides its parent's, and where it has none it takes its parent's.
  static let inherited: Set<String> = [
    "font-size", "line-height", "letter-spacing", "word-spacing", "text-indent", "text-align", "font-weight",
    "font-style", "font-variant-caps",
  ]
  /// A block's inline margins: its box's, which the boxes inside it stand
  /// within.
  static let inlineMargins: Set<String> = ["margin-left", "margin-right", "margin-inline-start", "margin-inline-end"]
  /// A block's margin before it: its first child's collapses with it.
  static let startMargins: Set<String> = ["margin-top", "margin-block-start"]
  /// A block's margin after it: its last child's collapses with it.
  static let endMargins: Set<String> = ["margin-bottom", "margin-block-end"]
  /// What draws a block's frame—a printed ruled box (`border-style`), its
  /// inset (`padding…`), its measure (`inline-size`)—and places it: its
  /// own box's, which no child takes.
  public static let frameProperties: Set<String> = [
    "border-style", "padding", "padding-block", "padding-inline", "padding-block-start", "padding-block-end",
    "padding-inline-start", "padding-inline-end", "inline-size", "block-size",
  ]

  public static func valid(property: String, value: String) -> Bool {
    if property == "text-align" { return ["left", "right", "center", "justify", "start", "end"].contains(value) }
    if property == "font-weight" { return ["normal", "bold", "400", "600", "700"].contains(value) }
    if property == "font-style" { return ["normal", "italic"].contains(value) }
    if property == "font-variant-caps" { return ["normal", "small-caps"].contains(value) }
    if property == "border-style" { return ["none", "solid", "double", "dotted", "dashed"].contains(value) }
    guard properties.contains(property), let length = Length(value) else { return false }
    let (number, unit) = (length.value, length.unit)
    switch property {
    case "font-size":
      if unit == "%" { return (50...400).contains(number) }
      if unit == "em" || unit == "rem" { return (0.5...4).contains(number) }
      if unit == "px" { return (8...64).contains(number) }
      if unit == "pt" { return (6...48).contains(number) }
      return false
    case "line-height":
      if unit == "" || unit == "em" { return (0.75...3).contains(number) }
      if unit == "%" { return (75...300).contains(number) }
      return false
    case "inline-size", "block-size":
      // A rule's or a frame's measure (a page's text block's height): up
      // to the page's, never negative.
      if unit == "" { return number == 0 }
      if unit == "%" { return (0...100).contains(number) }
      if unit == "em" || unit == "rem" { return (0...64).contains(number) }
      if unit == "px" || unit == "pt" { return (0...1024).contains(number) }
      return (0...32).contains(number)
    default:
      if unit == "" { return number == 0 }
      let bound = unit == "px" || unit == "pt" ? 512.0 : 32.0
      return abs(number) <= bound && (number >= 0 || ["text-indent", "letter-spacing", "word-spacing"].contains(property))
    }
  }

  public static func tokens(_ css: String) -> String {
    css.split(separator: ";").compactMap { declaration -> String? in
      let pair = declaration.split(separator: ":", maxSplits: 1)
      guard pair.count == 2 else { return nil }
      let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard valid(property: name, value: value) else { return nil }
      return "css:\(name)=\(value)"
    }.joined(separator: " ")
  }

  /// The CSS a rend's `css:` tokens declare; with `only`, just those
  /// properties, with `excluding`, all but those.
  public static func css(from rend: String, only: Set<String>? = nil, excluding: Set<String> = []) -> String {
    rend.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
      guard token.hasPrefix("css:") else { return nil }
      let pair = token.dropFirst(4).split(separator: "=", maxSplits: 1)
      guard pair.count == 2, valid(property: String(pair[0]), value: String(pair[1])) else { return nil }
      let name = String(pair[0])
      guard only?.contains(name) ?? true, !excluding.contains(name) else { return nil }
      return "\(pair[0]):\(pair[1]);"
    }.joined()
  }

  /// The work frame's rendition (gnorium-python `facsimile.frame_rendition`):
  /// the text block every page of the text is set in, its measure
  /// (`inline-size`) and its height (`block-size`) in page-em, the median of
  /// its pages' measured text blocks (`TEIFacsimile.workFrame`). TEI's own
  /// CSS rendition of `<text>` in the header's `<tagsDecl>`, so a document
  /// carries it and a page drawn alone is handed it with the rest
  /// (`header`); derived, written again whenever a page is laid in.
  public static let frameID = "text-block"

  public static func frameRendition(measure: Double, height: Double) -> String {
    "<rendition xml:id=\"\(frameID)\" scheme=\"css\" selector=\"text\">inline-size:\(Length(value: measure, unit: "em").text);"
      + "block-size:\(Length(value: height, unit: "em").text)</rendition>"
  }

  /// The work frame the renditions declare (`frameID`), in page-em; nil
  /// where they declare none.
  public static func frame(in definitions: [String: String]) -> (measure: Double, height: Double)? {
    guard let rend = definitions[frameID] else { return nil }
    let setting = Setting(rend)
    guard let measure = setting.length("inline-size"), measure.unit == "em", measure.value > 0,
      let height = setting.length("block-size"), height.unit == "em", height.value > 0
    else { return nil }
    return (measure.value, height.value)
  }

  public static func header(_ definitions: [String: String]) -> String {
    guard !definitions.isEmpty else { return "" }
    let entries = definitions.keys.sorted().map { id in
      let selector = id == frameID ? " selector=\"text\"" : ""
      return "<rendition xml:id=\"\(XMLFormatter.escapingAttribute(id))\" scheme=\"css\"\(selector)>\(XMLFormatter.escapingAttribute(css(from: definitions[id] ?? "")))</rendition>"
    }.joined()
    return "<teiHeader><encodingDesc><tagsDecl>" + entries + "</tagsDecl></encodingDesc></teiHeader>"
  }

  static func declarations(in root: TEIMarkup.Element) -> [String: String] {
    var result: [String: String] = [:]
    func visit(_ node: TEIMarkup.Element) {
      if node.name == "rendition", ["", "css"].contains(node.attribute("scheme")), !node.attribute("xml:id").isEmpty {
        result[node.attribute("xml:id")] = tokens(node.textContent)
      }
      for child in node.elements { visit(child) }
    }
    visit(root)
    return result
  }

  // MARK: - Cascade

  /// A CSS length as a rend writes it: a number and its unit ("" for none).
  struct Length {
    let value: Double
    let unit: String

    init(value: Double, unit: String) {
      self.value = value
      self.unit = unit
    }

    init?(_ text: String) {
      let pattern = #"^(-?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+))(em|rem|%|px|pt|mm|cm|in|pc)?$"#
      guard let expression = try? NSRegularExpression(pattern: pattern),
        let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text), let number = Double(text[range]), number.isFinite
      else { return nil }
      value = number
      unit = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
    }

    /// As a rend writes it: at most four decimals, no trailing zeros.
    var text: String {
      let rounded = (value * 10_000).rounded() / 10_000
      var number = String(format: "%.4f", rounded)
      while number.hasSuffix("0") { number.removeLast() }
      if number.hasSuffix(".") { number.removeLast() }
      if number == "-0" { number = "0" }
      return number + unit
    }

    /// The same length in an element whose font is `factor` times this
    /// one's: an em counts the element's own font.
    func within(factor: Double) -> Length {
      unit == "em" && factor != 0 ? Length(value: value / factor, unit: unit) : self
    }

    /// The two side by side, where their units allow: nil where they
    /// differ and neither is zero.
    static func combine(_ a: Length, _ b: Length, _ operation: (Double, Double) -> Double) -> Length? {
      if a.unit == b.unit { return Length(value: operation(a.value, b.value), unit: a.unit) }
      if a.value == 0 { return Length(value: operation(0, b.value), unit: b.unit) }
      if b.value == 0 { return Length(value: operation(a.value, 0), unit: a.unit) }
      return nil
    }
  }

  /// A rend read as its tokens, each keyed by what it sets: a later token
  /// of the same key sets it again.
  struct Setting {
    var entries: [(key: String, token: String)] = []

    init(_ rend: String) {
      for token in rend.split(whereSeparator: \.isWhitespace).map(String.init) {
        set(Self.key(of: token), token)
      }
    }

    static func key(of token: String) -> String {
      if token.hasPrefix("css:") { return "css:" + (token.dropFirst(4).split(separator: "=").first.map(String.init) ?? "") }
      for family in ["align(", "indent(", "color("] where token.hasPrefix(family) { return family }
      if TEIRenderer.typefaces.contains(token) { return "typeface" }
      if token == "larger" || token == "smaller" { return "size" }
      return token
    }

    var rend: String { entries.map(\.token).joined(separator: " ") }

    func value(_ property: String) -> String? {
      entries.first { $0.key == "css:" + property }.map { String($0.token.dropFirst(5 + property.count)) }
    }

    func length(_ property: String) -> Length? { value(property).flatMap(Length.init) }

    mutating func set(_ key: String, _ token: String) {
      if let index = entries.firstIndex(where: { $0.key == key }) {
        entries[index].token = token
      } else {
        entries.append((key, token))
      }
    }

    mutating func set(_ property: String, _ length: Length) {
      set("css:" + property, "css:\(property)=\(length.text)")
    }

    mutating func remove(_ properties: Set<String>) {
      entries.removeAll { $0.key.hasPrefix("css:") && properties.contains(String($0.key.dropFirst(4))) }
    }

    /// How many times its parent's its font is, where its own font-size
    /// is relative (em, %): 1 where it sets none, nil where it sets one
    /// absolutely.
    var relativeFont: Double? {
      guard let size = length("font-size") else { return 1 }
      switch size.unit {
      case "em": return size.value
      case "%": return size.value / 100
      default: return nil
      }
    }
  }

  /// How a child's setting meets the one around it.
  public enum Placement: Sendable {
    /// A block inside a block (a paragraph in a division): `first` where
    /// nothing of its parent's comes before it, so the parent's margin
    /// before it collapses with its own.
    case block(first: Bool)
    /// A phrase set in its parent's lines: its own settings override its
    /// parent's, property by property.
    case inline
  }

  /// A child element's rend combined with its parent's as CSS cascades
  /// them (user, 2026-10-13): what the child does not set it takes from
  /// its parent—an inherited property as computed (an em length counted
  /// in the parent's font, read again in the child's), the parent's inline
  /// margins as the box it stands in (added to its own), the parent's
  /// margin before it at its first block (collapsed with its own)—and
  /// what it sets overrides the same property only. Its font-size in em
  /// or % counts its parent's. The parent's frame and its margin after
  /// it are its own box's, never passed on (`closing(_:within:)`). A
  /// keyword overrides the parent's of its kind (an alignment, an indent,
  /// an ink, a typeface, a step of size); any other is kept beside it.
  public static func cascade(_ parent: String, _ child: String, _ placement: Placement = .block(first: false)) -> String {
    guard !parent.isEmpty else { return child }
    let own = Setting(child)
    var result = Setting(parent)
    let factor = own.relativeFont
    if case .block(let first) = placement {
      // The parent's own box: its frame, its margin after it, and its
      // margin before it unless this is its first block.
      result.remove(frameProperties.union(endMargins).union(["column-gap"]))
      if !first { result.remove(startMargins) }
      // An inherited length is inherited as computed: in the child's em.
      if let factor, factor != 1 {
        for property in inherited.union(inlineMargins).union(startMargins) where property != "font-size" {
          if let length = result.length(property) { result.set(property, length.within(factor: factor)) }
        }
      }
    }
    for entry in own.entries {
      let property = entry.key.hasPrefix("css:") ? String(entry.key.dropFirst(4)) : ""
      switch property {
      case "font-size":
        if let parentSize = result.length("font-size"), let factor {
          result.set(property, Length(value: parentSize.value * factor, unit: parentSize.unit))
        } else {
          result.set(entry.key, entry.token)
        }
      case _ where inlineMargins.contains(property) && placement.isBlock:
        if let mine = own.length(property), let theirs = result.length(property),
          let sum = Length.combine(theirs, mine, +)
        {
          result.set(property, sum)
        } else {
          result.set(entry.key, entry.token)
        }
      case _ where startMargins.contains(property) && placement.isBlock:
        if let mine = own.length(property), let theirs = result.length(property),
          let larger = Length.combine(theirs, mine, max)
        {
          result.set(property, larger)
        } else {
          result.set(entry.key, entry.token)
        }
      default:
        result.set(entry.key, entry.token)
      }
    }
    return result.rend
  }

  /// A block's rend at the end of `parent`, the last of its blocks: the
  /// parent's margin after it collapses with the block's own, counted in
  /// the block's font.
  public static func closing(_ rend: String, within parent: String) -> String {
    let outer = Setting(parent)
    var inner = Setting(rend)
    guard let factor = font(of: inner, within: outer) else { return rend }
    for property in endMargins {
      guard let theirs = outer.length(property)?.within(factor: factor) else { continue }
      if let mine = inner.length(property) {
        if let larger = Length.combine(theirs, mine, max) { inner.set(property, larger) }
      } else {
        inner.set(property, theirs)
      }
    }
    return inner.rend
  }

  /// How many times `outer`'s font a cascaded `inner`'s is: nil where
  /// their sizes are not in one unit.
  private static func font(of inner: Setting, within outer: Setting) -> Double? {
    switch (inner.length("font-size"), outer.length("font-size")) {
    case (nil, nil): return 1
    case (let size?, nil): return size.unit == "em" ? size.value : size.unit == "%" ? size.value / 100 : nil
    case (let size?, let around?) where size.unit == around.unit && around.value != 0: return size.value / around.value
    default: return nil
    }
  }

  /// A frame's own box, counted in the font around it: its border, inset,
  /// measure and margins, an em of its own font read in the font of what
  /// it stands in (the page's, where `rend`'s font-size is relative to it).
  public static func frame(of rend: String) -> String {
    let setting = Setting(rend)
    var frame = Setting("")
    let factor = setting.relativeFont ?? 1
    let box = frameProperties.union(inlineMargins).union(startMargins).union(endMargins)
    for entry in setting.entries where entry.key.hasPrefix("css:") && box.contains(String(entry.key.dropFirst(4))) {
      let property = String(entry.key.dropFirst(4))
      guard let value = setting.value(property) else { continue }
      if let length = Length(value) {
        frame.set(property, Length(value: length.unit == "em" ? length.value * factor : length.value, unit: length.unit))
      } else {
        frame.set("css:" + property, "css:\(property)=\(value)")
      }
    }
    return frame.rend
  }

  /// A block's rend inside a column container that draws the container's
  /// inline margins itself (`columnMargins(of:)`): the block's own, less
  /// the container's it took by cascade.
  public static func inColumns(_ rend: String, of container: String) -> String {
    let outer = Setting(container)
    var inner = Setting(rend)
    guard let factor = font(of: inner, within: outer) else { return rend }
    for property in inlineMargins {
      guard let theirs = outer.length(property)?.within(factor: factor), let mine = inner.length(property),
        let rest = Length.combine(mine, theirs, -)
      else { continue }
      if abs(rest.value) < 0.0001 { inner.remove([property]) } else { inner.set(property, rest) }
    }
    return inner.rend
  }

  /// What a framed block's lines take of its setting: all but the frame's
  /// own box (`frame(of:)`), which the frame draws.
  public static func inside(frame rend: String) -> String {
    var setting = Setting(rend)
    setting.remove(frameProperties.union(inlineMargins).union(startMargins).union(endMargins))
    return setting.rend
  }

  /// Whether a rend draws a printed frame around its block.
  public static func frames(_ rend: String) -> Bool {
    guard let style = Setting(rend).value("border-style") else { return false }
    return style != "none"
  }

  /// A column container's gap, counted in the font around it, as `frame`
  /// counts a frame's box: nil where it sets none.
  public static func columnGap(of rend: String) -> String? {
    let setting = Setting(rend)
    guard let gap = setting.length("column-gap") else { return nil }
    let factor = setting.relativeFont ?? 1
    return Length(value: gap.unit == "em" ? gap.value * factor : gap.value, unit: gap.unit).text
  }

  /// A column container's inline margins, counted in the font around it.
  public static func columnMargins(of rend: String) -> String {
    let setting = Setting(rend)
    let factor = setting.relativeFont ?? 1
    return inlineMargins.sorted().compactMap { property -> String? in
      guard let length = setting.length(property) else { return nil }
      let outer = Length(value: length.unit == "em" ? length.value * factor : length.value, unit: length.unit)
      // Drawn as the container's padding (`TEIView`): its columns stand
      // within it.
      let padding = property.replacingOccurrences(of: "margin", with: "padding")
      return "\(padding):\(outer.text);"
    }.joined()
  }
}

extension TEIRendition.Placement {
  var isBlock: Bool {
    if case .block = self { return true }
    return false
  }
}
#endif
