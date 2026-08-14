# Plan: Convert AsciiDoc to Markdown (Task 74)

## Motivation

Following os-autoinst commit e28007f5, openQA should also convert its documentation from AsciiDoc (`.asciidoc`) to Markdown (`.md`) to standardise the format, relying on well-established tools like `pandoc`.

## Steps

1.  **File Conversion**:
    - Find all `*.asciidoc` files in the repository (e.g., in `docs/`, `container/`, and the root `README.asciidoc`).
    - Convert each file to Markdown (`.md`) using `pandoc -f asciidoc -t gfm --wrap=preserve` (or similar, depending on the required formatting and layout).
    - Delete the original `.asciidoc` files using `git rm`.

2.  **Fixup Advanced Features (Inclusions & Cross-References)**:
    - **Cross-references**: AsciiDoc uses `<<File.asciidoc#_anchor,Text>>`. Convert these manually or via script to standard Markdown links `[Text](File.md#anchor)`.
    - **Inclusions**: `docs/index.asciidoc` and `tools/generate-documentation-genapi` use `include::...[]`. Pandoc does not natively support this for Markdown out of the box without extensions/filters. We need to either implement a simple preprocessor (e.g., in `tools/generate-docs`), use a Pandoc Lua filter, or concatenate files before passing to Pandoc.

3.  **Update Tooling Scripts**:
    - `tools/generate-docs`: Switch from calling `asciidoctor` to calling `pandoc`. Handle `index.md` appropriately.
    - `tools/generate-documentation`: Remove checks for `asciidoctor` and `asciidoctor-pdf`. Replace with checks for `pandoc` (and potentially a PDF engine like `wkhtmltopdf` or `tectonic` if PDF generation is still required).
    - `tools/generate-documentation-genapi`: Switch from `Pod::AsciiDoctor` to `Pod::Markdown`.

4.  **Update Configuration & Build Files**:
    - `Makefile`: Update `generate-docs` target and any hardcoded `docs/Contributing.asciidoc` mentions.
    - `.github/checklist.yml`: Update path `docs/*.asciidoc` to `docs/*.md`.
    - `dist/rpm/openQA.spec`: Change `%doc README.asciidoc` to `%doc README.md`.
    - `docs/Gemfile` and `docs/Gemfile.lock`: Remove `asciidoctor` dependency. Add new dependencies if any ruby tool is used for markdown generation.
    - `AGENTS.md`: Update documentation policy from AsciiDoc to Markdown.

5.  **Update Code & Template References**:
    - Search and replace `.asciidoc` references in:
      - `lib/OpenQA/Schema.pm`
      - `lib/OpenQA/WebAPI/Controller/API/V1/Job.pm`
      - `templates/webapi/api_key/index.html.ep`
      - `templates/webapi/layouts/bootstrap.html.ep`
      - `templates/webapi/test/live.html.ep`

## Verification & Testing

- **Documentation Generation**: Run `make generate-docs` (or execute `tools/generate-documentation`) and verify that it completes successfully and produces readable HTML/PDF outputs.
- **Link checking**: Use available linting/link-checking tools (if any exist in the Makefile) or manually verify cross-references in the generated Markdown.
- **Standard Checks**: Run `make tidy` and `make test-checkstyle` to ensure no trailing whitespaces or formatting regressions were introduced in the code/templates modified.
- Run the test suite (`make test`) to ensure no broken links in templates break frontend tests.
