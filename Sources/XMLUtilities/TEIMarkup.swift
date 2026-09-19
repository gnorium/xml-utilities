#if SERVER
  import Foundation

  /// A tolerant fragment reader. A facsimile boundary can split an outer div,
  /// so an XML document parser would reject otherwise usable page fragments.
  /// Only text and attributes are retained; declarations never load resources.
  enum TEIMarkup {
    enum Node {
      case text(String)
      case element(Element)
    }

    final class Element {
      let name: String
      let attributes: [String: String]
      var children: [Node] = []

      init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
      }

      func attribute(_ name: String) -> String { attributes[name] ?? "" }

      var textContent: String {
        children.map { node in
          switch node {
          case .text(let text): return text
          case .element(let child): return child.textContent
          }
        }.joined()
      }

      var elements: [Element] {
        children.compactMap {
          if case .element(let element) = $0 { return element }
          return nil
        }
      }
    }

    static func parse(_ markup: String) -> [Node] {
      let root = Element(name: "root")
      var stack = [root]
      let tokens = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<(?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+"#)
      let attributes = try! NSRegularExpression(pattern: #"([^\s=<>/]+)\s*=\s*("[^"]*"|'[^']*')"#)
      let emptyElements: Set<String> = ["pb", "cb", "lb", "gap", "milestone", "graphic"]
      for match in tokens.matches(in: markup, range: NSRange(markup.startIndex..., in: markup)) {
        guard let range = Range(match.range, in: markup) else { continue }
        let token = String(markup[range])
        if token.hasPrefix("<![CDATA[") {
          stack.last?.children.append(.text(String(token.dropFirst(9).dropLast(3))))
        } else if !token.hasPrefix("<") {
          stack.last?.children.append(.text(XMLFormatter.decodingEntities(token)))
        } else if token.hasPrefix("<!") || token.hasPrefix("<?") {
          continue
        } else {
          let closing = token.hasPrefix("</")
          let raw = token.dropFirst(closing ? 2 : 1).dropLast()
          let qualifiedName = raw.prefix { !$0.isWhitespace && $0 != "/" }
          let name = String(qualifiedName.split(separator: ":").last ?? qualifiedName)
          guard !name.isEmpty else { continue }
          if closing {
            if let index = stack.lastIndex(where: { $0.name == name }), index > 0 {
              stack.removeSubrange(index...)
            }
            continue
          }
          var values: [String: String] = [:]
          for attribute in attributes.matches(
            in: token, range: NSRange(token.startIndex..., in: token))
          {
            guard let key = Range(attribute.range(at: 1), in: token),
              let value = Range(attribute.range(at: 2), in: token)
            else { continue }
            values[String(token[key])] = XMLFormatter.decodingEntities(
              String(token[value].dropFirst().dropLast()))
          }
          let element = Element(name: name, attributes: values)
          stack.last?.children.append(.element(element))
          if !token.hasSuffix("/>") && !emptyElements.contains(name) { stack.append(element) }
        }
      }
      return root.children
    }
  }
#endif
