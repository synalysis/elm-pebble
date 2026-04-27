# Syntax.hs Coverage Matrix

This matrix tracks Elm `Syntax.hs` title coverage through the catalog + mapper pipeline.

## Coverage Source

- Upstream source: `https://github.com/elm/compiler/blob/master/compiler/src/Reporting/Error/Syntax.hs`
- Inventory function: `Ide.Diagnostics.ElmSyntaxCatalog.all_titles/0`
- Mapping function: `Ide.Diagnostics.ElmSyntaxCatalog.coverage_matrix/0`

## Routing Rule

- Each upstream title maps to a catalog ID via `title_to_id/1`.
- Primary mapper entrypoint: `Ide.Diagnostics.TokenizerParserMapper.from_title/6`.
- Compiler parser/lexer reasons route through `compiler_parser_hint/1`, which infers or consumes `elm_title` and then delegates to `from_title/6`.

## Family Buckets Covered

- Lexical/literals: `ENDLESS STRING`, `MISSING SINGLE QUOTE`, `UNKNOWN ESCAPE`, `BAD UNICODE ESCAPE`, `WEIRD NUMBER`, `WEIRD HEXIDECIMAL`, `LEADING ZEROS`, `NEEDS DOUBLE QUOTES`.
- Structure/delimiters: `UNFINISHED_*`, `UNEXPECTED_*`, `MISSING_*`, `EXTRA COMMA`, `NEED MORE INDENTATION`.
- Declarations/modules/imports/exposing: `MODULE NAME *`, `EXPECTING IMPORT *`, `PROBLEM IN EXPOSING`, `BAD MODULE DECLARATION`, `PORT PROBLEM`.
- Types/patterns/records: `PROBLEM IN TYPE ALIAS`, `PROBLEM IN CUSTOM TYPE`, `PROBLEM IN RECORD`, `PROBLEM IN RECORD TYPE`, `PROBLEM IN PATTERN`, `UNFINISHED RECORD TYPE`, `UNFINISHED LIST PATTERN`.

## Dynamic Syntax.hs Templates

The matrix includes the dynamic templates used in `Syntax.hs`:

- `UNEXPECTED {TERM}`
- `STRAY {TERM}`
- `PROBLEM IN {THING}`
- `UNFINISHED {THING}`

These are normalized through `title_to_id/1` using the literal template title form above.
