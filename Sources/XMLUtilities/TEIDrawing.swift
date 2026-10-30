#if SERVER
  import Foundation

  /// A figure's drawing (`TEILine.Kind.figure`'s `graphic`), read from the
  /// SVG it is filed as (gnorium-python `calibration.figure_trace`: an
  /// `<svg>` of `<path>`s, one per ink, each filled `currentColor`) and
  /// served as the reader references it (`referenced`): the reader draws
  /// it with `<use href="…#figure">`, so it paints in the page's ink from
  /// the first frame, stays one cached request, and keeps the page small
  /// (user, 2026-10-31: an `<img>` of it painted `currentColor` black until
  /// the client inlined it, and inlining it put a cover's 600 KB of paths
  /// in every load).
  ///
  /// Only what a drawing is is read: the SVG's size and view box, and each
  /// path's outline, fill, fill rule and ink class. Anything else the text
  /// holds (another element, a script, a handler) is never carried over,
  /// and the drawing is written again from these values, escaped as any
  /// attribute is.
  public struct TEIDrawing: Sendable, Equatable {
    public struct Path: Sendable, Equatable {
      /// Its ink's class (`ink-red`), "" for the print layer.
      public let ink: String
      public let fill: String
      public let fillRule: String
      public let d: String

      public init(ink: String, fill: String, fillRule: String, d: String) {
        self.ink = ink
        self.fill = fill
        self.fillRule = fillRule
        self.d = d
      }
    }

    public let width: String
    public let height: String
    public let viewBox: String
    public let paths: [Path]

    /// The id of the drawing in the file it is served as (`referenced`),
    /// which the reader's `<use>` names.
    public static let fragment = "figure"

    /// The custom property a reader sets an ink's color in (`--tei-ink-red`
    /// for `ink-red`): a page's style never reaches into a drawing used
    /// from another file, but an inherited property does.
    public static func inkProperty(_ ink: String) -> String { "--tei-\(ink)" }

    /// The file the reader references it in: a `<symbol>` (`fragment`) of
    /// its paths at its view box, stretched to the box it is used in as the
    /// figure's image filled its setting, used once so the file shows alone
    /// too. Its print is `currentColor`, the reader's `<use>`'s; another
    /// ink its class and its reader's property (`inkProperty`), else the
    /// print's color.
    public var referenced: String {
      func attribute(_ name: String, _ value: String) -> String {
        value.isEmpty ? "" : " \(name)=\"\(XMLFormatter.escapingAttribute(value))\""
      }
      let paths = paths.map { path in
        let ink = path.ink.isEmpty ? "" : attribute("class", path.ink) + attribute("style", "fill:var(\(Self.inkProperty(path.ink)),currentColor)")
        return "<path" + ink + attribute("fill", path.fill) + attribute("fill-rule", path.fillRule) + attribute("d", path.d) + "/>"
      }.joined()
      return "<svg xmlns=\"http://www.w3.org/2000/svg\"" + attribute("width", width) + attribute("height", height)
        + attribute("viewBox", viewBox) + "><symbol id=\"\(Self.fragment)\"" + attribute("viewBox", viewBox)
        + " preserveAspectRatio=\"none\">" + paths + "</symbol><use href=\"#\(Self.fragment)\" width=\"100%\" height=\"100%\"/></svg>"
    }

    /// The drawing `svg` is; nil where it is no `<svg>` or draws no path.
    public init?(svg: String) {
      let root = TEIMarkup.document(svg)
      guard let element = root.elements.first(where: { $0.name == "svg" }) else { return nil }
      var paths: [Path] = []
      func collect(_ parent: TEIMarkup.Element) {
        for child in parent.elements {
          if child.name == "path" {
            let d = child.attribute("d")
            guard !d.isEmpty else { continue }
            let ink = child.attribute("class").split(separator: " ").first { $0.hasPrefix("ink-") }.map(String.init) ?? ""
            paths.append(.init(ink: ink, fill: child.attribute("fill"), fillRule: child.attribute("fill-rule"), d: d))
          } else if child.name == "g" {
            collect(child)
          }
        }
      }
      collect(element)
      guard !paths.isEmpty else { return nil }
      width = element.attribute("width")
      height = element.attribute("height")
      viewBox = element.attribute("viewBox")
      self.paths = paths
    }
  }
#endif
