defmodule ElmEx.Frontend.Pretty do
  @moduledoc """
  Pretty-print Elm frontend AST back to source-shaped text.

  This is the print direction counterpart to `ElmEx.Frontend.ExprLayoutLexer`
  (layout while lexing) and `ElmEx.Frontend.ExprLayout` (legacy flatten pass).

  The formatter is intentionally incremental: expression and module layout rules
  grow here while the indent lexer absorbs the same semantics for parsing.
  """

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.Frontend.Pretty.AstNormalize
  alias ElmEx.Frontend.Pretty.Finalize
  alias ElmEx.Frontend.Pretty.ModuleNormalize
  alias ElmEx.Frontend.Pretty.Doc
  alias ElmEx.Frontend.Pretty.Expr
  alias ElmEx.Frontend.Pretty.Module, as: ModulePretty
  alias ElmEx.Frontend.Pretty.PreserveNormalize
  alias ElmEx.Frontend.SourceComments
  alias ElmEx.Frontend.SourceRegions

  @type opts :: [
          width: pos_integer(),
          indent: non_neg_integer()
        ]

  @doc """
  Format an expression AST node to a string.
  """
  @spec format_expr(map(), opts()) :: String.t()
  def format_expr(expr, opts \\ []) when is_map(expr) do
    expr
    |> Expr.format(opts)
    |> Doc.render(opts)
  end

  @doc """
  Parse multiline expression source, then format it.

  Uses `GeneratedExpressionParser.parse/1` (layout lexer by default).
  Returns `{:ok, formatted}` on success or `{:error, reason}` when parse fails.
  """
  @spec format_source(String.t(), opts()) :: {:ok, String.t()} | {:error, term()}
  def format_source(source, opts \\ []) when is_binary(source) do
    with {:ok, ast} <- GeneratedExpressionParser.parse(source) do
      {:ok, format_expr(ast, opts)}
    end
  end

  @doc """
  Returns true when source parses and formatted output parses again to an AST.
  """
  @spec round_trip?(String.t(), opts()) :: boolean()
  def round_trip?(source, opts \\ []) when is_binary(source) do
    with {:ok, formatted} <- format_source(source, opts),
         {:ok, _} <- GeneratedExpressionParser.parse(formatted) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Returns true when parse → format → parse yields an AST equivalent to the original.

  Uses `AstNormalize` to ignore layout-only metadata and preserved-sugar shapes.
  """
  @spec round_trip_ast?(String.t(), opts()) :: boolean()
  def round_trip_ast?(source, opts \\ []) when is_binary(source) do
    with {:ok, ast} <- GeneratedExpressionParser.parse(source),
         formatted = format_expr(ast, opts),
         {:ok, reparsed} <- GeneratedExpressionParser.parse(formatted) do
      AstNormalize.equivalent?(ast, reparsed)
    else
      _ -> false
    end
  end

  @doc """
  Format a module AST to a string.
  """
  @spec format_module(FrontendModule.t(), opts()) :: String.t()
  def format_module(%FrontendModule{} = mod, opts \\ []) do
    mod
    |> ModulePretty.format(opts)
    |> Doc.render(opts)
  end

  @doc """
  Format a declaration map to a string.
  """
  @spec format_declaration(map(), opts()) :: String.t()
  def format_declaration(decl, opts \\ []) when is_map(decl) do
    decl
    |> ElmEx.Frontend.Pretty.Declaration.format(opts)
    |> Doc.render(opts)
  end

  @doc """
  Parse module source, format it, and parse again.

  Returns `{:ok, formatted}` on success.
  """
  @spec format_module_source(String.t(), String.t(), opts()) :: {:ok, String.t()} | {:error, term()}
  def format_module_source(path, source, opts \\ [])
      when is_binary(path) and is_binary(source) do
    with {:ok, mod} <- GeneratedParser.parse_source(path, source) do
      {:ok, format_module(mod, opts)}
    end
  end

  @doc """
  Parse module source, pretty-print, and merge comments/docs from the original source.
  """
  @spec format_module_source_preserve(String.t(), String.t(), opts()) ::
          {:ok, String.t()} | {:error, term()}
  def format_module_source_preserve(path, source, opts \\ [])
      when is_binary(path) and is_binary(source) do
    with {:ok, mod} <- GeneratedParser.parse_source(path, source) do
      regions =
        source
        |> SourceRegions.extract()
        |> PreserveNormalize.normalize_regions(mod)

      comments =
        source
        |> then(&SourceComments.extract(path, &1, mod))
        |> SourceComments.for_body_region(regions.body_line_start)

      declarations =
        mod
        |> ModulePretty.format_declarations_only(opts)
        |> Doc.render(opts)
        |> SourceComments.merge(comments)
        |> Finalize.finalize()

      formatted = SourceRegions.stitch(regions, declarations)

      {:ok, formatted}
    end
  end

  @doc """
  Returns true when module source parses, formats, and re-parses successfully.
  """
  @spec round_trip_module?(String.t(), String.t(), opts()) :: boolean()
  def round_trip_module?(path, source, opts \\ [])
      when is_binary(path) and is_binary(source) do
    with {:ok, formatted} <- format_module_source(path, source, opts),
         {:ok, _} <- GeneratedParser.parse_source(path, formatted) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Returns true when parse → format → parse yields a module equivalent to the original.

  Uses `ModuleNormalize` for declaration-level comparison.
  """
  @spec round_trip_module_ast?(String.t(), String.t(), opts()) :: boolean()
  def round_trip_module_ast?(path, source, opts \\ [])
      when is_binary(path) and is_binary(source) do
    with {:ok, mod} <- GeneratedParser.parse_source(path, source),
         formatted = format_module(mod, opts),
         {:ok, reparsed} <- GeneratedParser.parse_source(path, formatted) do
      ModuleNormalize.equivalent?(mod, reparsed)
    else
      _ -> false
    end
  end
end
