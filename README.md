# XMLUtilities, as used in [gnorium.com](https://gnorium.com)

A Swift package for reading XML documents — TEI transcriptions in particular — as the pages and lines a reader sees.

## Overview

XMLUtilities is the counterpart of [markdown-utilities](https://github.com/gnorium/markdown-utilities). Where `MarkdownRenderer` turns a source format into an HTML fragment, `TEIRenderer` turns a TEI document into the pages a view draws: a facsimile edition is read one opening at a time, and no HTML fragment can carry that structure.

### Features
- **`TEIRenderer`**: splits a document into pages at the page breaks that carry a facsimile, and reads each page as typed lines (text, heading, speaker, stage direction, page-turn mark).
- **`XMLFormatter`**: XML as syntax with no knowledge of any vocabulary — pretty-printing, single-attribute reads, entity decoding, body extraction.
- **Line breaks are kept**: a diplomatic transcript says where the compositor broke the line, so `<lb/>` ends a line rather than collapsing into a space.

### Two kinds of page break

A source that photographs openings writes two kinds of `<pb>`:

```xml
<pb n="A1 verso – A2 recto" facs="https://…/iiif/8/full/max/0/default.jpg"/>
<pb n="A1v"/>
```

The first is a facsimile — one image, one page. The second is a side of the leaf, and becomes a mark on the page it falls in. Counting both makes a 64-image quarto read as 162 pages.

## Installation

### Swift Package Manager

Add XMLUtilities to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gnorium/xml-utilities.git", branch: "main")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "XMLUtilities", package: "xml-utilities")
    ]
)
```

## Requirements

- Swift 6.2+

## Usage

```swift
import XMLUtilities

for page in TEIRenderer.pages(in: tei) {
    print(page.label)          // "A1 verso – A2 recto"
    print(page.facsimileURL)   // the image it was transcribed from
    for line in page.lines where line.kind == .speaker {
        print(line.text)
    }
}

let readable = XMLFormatter.prettified(page.markup)
```

Everything is `#if SERVER`; the module compiles to an empty one under Embedded Swift for WASI, so a package shared by server and client can depend on it unconditionally.

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Packages

- [admin-core](https://github.com/gnorium/admin-core) - Core admin functionalities for web applications
- [artifact-core](https://github.com/gnorium/artifact-core) - IIIF Presentation API v3 types + deep zoom viewer
- [design-tokens](https://github.com/gnorium/design-tokens) - Universal design tokens based on Apple HIG
- [diff-engine](https://github.com/gnorium/diff-engine) - Platform-agnostic character-level diff engine
- [embedded-swift-utilities](https://github.com/gnorium/embedded-swift-utilities) - Utility functions for Embedded Swift environments
- [markdown-utilities](https://github.com/gnorium/markdown-utilities) - Markdown to HTML with media attribution syntax
- [tex-utilities](https://github.com/gnorium/tex-utilities) - TeX formula rendering with locally served KaTeX
- [web-apis](https://github.com/gnorium/web-apis) - Web API implementations for Swift WebAssembly
- [web-builders](https://github.com/gnorium/web-builders) - HTML, CSS, JS, and SVG DSL builders
- [web-components](https://github.com/gnorium/web-components) - Reusable UI components for web applications
- [web-formats](https://github.com/gnorium/web-formats) - Structured data format builders
- [web-security](https://github.com/gnorium/web-security) - Portable security utilities for web applications
- [web-tests](https://github.com/gnorium/web-tests) - Swift browser testing across Chrome and Safari
- [web-types](https://github.com/gnorium/web-types) - Shared web types for web applications
