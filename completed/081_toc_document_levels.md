# Plan: Restructure Markdown Files for Document-Level TOC

## Motivation
Currently, when generating the joint documentation (HTML/PDF), the contents of all `.md` files are concatenated. Because all individual `.md` files use top-level headings (`# Heading`), the resulting document has over 80 top-level sections in the Table of Contents, making it difficult to navigate. Instead of adding complex parsing logic to the Perl preprocessor, we will perform a one-time restructuring of the 12 Markdown files to ensure they each act as a single "Chapter" with exactly one top-level heading.

## Design Choices
1. **No Script Modifications**: We will completely avoid changing the Perl preprocessor in `tools/generate-docs` and `tools/generate-documentation`. This prevents fragility and regex parsing bugs.
2. **One-Time Markdown Refactoring**: For each of the 12 included Markdown files (e.g., `GettingStarted.md`, `Installing.md`):
   - A single top-level heading will be added at the top of the file, immediately after the existing `<a id="..."></a>` anchor. The heading will match the document's name (e.g., `# Getting Started`).
   - Every existing heading in the document will be demoted by one level (e.g., `# Introduction` becomes `## Introduction`, `## Details` becomes `### Details`).
3. **Code Block Safety**: The header demotion process will be performed carefully (using a temporary Python script during implementation) to ensure `#` characters inside Markdown code blocks (` ``` `) are strictly ignored and left untouched.
4. **Anchor Links**: Existing cross-document anchor links like `[text](GettingStarted.md#configuration)` will continue to work perfectly, because Pandoc/GitHub generates HTML anchor IDs based on the header text, regardless of its heading level.
5. **Numbering**: As before, Pandoc's `--number-sections` will handle the top-level numbering automatically (e.g., `1. Getting Started`, `1.1. Introduction`), avoiding hardcoded Roman numerals that would conflict with automated numbering.

## Benefits
- **Simplicity**: No changes required to the build system; no new dependencies.
- **Robustness**: No risk of the Perl script breaking on edge cases in the future.
- **Improved GitHub Reading**: Reading the individual Markdown files directly on GitHub will be much clearer, as each file will now have a proper "Chapter" title and hierarchical structure.

## Steps
1. Write a temporary Python script in the `tasks/` directory to safely demote all headings in `docs/*.md` (ignoring code blocks).
2. Use the script to process the 12 Markdown files listed in `docs/index.md`.
3. Manually insert the top-level Chapter headings (e.g., `# Getting Started`) at the top of each processed file, just below their `<a id="..."></a>` tags.
4. Run `tools/generate-docs` locally to verify the output HTML and TOC structure.
5. Run `tools/generate-documentation` locally to verify the HTML/PDF output.
6. Verify that internal anchor links still work correctly in the generated HTML.
7. Remove the temporary Python script.