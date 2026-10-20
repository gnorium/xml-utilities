#if SERVER
  import Foundation

  /// A multi-word unit of a page (user, 2026-09-29): a `<phr>` (an idiom, a
  /// phrase, …) and the words in it, as a quote's anchor counts them,
  /// so the words a reader opens can open the phrase they are in.
  public struct TEIPhrase: Sendable, Equatable {
    /// Its words in reading order, each by its place on the page.
    public let words: [TEIWordPlace]
    /// Its class (`@class`: "idiom", "phrase", …); "" where none is written.
    public let wordClass: String
    /// Its dictionary form (`@lemma`); "" where none is written.
    public let lemma: String
    /// Its words as written, one space between them.
    public let surface: String
    /// Its language, as the nearest `xml:lang` over it names it; "" where
    /// none does.
    public let language: String
    /// Its `xml:id`: what its sentiment assignment names it by; "" where it
    /// has none.
    public let id: String

    public init(
      words: [TEIWordPlace], wordClass: String, lemma: String, surface: String, language: String, id: String = ""
    ) {
      self.id = id
      self.words = words
      self.wordClass = wordClass
      self.lemma = lemma
      self.surface = surface
      self.language = language
    }

    public func contains(_ place: TEIWordPlace) -> Bool { words.contains(place) }
  }

  extension TEIRenderer {
    /// A page's phrases, each with the words it holds (a `<w>` or an `<m>`
    /// inside it, its first part on this page); a phrase none of whose words
    /// is on the page is left out. Nested phrases are each listed.
    public static func phrases(of page: TEIPage) -> [TEIPhrase] {
      let root = TEIMarkup.document(TEIProjection.normalized(page.markup))
      let units = TEIProjection(root).units
      var found: [TEIPhrase] = []
      func starts(under element: TEIMarkup.Element) -> [Int] {
        element.elements.flatMap { child -> [Int] in
          if child.name == "w" || child.name == "m", let start = child.projectedStart { return [start] }
          return starts(under: child)
        }
      }
      func visit(_ element: TEIMarkup.Element, languages: [String]) {
        let language = element.attribute("xml:lang")
        let languages = language.isEmpty ? languages : languages + [language]
        if element.name == "phr" {
          let starts = Set(starts(under: element))
          let members = units.filter { starts.contains($0.ranges[0].lowerBound) }
          if !members.isEmpty {
            found.append(
              TEIPhrase(
                words: members.map { .init(line: $0.line, word: $0.number) },
                wordClass: element.attribute("class"), lemma: element.attribute("lemma"),
                surface: members.map(\.surface).joined(separator: " "), language: languages.last ?? "",
                id: element.attribute("xml:id")))
          }
        }
        for child in element.elements { visit(child, languages: languages) }
      }
      visit(root, languages: [])
      return found
    }

    /// The smallest phrase of a page holding the word at `place`; nil where
    /// none does.
    public static func phrase(of page: TEIPage, at place: TEIWordPlace) -> TEIPhrase? {
      phrases(of: page).filter { $0.contains(place) }.min { $0.words.count < $1.words.count }
    }
  }
#endif
