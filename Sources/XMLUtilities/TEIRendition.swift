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
  /// The width of the work's scans in its em (`max-inline-size`; gnorium-python
  /// `WorkFrame.width`, user, 2026-10-18): the book is set in one type, so a
  /// scan of it, at any resolution, has its em as its width over this. 0
  /// where the frame does not declare it.
  public let width: Double

  public init(body: Double, measure: Double, height: Double, margin: Double, width: Double = 0) {
    self.body = body
    self.measure = measure
    self.height = height
    self.margin = margin
    self.width = width
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
    "padding-block-end", "padding-inline-start", "padding-inline-end", "background-color",
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
  /// inset (`padding…`), its measure (`inline-size`), its own ground (a
  /// shaded box, a tinted panel: `background-color`)—and places it: its
  /// own box's, which no child takes.
  public static let frameProperties: Set<String> = [
    "border-style", "padding", "padding-block", "padding-inline", "padding-block-start", "padding-block-end",
    "padding-inline-start", "padding-inline-end", "inline-size", "block-size", "background-color",
  ]

  /// The largest length a CSS length (and a `<space>`'s) may measure in
  /// `unit`: in the body type's em, twice the page-em bounds they replace.
  /// gnorium-python's `tei_encoding._length_bound`.
  public static func lengthBound(unit: String) -> Double {
    unit == "px" || unit == "pt" ? 1024 : 64
  }

  public static func valid(property: String, value: String) -> Bool {
    if property == "text-align" { return ["left", "right", "center", "justify", "start", "end"].contains(value) }
    if property == "font-weight" { return ["normal", "bold", "400", "600", "700"].contains(value) }
    if property == "font-style" { return ["normal", "italic"].contains(value) }
    if property == "font-variant-caps" { return ["normal", "small-caps"].contains(value) }
    // Old-style or lining figures, as the print sets its numerals (the
    // edition face's onum and lnum).
    if property == "font-variant-numeric" { return ["normal", "oldstyle-nums", "lining-nums"].contains(value) }
    if property == "border-style" { return ["none", "solid", "double", "dotted", "dashed"].contains(value) }
    // A region's own ground (user, 2026-10-25: gnorium-python
    // `base_tei.fills`), drawn as encoded in every theme: "#rrggbb" only.
    if property == "background-color" { return isHexColor(value) }
    guard properties.contains(property), let length = Length(value) else { return false }
    let (number, unit) = (length.value, length.unit)
    switch property {
    case "font-size":
      return bodyEm(of: length).map(fontSizes.contains) ?? false
    case "line-height":
      if unit == "" || unit == "em" { return (0.75...3).contains(number) }
      if unit == "%" { return (75...300).contains(number) }
      // A step of the witness's type scale, in rem (gnorium-python
      // `type_scale`): a relative line-height's bounds at the font-size
      // bounds.
      if unit == "rem" { return (0.75 * fontSizes.lowerBound...3 * fontSizes.upperBound).contains(number) }
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
      let bound = lengthBound(unit: unit)
      // A margin may be negative: a note in a margin placed over the
      // frame's empty part, by its measured white (user, 2026-10-14).
      return abs(number) <= bound
        && (number >= 0 || ["text-indent", "letter-spacing", "word-spacing"].contains(property) || property.hasPrefix("margin"))
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
      + (frame.width > 0 ? ";max-inline-size:\(Length(value: frame.width, unit: "em").text)" : "") + "</rendition>"
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
    let width = setting.length("max-inline-size")
    return TEIWorkFrame(
      body: body.value, measure: measure.value, height: height.value, margin: margin.value,
      width: width?.unit == "em" ? width?.value ?? 0 : 0)
  }

  /// The work frame's declarations as tokens: its four lengths, each in its
  /// unit (`frame(in:)`), never a property a page's text takes.
  static func frameTokens(_ css: String) -> String {
    let units = ["font-size": "px", "inline-size": "em", "block-size": "em", "margin": "em", "max-inline-size": "em"]
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

  /// The renditions a TEI document, page or header declares (its work
  /// frame and type scale among them), as `TEIPage.renditions` keeps them.
  public static func declarations(of xml: String) -> [String: String] {
    declarations(in: TEIMarkup.document(xml))
  }

  // MARK: - The witness's renditions in a header

  /// The kinds of a type scale's step, in the order a header declares them,
  /// and the CSS property each sets (gnorium-python `type_scale.KINDS`,
  /// `PROPERTY`).
  static let stepKinds = ["size", "leading", "indent", "gap"]
  static let stepProperty = [
    "size": "font-size", "leading": "line-height", "indent": "text-indent", "gap": "margin-block-start",
  ]

  /// The renditions a page's or a document's header declares, as its
  /// `<tagsDecl>` holds them; "" where it declares none (gnorium-python
  /// `type_scale.renditions_of`).
  public static func renditions(of tei: String) -> String {
    guard let declared = tei.range(of: #"<tagsDecl\b[^>]*?(?:/>|>[\s\S]*?</tagsDecl>)"#, options: .regularExpression)
    else { return "" }
    return renditionElements(in: String(tei[declared])).joined()
  }

  /// Each `<rendition>` element in `markup`, as written.
  static func renditionElements(in markup: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: #"<rendition\b[^>]*>[\s\S]*?</rendition>|<rendition\b[^>]*/>"#)
    return pattern.matches(in: markup, range: NSRange(markup.startIndex..., in: markup)).compactMap {
      Range($0.range, in: markup).map { String(markup[$0]) }
    }
  }

  /// The witness's renditions over several declarations (each
  /// `renditions(of:)` a header): the first frame declared, and every step,
  /// the first declaration of an id kept—a later measurement only adds
  /// steps. As a header declares them: the frame first, then each kind's
  /// steps in id order; any other rendition is no part of them.
  /// gnorium-python `type_scale.joined(declared).xml`, the reference.
  public static func joined(_ declared: [String]) -> String {
    var frame: TEIWorkFrame?
    var steps: [(id: String, kind: String, value: Double)] = []
    for renditions in declared {
      let scale = scale(of: renditions)
      frame = frame ?? scale.frame
      for step in scale.steps where !steps.contains(where: { $0.id == step.id }) { steps.append(step) }
    }
    func order(_ step: (id: String, kind: String, value: Double)) -> (Int, Int) {
      (stepKinds.firstIndex(of: step.kind) ?? 0, Int(step.id.split(separator: "-").last ?? "") ?? 0)
    }
    let header = frame.map { frame in
      "<rendition xml:id=\"\(frameID)\" scheme=\"css\" selector=\"text\">"
        + "font-size:\(String(format: "%.2f", frame.body))px;inline-size:\(String(format: "%.2f", frame.measure))em;"
        + "block-size:\(String(format: "%.2f", frame.height))em;margin:\(String(format: "%.2f", frame.margin))em"
        + (frame.width > 0 ? ";max-inline-size:\(String(format: "%.2f", frame.width))em" : "") + "</rendition>"
    } ?? ""
    return header
      + steps.sorted { order($0) < order($1) }.map { step in
        "<rendition xml:id=\"\(step.id)\" scheme=\"css\">\(stepProperty[step.kind] ?? ""):\(Length(value: step.value, unit: "rem").text)</rendition>"
      }.joined()
  }

  /// The frame and steps `renditions` declare (gnorium-python
  /// `type_scale.parse`): the work frame (`frameID`), its body type in px
  /// and its lengths in em, and each step (`size-1`…), its value in rem;
  /// a rendition that is neither is no part of them.
  static func scale(of renditions: String) -> (frame: TEIWorkFrame?, steps: [(id: String, kind: String, value: Double)]) {
    var frame: TEIWorkFrame?
    var steps: [(id: String, kind: String, value: Double)] = []
    func length(_ value: String?, _ unit: String) -> Double? {
      guard let value, let length = Length(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
        length.unit == unit
      else { return nil }
      return length.value
    }
    for written in renditionElements(in: renditions) {
      guard let element = TEIMarkup.document(written).elements.first(where: { $0.name == "rendition" }) else { continue }
      let id = element.attribute("xml:id")
      var css: [String: String] = [:]
      for declaration in element.textContent.split(separator: ";") {
        let pair = declaration.split(separator: ":", maxSplits: 1)
        guard pair.count == 2 else { continue }
        css[pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
          pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
      }
      if id == frameID {
        if let body = length(css["font-size"], "px"), body > 0, let measure = length(css["inline-size"], "em"),
          let height = length(css["block-size"], "em"), let margin = length(css["margin"], "em")
        {
          frame = TEIWorkFrame(
            body: body, measure: measure, height: height, margin: margin, width: length(css["max-inline-size"], "em") ?? 0)
        }
        continue
      }
      guard id.range(of: #"^(size|leading|indent|gap)-[1-9][0-9]*$"#, options: .regularExpression) != nil else { continue }
      let kind = String(id.prefix { $0 != "-" })
      if let value = length(css[stepProperty[kind] ?? ""], "rem") { steps.append((id, kind, value)) }
    }
    return (frame, steps)
  }

  /// `document` with `renditions` as its header's `<tagsDecl>`, in place of
  /// any it had: in its `<encodingDesc>`, one made after its `<fileDesc>`
  /// (or a header made) where it has none (gnorium-python
  /// `type_scale.with_renditions`, for a document). No renditions, none.
  public static func declaring(_ renditions: String, in document: String) -> String {
    var text = document.replacingOccurrences(
      of: #"\s*<tagsDecl\b[^>]*?(?:/>|>[\s\S]*?</tagsDecl>)"#, with: "", options: .regularExpression)
    if let empty = text.range(of: #"\s*<encodingDesc\b[^>]*?(?:/>|>\s*</encodingDesc>)"#, options: .regularExpression) {
      text.removeSubrange(empty)
    }
    guard !renditions.isEmpty else { return text }
    let tags = "<tagsDecl>" + renditions + "</tagsDecl>"
    if let empty = text.range(of: #"<teiHeader\b[^>]*/>"#, options: .regularExpression) {
      // An empty header (which gnorium-python never writes) holds them.
      text.replaceSubrange(empty, with: "<teiHeader><encodingDesc>" + tags + "</encodingDesc></teiHeader>")
    } else if let encoding = text.range(of: #"<encodingDesc\b[^>]*>"#, options: .regularExpression) {
      text.insert(contentsOf: tags, at: encoding.upperBound)
    } else if let anchor = text.range(of: "</fileDesc>") ?? text.range(of: #"<teiHeader\b[^>]*>"#, options: .regularExpression) {
      text.insert(contentsOf: "<encodingDesc>" + tags + "</encodingDesc>", at: anchor.upperBound)
    } else if let opening = text.range(of: #"<TEI\b[^>]*>"#, options: .regularExpression) {
      text.insert(contentsOf: "<teiHeader><encodingDesc>" + tags + "</encodingDesc></teiHeader>", at: opening.upperBound)
    }
    return text
  }

  /// `document` with a page's renditions (`renditions`, as a page's header
  /// declares them) joined into its header's (`joined`): its frame where it
  /// declares none, its steps beside the document's, a step the document
  /// declares keeping its id and value—as the assembly joins its pages'
  /// (gnorium-python `concatenate_tei`). The document as it was where the
  /// page declares none, or nothing the document does not.
  public static func joining(_ renditions: String, into document: String) -> String {
    guard !renditions.isEmpty else { return document }
    let standing = self.renditions(of: document)
    let merged = joined([standing, renditions]) + kept([standing, renditions])
    return merged == standing ? document : declaring(merged, in: document)
  }

  /// The renditions of `declared` (each `renditions(of:)` a header) that
  /// are neither the work frame nor a step of the scale (`joined` leaves
  /// them out): a furniture role's placement (`fw-header`), a centering
  /// step (`align-center-1`), a display line's spacing or place, a block's
  /// indent, the tracking steps, a space's character (gnorium-python
  /// `calibration.scale`). Each as written, the first declaration of an
  /// id kept, in the order declared: a reader's document declares every
  /// rendition its pages reference, or a page's line is set without it.
  public static func kept(_ declared: [String]) -> String {
    var seen: Set<String> = []
    var out = ""
    for renditions in declared {
      for written in renditionElements(in: renditions) {
        let id = identifier(of: written)
        guard !id.isEmpty, id != frameID, !isStep(id), seen.insert(id).inserted else { continue }
        out += written
      }
    }
    return out
  }

  /// Whether `id` names a step of the type scale (`size-1`, `leading-2`…).
  static func isStep(_ id: String) -> Bool {
    id.range(of: #"^(size|leading|indent|gap)-[1-9][0-9]*$"#, options: .regularExpression) != nil
  }

  /// A written `<rendition>`'s `xml:id`; "" where it has none.
  static func identifier(of written: String) -> String {
    TEIMarkup.document(written).elements.first(where: { $0.name == "rendition" })?.attribute("xml:id") ?? ""
  }

  /// A written `<rendition>`'s declaration, compared as a header's are
  /// read (`tokens`, the frame's `frameTokens`), else as written.
  static func declaration(of written: String) -> String {
    guard let element = TEIMarkup.document(written).elements.first(where: { $0.name == "rendition" }) else { return "" }
    let text = element.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
    let read = element.attribute("xml:id") == frameID ? frameTokens(text) : tokens(text)
    return read.isEmpty ? text : read
  }

  /// A page's renditions made to agree with the document it is laid into
  /// (`TEIFacsimile.laying`): a page is encoded under the scale of that
  /// page alone (gnorium-python `base_tei`), so its `size-2` may be another
  /// size than the document's `size-2` (a halftone's header numbers the
  /// witness's steps). Where the document declares a page's id otherwise,
  /// the page's references to it name the document's rendition that
  /// declares the same, else a new id (a step the next number of its kind,
  /// any other its id and the next free number): every line keeps the
  /// setting it was encoded with. An id the document does not declare, or
  /// declares alike, is kept. The page's renditions to join (`joining`) and
  /// its fragment with its `rendition` pointers renamed.
  public static func reconciled(_ renditions: String, fragment: String, with document: String) -> (
    renditions: String, fragment: String
  ) {
    var standing: [String: String] = [:]
    var taken: Set<String> = []
    for written in renditionElements(in: document) {
      let id = identifier(of: written)
      guard !id.isEmpty else { continue }
      taken.insert(id)
      if standing[id] == nil { standing[id] = declaration(of: written) }
    }
    let own = renditionElements(in: renditions)
    for written in own { taken.insert(identifier(of: written)) }
    var renamed: [String: String] = [:]
    var out = ""
    for written in own {
      let id = identifier(of: written)
      let declared = declaration(of: written)
      guard !id.isEmpty, id != frameID, let theirs = standing[id], theirs != declared else {
        out += written
        continue
      }
      let kind = isStep(id) ? String(id.prefix { $0 != "-" }) + "-" : ""
      if let alike = standing.keys.sorted().first(where: { other in
        standing[other] == declared && (kind.isEmpty ? !isStep(other) : other.hasPrefix(kind) && isStep(other))
      }) {
        renamed[id] = alike
        continue
      }
      let stem = kind.isEmpty ? id + "-" : kind
      var number = 1
      if !kind.isEmpty {
        number = (taken.compactMap { $0.hasPrefix(kind) && isStep($0) ? Int($0.dropFirst(kind.count)) : nil }.max() ?? 0) + 1
      }
      while taken.contains(stem + String(number)) { number += 1 }
      let fresh = stem + String(number)
      taken.insert(fresh)
      renamed[id] = fresh
      standing[fresh] = declared
      out += written.replacingOccurrences(of: "xml:id=\"\(id)\"", with: "xml:id=\"\(fresh)\"")
    }
    guard !renamed.isEmpty else { return (out, fragment) }
    return (out, renamingRenditionPointers(in: fragment, renamed))
  }

  /// `markup` with each `rendition` pointer (`#id`) to an id of `renamed`
  /// naming its new id instead.
  static func renamingRenditionPointers(in markup: String, _ renamed: [String: String]) -> String {
    let pattern = try! NSRegularExpression(pattern: #"(\brendition\s*=\s*")([^"]*)(")"#)
    var text = markup
    for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
      guard let range = Range(match.range(at: 2), in: text) else { continue }
      let pointers = text[range].split(whereSeparator: \.isWhitespace).map { pointer -> String in
        guard pointer.hasPrefix("#"), let to = renamed[String(pointer.dropFirst())] else { return String(pointer) }
        return "#" + to
      }
      text.replaceSubrange(range, with: pointers.joined(separator: " "))
    }
    return text
  }

  /// `document` with `renditions` (a page's header's, as a person edited
  /// it) laid over its header's: each frame and step `renditions` declares
  /// in place of the document's, the document's others kept (`joined`,
  /// `renditions` first). The document as it was where that declares
  /// nothing new—read as the witness's renditions, not as written.
  public static func overriding(_ renditions: String, into document: String) -> String {
    guard !renditions.isEmpty else { return document }
    let standing = self.renditions(of: document)
    let merged = joined([renditions, standing]) + kept([renditions, standing])
    return merged == joined([standing]) + kept([standing]) ? document : declaring(merged, in: document)
  }

  /// A page as one TEI document, as every view of a single page shows it
  /// (user, 2026-10-14) and as an explication keeps a page (gnorium-python
  /// `tei_review.headed`): its document's renditions as the header's
  /// `<tagsDecl>` (`joined`, one per line), then the page's fragment as the
  /// body, on lines of its own. A document declaring none, no header. A
  /// document stores one header and the fragments (`PageSplice.posted`
  /// splits an edit of this back).
  public static func headedPage(_ fragment: String, renditions: String) -> String {
    let body = "<text><body>\n" + fragment + "\n</body></text>\n</TEI>"
    let open = "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\">\n"
    let declared = joined([renditions])
    guard !declared.isEmpty else { return open + body }
    let lines = renditionElements(in: declared).joined(separator: "\n")
    return open + "<teiHeader><encodingDesc><tagsDecl>\n" + lines + "\n</tagsDecl></encodingDesc></teiHeader>\n" + body
  }

  /// The body's leading, in rem (gnorium-python `type_scale`: the leading
  /// of the size step that holds the body type, 1rem): the `leading-N` of
  /// the `size-N` nearest 1rem in proportion (type is cut in proportional
  /// steps), from a document's declarations (`declarations(in:)`); nil
  /// where its scale declares no such pair.
  public static func bodyLeading(in declarations: [String: String]) -> Double? {
    var nearest: (number: Substring, distance: Double)?
    for (id, tokens) in declarations where id.hasPrefix("size-") {
      guard let size = Setting(tokens).length("font-size"), size.unit == "rem", size.value > 0 else { continue }
      let distance = abs(log(size.value))
      if nearest.map({ distance < $0.distance }) ?? true { nearest = (id.dropFirst("size-".count), distance) }
    }
    guard let number = nearest?.number, let tokens = declarations["leading-" + number],
      let leading = Setting(tokens).length("line-height"), leading.unit == "rem"
    else { return nil }
    return leading.value
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
  /// or % counts its parent's; a length in rem is the body type's
  /// (`inEm`). The parent's frame and its margin after
  /// it are its own box's, never passed on (`closing(_:within:)`). A
  /// keyword overrides the parent's of its kind (an alignment, an indent,
  /// an ink, a typeface, a step of size); any other is kept beside it.
  public static func cascade(_ parent: String, _ child: String, _ placement: Placement = .block(first: false)) -> String {
    let child = inEm(child, within: parent)
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

  /// A child's rend with its lengths in rem—the steps of its witness's
  /// type scale (gnorium-python `type_scale`), in the body type, CSS's root
  /// em: the `<text>` the work frame sets at the body type—as em of its
  /// own font, as the cascade counts them: its font-size over its parent's
  /// computed font (`fontSize(of:)`), every other length over its own. A
  /// step means one size wherever it is referenced.
  static func inEm(_ rend: String, within parent: String) -> String {
    var own = Setting(rend)
    let rem = own.entries.compactMap { entry -> String? in
      guard entry.key.hasPrefix("css:") else { return nil }
      let property = String(entry.key.dropFirst(4))
      return own.length(property)?.unit == "rem" ? property : nil
    }
    guard !rem.isEmpty else { return rend }
    let around = fontSize(of: parent) ?? 1
    if let size = own.length("font-size"), size.unit == "rem" {
      own.set("font-size", Length(value: size.value / around, unit: "em"))
    }
    let font = own.relativeFont.map { around * $0 } ?? own.length("font-size").flatMap(bodyEm) ?? around
    for property in rem where property != "font-size" {
      guard let length = own.length(property), font != 0 else { continue }
      own.set(property, Length(value: length.value / font, unit: "em"))
    }
    return own.rend
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
    // Its alignment too: a framed block set centered (an owner's pasted
    // bookplate regularized to the head's middle, user, 2026-10-14) is a
    // box centered, not only its lines.
    for entry in setting.entries where entry.key == "align(" { frame.set(entry.key, entry.token) }
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

  /// Whether a rend draws a frame around its block: a printed rule
  /// (`border-style`) or a ground of its own (`background-color`).
  public static func frames(_ rend: String) -> Bool {
    let setting = Setting(rend)
    if setting.value("background-color") != nil { return true }
    guard let style = setting.value("border-style") else { return false }
    return style != "none"
  }

  /// Whether a value is a color as "#rrggbb": six hexadecimal digits.
  static func isHexColor(_ value: String) -> Bool {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count == 7, scalars[0] == "#" else { return false }
    return scalars.dropFirst().allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0) }
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
