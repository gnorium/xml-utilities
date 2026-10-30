#if SERVER
  import Foundation

  /// A figure's drawing (`TEILine.Kind.figure`'s `graphic`), read from the
  /// SVG it is served as (gnorium-python `calibration.figure_trace`: an
  /// `<svg>` of `<path>`s, one per ink, each filled `currentColor`), so a
  /// server can draw it into the page itself and the figure paints in its
  /// ink from the first frame (user, 2026-10-31: an `<img>` of it paints
  /// `currentColor` black until the client inlines it).
  ///
  /// Only what a drawing is is read: the SVG's size and view box, and each
  /// path's outline, fill, fill rule and ink class. Anything else the text
  /// holds (another element, a script, a handler) is never carried over,
  /// and the drawing is rebuilt from these values, escaped as any
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
