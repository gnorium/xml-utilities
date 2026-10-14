#if SERVER
import Foundation

/// The frame a work's pages are set in (`TEIRendition.frameRendition`): its
/// body type on its scans, in their pixels per em, and in that em the main
/// text block's measure and height and the margin around a page's content.
public struct TEIWorkFrame: Sendable, Equatable {
  public let body: Double
  public let measure: Double
  public let height: Double
  public let margin: Double

  public init(body: Double, measure: Double, height: Double, margin: Double) {
    self.body = body
    self.measure = measure
    self.height = height
    self.margin = margin
  }
}

/// The frame one page is set in (`TEIPage.frame`), in em of its work's body
/// type: the main text block's measure and height, and the equal margin
/// around the page's content; and, for a page genuinely larger than its
/// work's (a plate, a foldout), its own size (0 for any other page).
public struct TEIPageFrame: Sendable, Equatable {
  public let measure: Double
  public let height: Double
  public let margin: Double
  public let pageWidth: Double
  public let pageHeight: Double

  public init(measure: Double, height: Double, margin: Double, pageWidth: Double = 0, pageHeight: Double = 0) {
    self.measure = measure
    self.height = height
    self.margin = margin
    self.pageWidth = pageWidth
    self.pageHeight = pageHeight
  }
}

/// A bounded subset of standard TEI CSS rendition, describing source layout.
/// No positioning, text coordinates, URLs, arbitrary selectors or fonts.
public enum TEIRendition {
  public static let properties = [
    "font-size", "line-height", "letter-spacing", "word-spacing", "text-indent", "margin-top", "margin-bottom",
    "margin-left", "margin-right", "margin-block-start", "margin-block-end", "margin-inline-start",
    "margin-inline-end", "text-align", "font-weight", "font-style", "font-variant-caps", "font-variant-numeric",
    "column-gap",
    "inline-size", "block-size", "border-style", "padding", "padding-block", "padding-inline", "padding-block-start",
    "padding-block-end", "padding-inline-start", "padding-inline-end",
  ]

  /// The properties CSS inherits: a child's own declaration of one
  /// overrides its parent's, and where it has none it takes its parent's.
  static let inherited: Set<String> = [
    "font-size", "line-height", "letter-spacing", "word-spacing", "text-indent", "text-align", "font-weight",
    "font-style", "font-variant-caps", "font-variant-numeric",
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
    // Old-style or lining figures, as the print sets its numerals (the
    // edition face's onum and lnum).
    if property == "font-variant-numeric" { return ["normal", "oldstyle-nums", "lining-nums"].contains(value) }
    if property == "border-style" { return ["none", "solid", "double", "dotted", "dashed"].contains(value) }
    guard properties.contains(property), let length = Length(value) else { return false }
    let (number, unit) = (length.value, length.unit)
    switch property {
    case "font-size":
      return bodyEm(of: length).map(fontSizes.contains) ?? false
    case "line-height":
      if unit == "" || unit == "em" { return (0.75...3).contains(number) }
      if unit == "%" { return (75...300).contains(number) }
      return false
    case "inline-size", "block-size":
      // A rule's or a frame's measure (a page's text block's height): up
      // to a page's, never negative. Lengths are in the body type's em
      // (user, 2026-10-14), a page some sixty of them wide and eighty
      // tall: twice the page-em bounds they replace.
      if unit == "" { return number == 0 }
      if unit == "%" { return (0...100).contains(number) }
      if unit == "em" || unit == "rem" { return (0...128).contains(number) }
      if unit == "px" || unit == "pt" { return (0...2048).contains(number) }
      return (0...64).contains(number)
    default:
      if unit == "" { return number == 0 }
      let bound = unit == "px" || unit == "pt" ? 1024.0 : 64.0
      return abs(number) <= bound && (number >= 0 || ["text-indent", "letter-spacing", "word-spacing"].contains(property))
    }
  }

  /// The type sizes a page may set, in em of the work's body type (its
  /// 1em, the renderer's 16 px): each written value, and each element's size as the
  /// cascade computes it (`cascade`), so a size written inside a smaller
  /// one is held to the same bounds (user, 2026-10-14). gnorium-python's
  /// `tei_encoding.FONT_SIZES`.
  public static let fontSizes: ClosedRange<Double> = 0.5...4

  /// A font-size in em of the body type: em and rem as written (the
  /// page's font is the root's, the body type), % of it, px of its 16, pt
  /// as CSS's 4/3 px; nil for a unit a font-size does not take.
  static func bodyEm(of size: Length) -> Double? {
    switch size.unit {
    case "em", "rem": return size.value
    case "%": return size.value / 100
    case "px": return size.value / 16
    case "pt": return size.value / 12
    default: return nil
    }
  }

  /// The font-size a cascaded rend (`cascade`) computes, in em: 1
  /// where it sets none.
  public static func fontSize(of rend: String) -> Double? {
    guard let size = Setting(rend).length("font-size") else { return 1 }
    return bodyEm(of: size)
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

  /// The work frame's rendition (gnorium-python `facsimile.frame_rendition`,
  /// user, 2026-10-14): the work's body type on its scans (`font-size`, in
  /// the scans' pixels, as its surfaces' graphics count them: type set on
  /// an image shown at its own pixels), and in that em the main text block
  /// every page of the text is set in—its measure (`inline-size`) and its
  /// height (`block-size`)—and the margin around a page's content
  /// (`margin`): the medians of its pages' measured main text blocks
  /// (`TEIFacsimile.workFrame`). TEI's own CSS rendition of `<text>` in the
  /// header's `<tagsDecl>`, so a document carries it and a page drawn alone
  /// is handed it with the rest (`header`); derived, written again whenever
  /// a page is laid in. Every em the TEI writes is this body type's.
  public static let frameID = "text-block"

  public static func frameRendition(_ frame: TEIWorkFrame) -> String {
    "<rendition xml:id=\"\(frameID)\" scheme=\"css\" selector=\"text\">"
      + "font-size:\(Length(value: frame.body, unit: "px").text);inline-size:\(Length(value: frame.measure, unit: "em").text);"
      + "block-size:\(Length(value: frame.height, unit: "em").text);margin:\(Length(value: frame.margin, unit: "em").text)"
      + "</rendition>"
  }

  /// The work frame the renditions declare (`frameID`); nil where they
  /// declare none, or one without its body type.
  public static func frame(in definitions: [String: String]) -> TEIWorkFrame? {
    guard let rend = definitions[frameID] else { return nil }
    let setting = Setting(rend)
    guard let body = setting.length("font-size"), body.unit == "px", body.value > 0,
      let measure = setting.length("inline-size"), measure.unit == "em", measure.value > 0,
      let height = setting.length("block-size"), height.unit == "em", height.value > 0,
      let margin = setting.length("margin"), margin.unit == "em", margin.value >= 0
    else { return nil }
    return TEIWorkFrame(body: body.value, measure: measure.value, height: height.value, margin: margin.value)
  }

  /// The work frame's declarations as tokens: its four lengths, each in its
  /// unit (`frame(in:)`), never a property a page's text takes.
  static func frameTokens(_ css: String) -> String {
    let units = ["font-size": "px", "inline-size": "em", "block-size": "em", "margin": "em"]
    return css.split(separator: ";").compactMap { declaration -> String? in
      let pair = declaration.split(separator: ":", maxSplits: 1)
      guard pair.count == 2 else { return nil }
      let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard let unit = units[name], let length = Length(value), length.unit == unit, length.value >= 0 else { return nil }
      return "css:\(name)=\(value)"
    }.joined(separator: " ")
  }

  public static func header(_ definitions: [String: String]) -> String {
    guard !definitions.isEmpty else { return "" }
    let entries = definitions.keys.sorted().map { id in
      let selector = id == frameID ? " selector=\"text\"" : ""
      let declared = id == frameID ? frame(in: definitions).map(frameDeclarations) ?? "" : css(from: definitions[id] ?? "")
      return "<rendition xml:id=\"\(XMLFormatter.escapingAttribute(id))\" scheme=\"css\"\(selector)>\(XMLFormatter.escapingAttribute(declared))</rendition>"
    }.joined()
    return "<teiHeader><encodingDesc><tagsDecl>" + entries + "</tagsDecl></encodingDesc></teiHeader>"
  }

  /// The work frame's declarations as its rendition writes them.
  static func frameDeclarations(_ frame: TEIWorkFrame) -> String {
    let rendition = frameRendition(frame)
    guard let open = rendition.firstIndex(of: ">"), let close = rendition.range(of: "</rendition>") else { return "" }
    return String(rendition[rendition.index(after: open)..<close.lowerBound])
  }

  static func declarations(in root: TEIMarkup.Element) -> [String: String] {
    var result: [String: String] = [:]
    func visit(_ node: TEIMarkup.Element) {
      if node.name == "rendition", ["", "css"].contains(node.attribute("scheme")), !node.attribute("xml:id").isEmpty {
        let id = node.attribute("xml:id")
        result[id] = id == frameID ? frameTokens(node.textContent) : tokens(node.textContent)
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
    var own = Setting(child)
    var result = Setting(parent)
    // A size the cascade computes outside the page's bounds (`fontSizes`)
    // is no size, as a written one outside them is not (`valid`): the
    // child keeps its parent's.
    if let size = own.length("font-size") {
      let computed = result.length("font-size").flatMap { around in
        own.relativeFont.map { Length(value: around.value * $0, unit: around.unit) }
      } ?? size
      if !(bodyEm(of: computed).map(fontSizes.contains) ?? false) { own.remove(["font-size"]) }
    }
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
