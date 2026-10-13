# Repository guidance

This directory is its own Git repository. The parent Gnorium workspace is not a repository; run Git commands here and inspect sibling repositories separately.

- Preserve unrelated working changes. When renaming an internal API, update callers in sibling packages rather than leave obsolete aliases.
- Run focused checks for the changed behavior. Do not run full server/browser suites unless requested.
- Keep build caches and `.build` directories. Diagnose build/toolchain errors before rebuilding; do not wipe caches to troubleshoot.
- Batch related changes before building. Deployment requires an explicit user request; a local build or server restart is not deployment.
- If committing authorized work, omit attribution trailers and push normally after the commit; never force-push.

## TEI fidelity and layout

- Preserve the exact source reading and whitespace evidence. Linguistic alternatives and annotations go beside the reading, never replace it.
- Use standard TEI structure: physical `pb`, `cb`, `lb`, supported rendition settings, and explicit vertical spaces. Text coordinates, text bounding boxes, and absolute positioning are excluded; existing figure/initial zones remain supported.
- A `pb` label identifies the surface and is not synthetic page text. Display numbers actually printed on the page through `fw type="pageNum"`.
- Contents pages use `table type="contents"`, one row per entry, separate title/reference cells, indentation inside title cells, and continuation lines within their entry.
- Left alignment is the default; justify only explicit `align(justify)` settings. Some drift from the scan is acceptable.

## Renderer ownership

The web view and model visual validator share this TEI rendering model. Preserve standard column, table, paragraph, and page structure; do not flatten tabular entries into prose. Keep original markup separate from its rendering and encoded alternatives.
