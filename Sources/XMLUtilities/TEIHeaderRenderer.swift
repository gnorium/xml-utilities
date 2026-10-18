#if SERVER
  import Foundation

  /// A table in a rendered header: its column heads and its rows, every
  /// cell a string (an unknown value is already "—").
  public struct TEIHeaderTable: Sendable, Equatable {
    /// What the table is of, where the header says ("Size"); "" for none.
    public let title: String
    public let columns: [String]
    public let rows: [[String]]

    public init(title: String = "", columns: [String], rows: [[String]]) {
      self.title = title
      self.columns = columns
      self.rows = rows
    }
  }

  /// One labelled entry of a rendered header: a label and what it holds—a
  /// value, paragraphs, tables, and nested entries beneath it. An entry
  /// that holds none of them has the value "—".
  public struct TEIHeaderEntry: Sendable, Equatable {
    public let label: String
    public let value: String
    public let paragraphs: [String]
    public let tables: [TEIHeaderTable]
    public let entries: [TEIHeaderEntry]

    public init(
      label: String, value: String = "", paragraphs: [String] = [], tables: [TEIHeaderTable] = [],
      entries: [TEIHeaderEntry] = []
    ) {
      self.label = label
      self.paragraphs = paragraphs
      self.tables = tables
      self.entries = entries
      self.value =
        value.isEmpty && paragraphs.isEmpty && tables.isEmpty && entries.isEmpty
        ? TEIHeaderRenderer.unknown : value
    }
  }

  /// A `<teiHeader>` as nested labelled entries, read from official TEI
  /// elements alone (user, 2026-10-18): what a header declares is shown
  /// where TEI puts it, whatever it describes—a witness's type scale or a
  /// concordance's selection—so one renderer serves both sides. The wording
  /// is TEI's (title, extent, sampling, languages, revisions), never the
  /// caller's.
  ///
  /// | Element | Entry |
  /// |---|---|
  /// | `fileDesc/titleStmt` `title`, `author`, `editor`, `respStmt` | Title (always present, "—" if none), Author, Editor, one entry per `resp` |
  /// | `fileDesc/extent/measure` | Extent, one entry per measure: unit (and type), quantity or `atLeast`–`atMost` |
  /// | `fileDesc/publicationStmt` `publisher`, `idno` | Publisher, one entry per identifier |
  /// | `fileDesc/sourceDesc/bibl` | Source |
  /// | `encodingDesc/samplingDecl` | Sampling: its `p` as paragraphs, its `table`s as tables |
  /// | `encodingDesc/editorialDecl/*` | Editorial practice: one entry per child (normalization, segmentation, …) |
  /// | `encodingDesc/tagsDecl/rendition` | Scale: the `text-block` frame's declarations, then one table per axis (`size-1`… grouped by id prefix: Step, Em, and Count where a rendition has `@n`) |
  /// | `encodingDesc/tagsDecl/namespace/tagUsage` | Tag usage: Element, Occurrences |
  /// | `encodingDesc/appInfo/application` | Tools: Application (`@ident`), Version, Label |
  /// | `profileDesc/langUsage/language` | Languages: Language, Usage (`@usage`, a percent) |
  /// | `revisionDesc/change` | Revisions: When, Who, Change |
  public enum TEIHeaderRenderer {
    /// The shown value of one that is not known.
    public static let unknown = "—"

    /// The axes a scale's tables come in first, in this order; any other
    /// step prefix follows, in the order the header declares it.
    static let axes = ["size", "leading", "indent", "gap", "tracking"]

    /// The entries of the `<teiHeader>` in `tei`—a header fragment or a
    /// whole document. Where it has no header, the entries of an empty one.
    public static func entries(of tei: String) -> [TEIHeaderEntry] {
      let root = TEIMarkup.document(tei)
      let header = first("teiHeader", in: root) ?? TEIMarkup.Element(name: "teiHeader")
      var entries: [TEIHeaderEntry] = []
      let fileDesc = first("fileDesc", in: header)
      let titleStmt = fileDesc.flatMap { first("titleStmt", in: $0) }

      entries.append(
        TEIHeaderEntry(label: "Title", value: joined(texts("title", in: titleStmt))))
      for (name, label) in [("author", "Author"), ("editor", "Editor")] {
        let values = texts(name, in: titleStmt)
        if !values.isEmpty { entries.append(TEIHeaderEntry(label: label, value: joined(values))) }
      }
      for statement in all("respStmt", in: titleStmt) {
        let who = joined(texts("name", in: statement) + texts("persName", in: statement))
        let what = joined(texts("resp", in: statement))
        entries.append(TEIHeaderEntry(label: what.isEmpty ? "Responsibility" : capitalized(what), value: who))
      }

      if let extent = fileDesc.flatMap({ first("extent", in: $0) }) {
        let measures = all("measure", in: extent).map { measure in
          TEIHeaderEntry(label: measureLabel(measure), value: quantity(of: measure))
        }
        let text = flat(extent, excluding: ["measure"])
        entries.append(TEIHeaderEntry(label: "Extent", value: text, entries: measures))
      }

      if let publication = fileDesc.flatMap({ first("publicationStmt", in: $0) }) {
        let publishers = texts("publisher", in: publication)
        if !publishers.isEmpty { entries.append(TEIHeaderEntry(label: "Publisher", value: joined(publishers))) }
        for identifier in all("idno", in: publication) {
          let type = identifier.attribute("type")
          entries.append(
            TEIHeaderEntry(label: type.isEmpty ? "Identifier" : "Identifier (\(type))", value: flat(identifier)))
        }
      }

      if let source = fileDesc.flatMap({ first("sourceDesc", in: $0) }) {
        let values = all("bibl", in: source).map { flat($0) }.filter { !$0.isEmpty }
        entries.append(TEIHeaderEntry(label: "Source", value: joined(values, separator: "; ")))
      }

      let encoding = first("encodingDesc", in: header)
      if let sampling = encoding.flatMap({ first("samplingDecl", in: $0) }) {
        var paragraphs: [String] = []
        var tables: [TEIHeaderTable] = []
        for child in sampling.elements {
          if child.name == "p" {
            let text = flat(child, excluding: ["table"])
            if !text.isEmpty { paragraphs.append(text) }
            tables += all("table", in: child).map(table(of:))
          } else if child.name == "table" {
            tables.append(table(of: child))
          }
        }
        if paragraphs.isEmpty && tables.isEmpty, case let text = flat(sampling), !text.isEmpty { paragraphs = [text] }
        entries.append(TEIHeaderEntry(label: "Sampling", paragraphs: paragraphs, tables: tables))
      }
      if let editorial = encoding.flatMap({ first("editorialDecl", in: $0) }) {
        let practices = editorial.elements.map { practice in
          TEIHeaderEntry(label: capitalized(words(practice.name)), paragraphs: [flat(practice)].filter { !$0.isEmpty })
        }
        entries.append(TEIHeaderEntry(label: "Editorial practice", entries: practices))
      }

      if let tags = encoding.flatMap({ first("tagsDecl", in: $0) }) {
        if let scale = scale(in: tags) { entries.append(scale) }
        let usages = all("tagUsage", in: tags)
        if !usages.isEmpty {
          let rows = usages.map { [orUnknown($0.attribute("gi")), orUnknown($0.attribute("occurs"))] }
          entries.append(
            TEIHeaderEntry(label: "Tag usage", tables: [TEIHeaderTable(columns: ["Element", "Occurrences"], rows: rows)]))
        }
      }

      if let info = encoding.flatMap({ first("appInfo", in: $0) }) {
        let rows = all("application", in: info).map { application in
          [
            orUnknown(application.attribute("ident")), orUnknown(application.attribute("version")),
            orUnknown(joined(texts("label", in: application))),
          ]
        }
        entries.append(
          TEIHeaderEntry(label: "Tools", tables: [TEIHeaderTable(columns: ["Application", "Version", "Label"], rows: rows)]))
      }

      if let languages = first("langUsage", in: first("profileDesc", in: header) ?? header) {
        let rows = all("language", in: languages).map { language -> [String] in
          let ident = language.attribute("ident"), name = flat(language)
          let usage = language.attribute("usage")
          return [
            name.isEmpty ? orUnknown(ident) : (ident.isEmpty ? name : "\(name) (\(ident))"),
            usage.isEmpty ? unknown : usage + "%",
          ]
        }
        entries.append(
          TEIHeaderEntry(label: "Languages", tables: [TEIHeaderTable(columns: ["Language", "Usage"], rows: rows)]))
      }

      if let revisions = first("revisionDesc", in: header) {
        let rows = all("change", in: revisions).map { change in
          [
            orUnknown(change.attribute("when")), orUnknown(change.attribute("who").replacingOccurrences(of: "#", with: "")),
            orUnknown(flat(change)),
          ]
        }
        entries.append(
          TEIHeaderEntry(label: "Revisions", tables: [TEIHeaderTable(columns: ["When", "Who", "Change"], rows: rows)]))
      }
      return entries
    }

    // MARK: - Scale

    /// The renditions a `<tagsDecl>` declares: the work frame's own
    /// declarations, then a table per axis. Nil where it declares none.
    static func scale(in tags: TEIMarkup.Element) -> TEIHeaderEntry? {
      let renditions = all("rendition", in: tags).filter { ["", "css"].contains($0.attribute("scheme")) }
      guard !renditions.isEmpty else { return nil }
      var frame: [String] = []
      var groups: [(axis: String, steps: [(id: String, value: String, count: String)])] = []
      for rendition in renditions {
        let id = rendition.attribute("xml:id")
        let declarations = declared(rendition.textContent)
        if id == TEIRendition.frameID {
          frame = declarations.map { "\(words($0.property)): \($0.value)" }
          continue
        }
        guard let dash = id.lastIndex(of: "-"), Int(id[id.index(after: dash)...]) != nil else { continue }
        let axis = String(id[..<dash])
        let value = declarations.first.map { em($0.value) } ?? unknown
        let count = rendition.attribute("n")
        if let index = groups.firstIndex(where: { $0.axis == axis }) {
          groups[index].steps.append((id, value, count))
        } else {
          groups.append((axis, [(id, value, count)]))
        }
      }
      groups.sort { rank($0.axis) < rank($1.axis) }
      let tables = groups.map { group -> TEIHeaderTable in
        let counted = group.steps.contains { !$0.count.isEmpty }
        return TEIHeaderTable(
          title: capitalized(group.axis), columns: counted ? ["Step", "Em", "Count"] : ["Step", "Em"],
          rows: group.steps.map { counted ? [$0.id, $0.value, orUnknown($0.count)] : [$0.id, $0.value] })
      }
      var entries: [TEIHeaderEntry] = []
      if !frame.isEmpty { entries.append(TEIHeaderEntry(label: "Frame", paragraphs: frame)) }
      return TEIHeaderEntry(label: "Scale", tables: tables, entries: entries)
    }

    private static func rank(_ axis: String) -> Int { axes.firstIndex(of: axis) ?? axes.count }

    /// A rendition's CSS declarations, in order, each property and value.
    private static func declared(_ css: String) -> [(property: String, value: String)] {
      css.split(separator: ";").compactMap { declaration in
        let pair = declaration.split(separator: ":", maxSplits: 1)
        guard pair.count == 2 else { return nil }
        return (
          pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }
    }

    /// A step's length in em: the number alone where it is in rem or em (a
    /// header's rem is the work's em), any other unit as written.
    private static func em(_ value: String) -> String {
      guard let length = TEIRendition.Length(value.lowercased()) else { return orUnknown(value) }
      return length.unit == "rem" || length.unit == "em" ? TEIRendition.Length(value: length.value, unit: "").text : length.text
    }

    // MARK: - Elements

    private static func measureLabel(_ measure: TEIMarkup.Element) -> String {
      let unit = measure.attribute("unit"), type = measure.attribute("type")
      let label = [unit, type].filter { !$0.isEmpty }.joined(separator: " ")
      return label.isEmpty ? "Measure" : capitalized(label)
    }

    private static func quantity(of measure: TEIMarkup.Element) -> String {
      let exact = measure.attribute("quantity")
      if !exact.isEmpty { return exact }
      let low = measure.attribute("atLeast"), high = measure.attribute("atMost")
      if !low.isEmpty || !high.isEmpty { return "\(orUnknown(low))–\(orUnknown(high))" }
      return flat(measure)
    }

    /// A TEI table: its `<row role="label">` heads the columns, the rest
    /// are rows; without one the columns are numbered.
    private static func table(of element: TEIMarkup.Element) -> TEIHeaderTable {
      var columns: [String] = []
      var rows: [[String]] = []
      for row in all("row", in: element) {
        let cells = row.elements.filter { $0.name == "cell" }.map { orUnknown(flat($0)) }
        if columns.isEmpty && row.attribute("role") == "label" { columns = cells } else { rows.append(cells) }
      }
      if columns.isEmpty { columns = (0..<(rows.map(\.count).max() ?? 0)).map { String($0 + 1) } }
      let title = flat(first("head", in: element) ?? TEIMarkup.Element(name: "head"))
      return TEIHeaderTable(title: title.isEmpty ? capitalized(element.attribute("rend")) : title, columns: columns, rows: rows)
    }

    // MARK: - Reading

    private static func first(_ name: String, in element: TEIMarkup.Element?) -> TEIMarkup.Element? {
      guard let element else { return nil }
      for child in element.elements {
        if child.name == name { return child }
        if let found = first(name, in: child) { return found }
      }
      return nil
    }

    private static func all(_ name: String, in element: TEIMarkup.Element?) -> [TEIMarkup.Element] {
      guard let element else { return [] }
      var found: [TEIMarkup.Element] = []
      for child in element.elements {
        if child.name == name { found.append(child) }
        found += all(name, in: child)
      }
      return found
    }

    private static func texts(_ name: String, in element: TEIMarkup.Element?) -> [String] {
      all(name, in: element).map { flat($0) }.filter { !$0.isEmpty }
    }

    /// An element's text with its whitespace collapsed; with `excluding`,
    /// without the text of those descendants.
    private static func flat(_ element: TEIMarkup.Element, excluding: Set<String> = []) -> String {
      func text(_ node: TEIMarkup.Element) -> String {
        node.children.map { child -> String in
          switch child {
          case .text(let text): return text
          case .element(let inner): return excluding.contains(inner.name) ? " " : text(inner)
          }
        }.joined()
      }
      return text(element).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func joined(_ values: [String], separator: String = ", ") -> String {
      values.joined(separator: separator)
    }

    private static func orUnknown(_ value: String) -> String { value.isEmpty ? unknown : value }

    /// "samplingDecl"-style names and hyphenated ids as words: "sampling decl".
    private static func words(_ name: String) -> String {
      var out = ""
      for character in name {
        if character == "-" || character == "_" {
          out += " "
        } else if character.isUppercase, !out.isEmpty {
          out += " " + character.lowercased()
        } else {
          out.append(character)
        }
      }
      return capitalized(out)
    }

    private static func capitalized(_ text: String) -> String {
      guard let first = text.first else { return text }
      return first.uppercased() + text.dropFirst()
    }
  }
#endif
