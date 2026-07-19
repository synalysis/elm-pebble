# Expression layout lexer

Multiline Elm expressions in `elm_ex` are tokenized with **significant indentation** before Yecc parsing. Physical newlines, indent changes, and sibling binding/arm separators become explicit tokens instead of rewriting source with `;` / `;;`.

## Components

| Module | Role |
| --- | --- |
| `ElmEx.Frontend.ExprLayoutLexer` | Emits `:newline`, `:indent`, `:dedent`, `:semicolon`, `:case_sep` between per-line Leex runs |
| `ElmEx.Frontend.LayoutRules` | Shared heuristics for sibling `let` bindings, `case` arms, and expression continuations (parse + future formatter) |
| `ElmEx.Frontend.LetLayout` | Validates multiline `let`/`in` shape (rejects inline `let … in`) |
| `ElmEx.Frontend.Layout` | Whitespace helpers (`dedent_uniform_leading_whitespace/1`, `indent_lines/2`) |
| `elm_ex_expr_parser.yrl` | Layout-aware grammar for `let`, `case`, `if`, pipes, cons/append, apply-left |
| `ElmEx.Frontend.GeneratedExpressionParser` | Chooses layout lexing vs legacy normalize |

## Parse path selection

`GeneratedExpressionParser.parse/1` prepares source (comments, compose sugar, etc.), then:

1. **Layout lexer** (default) when the source has `\n`, no legacy `;;` case-arm separators, and `LetLayout.validate/1 == :ok`.
2. **Legacy normalize + Leex** otherwise (inline `let … in`, `;;` fragments, or `Application.put_env(:elm_ex, :expr_layout_lexer, false)`).

Single-line expressions always use plain Leex (no layout tokens).

`parse_with_layout_lexer/1` always runs `ExprLayoutLexer` on prepared source and skips `ExprLayout.normalize/1`. Use it in tests and tools that must exercise the layout path directly.

## Layout tokens

- `:newline` — end of a physical line (outside strings/chars).
- `:indent` / `:dedent` — stack-based significant whitespace when paren/bracket depth is zero.
- `:semicolon` — sibling `let` binding separator (same indent as the binding block).
- `:case_sep` — sibling `case` arm separator.

Continuation lines (no extra indent break) include:

- Pipe (`|>`), cons (`::`), append (`++`) after a value line.
- Split call arguments (`[ … ]`, `( … )`, `{ … }`, trailing value lines).
- RHS of `<|`, `<<`, `>>` after the operator line.

Special dedent rules:

- **`else`** — pop open indents above the `else` line; if stack top equals `else` indent, emit one `:dedent`.
- **`in`** — emit dedents for open expression indents plus the bindings block (split-RHS `let`).

## Formatter direction

`ElmEx.Frontend.Pretty` is the print counterpart. Layout-eligible multiline expressions from `let_layout_test.exs` and the fixture matrix in `layout_lexer_coverage_test.exs` round-trip through parse → format → parse (`Pretty.round_trip?/1`, `@tag :layout_round_trip`).

Coverage includes function `let` bindings (`point x y = …`), flattened triple-tuple subjects/patterns, `else if` chains and `<=` / `>=` compare sugar, multiline lambdas and call arguments, collapsed `caseSubject` lets, reverse lowering of synthetic tuple/pattern bind names (`__tupleBind_*`, `__patternBind_*`), and cons/list patterns (`::`, `[ … ]`) plus expression `::` / `++` sugar from `List.cons` / `__append__`. Empty list/record literals print compactly (`[]`, `{}`); parser operators `|.` and `|=` print infix. Pattern-lambda headers such as `\title build (Schema data) ->` and `\(Config svgConfig) b ->` are reconstructed from lambda+case chains (tight `\` prefix and parenthesized patterns). Simple `case` arms and `if`/`else if` chains print inline when branch bodies are single-line expressions (`Tick -> (model, Cmd.none)`, `if x then 1 else 0`). Preserved `&&` / `||` (`bool_and` / `bool_or`) and `/=` (from `not (… == …)`) print infix. Constructor pattern bindings in `let` print with required parentheses (`( Schema next ) = …`).

Multiline record literals and record updates use Elm-style leading-comma field layout when fields or values are multiline. Simple inline records and record updates use compact braces (`{a = 1, b = 2}`, `{scan | prevAbove = above}`). Record patterns print compactly (`{author, name}`, `{x | field}`). Cons patterns with `as` bindings keep required grouping (`(x :: xs) as full`). Partial operator sections print as backtick-style sections (`((+) 1)`, `List.map ((+) 1) values`). Module and import metadata preserve split-line `exposing` lists from the header token stream. Multiline calls stack arguments on indented lines; multiline arguments (lambdas, case, let) keep parentheses so parse grouping is preserved. Constructor case patterns keep required grouping parentheses (`CatalogReceived (Ok json)`). Infix operators print with precedence parentheses derived from yecc levels (`(a + b) * c`, `a + (b - c)`); redundant parentheses from the source are dropped when precedence makes them unnecessary (`a + (b * c)` → `a + b * c`). Simple list literals and list patterns use compact brackets when elements are simple (`[a, b]`, `["packages", author, name]`).

Grow formatter rules alongside `LayoutRules` when adding new layout shapes to the lexer. Use `Pretty.round_trip?/1` for parse stability and `Pretty.round_trip_ast?/1` when semantic AST equivalence matters (`Pretty.AstNormalize` strips layout metadata and expands preserved sugar). `Pretty.format_module/1` prints module headers, imports, type aliases (from `field_types` or `alias_type` for non-record synonyms like `type alias Model = String`, including extensible `{ base | ... }` records), unions (`=` / `|` layout), function signatures (including `port` when `ports` metadata is present), and expression bodies from parsed `expr` AST. Module-level checks use `Pretty.round_trip_module?/2` and `Pretty.round_trip_module_ast?/2` with `Pretty.ModuleNormalize`. Contract-normalized expression sugar such as `Tuple.first`, `Tuple.second`, `String.length`, and `Char.fromCode` prints as qualified calls again for round-trip.

## `let_bindings` AST

Multiline `let` blocks parse to a preserved binding list instead of immediately nesting synthetic `let_in` chains:

```elixir
%{op: :let_bindings, bindings: [...], in_expr: body}
```

Each binding entry is one of:

- `%{kind: :name, name: String.t(), value: expr}`
- `%{kind: :discard, value: expr}`
- `%{kind: :tuple2 | :tuple3, names: [String.t()], value: expr}`
- `%{kind: :pattern, pattern: pattern, value: expr}`

Optional `layout: :inline_first` records when the first binding appeared on the `let` line (`let a = …` with indented siblings). Block-style `let` / newline / indent bindings omit layout (or use `:block`).

`<|` application is preserved as `%{op: :apply_left, fn_expr: ..., arg: ...}` (like `pipe_chain` for `|>`). `ElmEx.Frontend.ApplyLeft.expand/1` lowers to nested call nodes for backends that expect the legacy flattened arg list.

`&&` / `||` are preserved as `%{op: :bool_and, left: ..., right: ...}` and `%{op: :bool_or, ...}`. `ElmEx.Frontend.BoolOps.expand/1` lowers to nested `if` for IR/backends that expect the legacy desugaring.

`ElmEx.Frontend.LetBindings.expand/1` lowers `let_bindings` to nested `let_in` (with `__tupleBind_*` / `__patternBind_*` temps when needed) for IR lowering and legacy consumers. Pretty-printing reads preserved binding and apply-left shape directly so tuple/pattern/function binding and `<|` layout round-trip without heuristics.

## Grammar note (let body + split case arms)

Indented `let … in` bodies whose expression is a `case` with split arms (`A ->` on one line, body on the next) use a yecc rule without a trailing `dedent` after the body expression—the case arm close dedents are consumed inside `case_expr`.

## Tests

- `test/frontend/expr_layout_lexer_test.exs` — token shapes and direct layout parse.
- `test/frontend/layout_lexer_coverage_test.exs` — fixture matrix + env toggle.
- `test/frontend/let_bindings_test.exs` — preserved bindings, expand lowering, pretty round-trip.
- `test/frontend/let_layout_equivalence_test.exs` — default vs layout AST equality and pretty round-trip across `let_layout_test` heredocs.
- `test/frontend/pretty_module_fixture_round_trip_test.exs` — small `elmc` fixture modules (`round_trip_module_ast?/2`).
- `test/frontend/generated_parser_metadata_test.exs` — split-line module/import exposing metadata.
- `test/tree_sitter_corpus_parse_gate_test.exs` — full Elm corpus still parses.

## Opt out

```elixir
Application.put_env(:elm_ex, :expr_layout_lexer, false)
```
