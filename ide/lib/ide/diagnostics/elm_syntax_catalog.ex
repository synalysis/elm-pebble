defmodule Ide.Diagnostics.ElmSyntaxCatalog do
  @moduledoc """
  Versioned catalog of Elm-style syntax diagnostics used by tokenizer/parser flows.
  """

  @catalog_version "elm-compiler-0.19.1-syntax-full-v1"
  @source_reference "https://github.com/elm/compiler/blob/master/compiler/src/Reporting/Error/Syntax.hs"

  @syntax_titles [
    "BAD INFIX",
    "BAD MODULE DECLARATION",
    "BAD UNICODE ESCAPE",
    "ENDLESS COMMENT",
    "ENDLESS SHADER",
    "ENDLESS STRING",
    "EXPECTING DECLARATION",
    "EXPECTING DEFINITION",
    "EXPECTING IMPORT ALIAS",
    "EXPECTING IMPORT NAME",
    "EXPECTING MODULE NAME",
    "EXPECTING RECORD ACCESSOR",
    "EXPECTING TYPE ALIAS NAME",
    "EXPECTING TYPE NAME",
    "EXTRA COMMA",
    "INVALID EFFECT MODULE",
    "LEADING ZEROS",
    "LET PROBLEM",
    "MISSING ARGUMENT",
    "MISSING ARROW",
    "MISSING COLON?",
    "MISSING EXPRESSION",
    "MISSING SINGLE QUOTE",
    "MODULE NAME MISMATCH",
    "MODULE NAME MISSING",
    "NAME MISMATCH",
    "NEED MORE INDENTATION",
    "NEEDS DOUBLE QUOTES",
    "NO PORTS",
    "NO TABS",
    "PACKAGES CANNOT HAVE PORTS",
    "PORT PROBLEM",
    "PROBLEM EXPOSING CUSTOM TYPE VARIANTS",
    "PROBLEM IN CUSTOM TYPE",
    "PROBLEM IN DEFINITION",
    "PROBLEM IN EXPOSING",
    "PROBLEM IN PATTERN",
    "PROBLEM IN RECORD",
    "PROBLEM IN RECORD TYPE",
    "PROBLEM IN TYPE ALIAS",
    "RESERVED SYMBOL",
    "RESERVED WORD",
    "SHADER PROBLEM",
    "SYNTAX PROBLEM",
    "TOO MUCH INDENTATION",
    "UNEXPECTED ARROW",
    "UNEXPECTED CAPITAL LETTER",
    "UNEXPECTED CHARACTER",
    "UNEXPECTED COMMA",
    "UNEXPECTED EQUALS",
    "UNEXPECTED NAME",
    "UNEXPECTED OPERATOR",
    "UNEXPECTED PATTERN",
    "UNEXPECTED PORTS",
    "UNEXPECTED SEMICOLON",
    "UNEXPECTED SYMBOL",
    "UNFINISHED ANONYMOUS FUNCTION",
    "UNFINISHED CASE",
    "UNFINISHED CUSTOM TYPE",
    "UNFINISHED DEFINITION",
    "UNFINISHED EXPOSING",
    "UNFINISHED IF",
    "UNFINISHED IMPORT",
    "UNFINISHED LET",
    "UNFINISHED LIST",
    "UNFINISHED LIST PATTERN",
    "UNFINISHED MODULE DECLARATION",
    "UNFINISHED OPERATOR FUNCTION",
    "UNFINISHED PARENTHESES",
    "UNFINISHED PATTERN",
    "UNFINISHED PORT",
    "UNFINISHED PORT MODULE DECLARATION",
    "UNFINISHED RECORD",
    "UNFINISHED RECORD PATTERN",
    "UNFINISHED RECORD TYPE",
    "UNFINISHED TUPLE",
    "UNFINISHED TUPLE PATTERN",
    "UNFINISHED TUPLE TYPE",
    "UNFINISHED TYPE ALIAS",
    "UNKNOWN ESCAPE",
    "WEIRD DECLARATION",
    "WEIRD ELSE BRANCH",
    "WEIRD HEXIDECIMAL",
    "WEIRD NUMBER",
    "UNEXPECTED {TERM}",
    "STRAY {TERM}",
    "PROBLEM IN {THING}",
    "UNFINISHED {THING}"
  ]

  @seed_entries %{
    endless_comment: %{
      title: "ENDLESS COMMENT",
      source_title: "ENDLESS COMMENT",
      summary: "I cannot find the end of this multi-line comment.",
      hint:
        "Add a -} somewhere after this to end the comment. Multi-line comments can be nested, so the start and end markers must be balanced.",
      example: "{- outer {- inner -} -}",
      span_semantics: :start_to_eof
    },
    endless_string_single: %{
      title: "ENDLESS STRING",
      source_title: "ENDLESS STRING",
      summary: "I got to the end of the line without seeing the closing double quote.",
      hint:
        "Strings look like \"this\" with double quotes on each end. For multi-line strings, use triple double quotes.",
      example: "\"\"\"\n# Multi-line Strings\n\"\"\"",
      span_semantics: :start_to_eof
    },
    endless_string_multi: %{
      title: "ENDLESS STRING",
      source_title: "ENDLESS STRING",
      summary: "I cannot find the end of this multi-line string.",
      hint: "Add a \"\"\" somewhere after this to end the string.",
      example: "\"\"\"\n# Multi-line Strings\n\"\"\"",
      span_semantics: :start_to_eof
    },
    missing_single_quote: %{
      title: "MISSING SINGLE QUOTE",
      source_title: "MISSING SINGLE QUOTE",
      summary: "I thought I was parsing a character, but did not find the closing single quote.",
      hint: "Add a closing single quote, or switch to double quotes for strings.",
      example: "'a'  and  \"text\"",
      span_semantics: :token
    },
    unexpected_closing_delimiter: %{
      title: "STRAY CLOSING DELIMITER",
      source_title: "STRAY PARENS/BRACE/BRACKET",
      summary: "I was not expecting to see this closing delimiter here.",
      hint: "This does not match up with an earlier open delimiter. Try deleting it?",
      example: "value = (1 + 2]",
      span_semantics: :token
    },
    unclosed_delimiter: %{
      title: "UNFINISHED PARENTHESES",
      source_title: "UNFINISHED PARENTHESES/RECORD/LIST",
      summary: "I was expecting to see a closing delimiter next, but got stuck.",
      hint: "Try adding the expected closing delimiter to see if that helps.",
      example: "value = (1 + 2",
      span_semantics: :opening_to_eof
    },
    syntax_problem: %{
      title: "SYNTAX PROBLEM",
      source_title: "SYNTAX PROBLEM",
      summary: "I ran into something unexpected while parsing this code.",
      hint: "Check for missing delimiters, misplaced operators, or indentation issues nearby.",
      example: "value if = 1",
      span_semantics: :inferred
    },
    unexpected_character: %{
      title: "UNEXPECTED CHARACTER",
      source_title: "UNEXPECTED CHARACTER",
      summary: "I ran into an unexpected character while tokenizing this code.",
      hint: "Try removing the character or replacing it with valid Elm syntax.",
      example: "value = @",
      span_semantics: :inferred
    }
  }

  @title_to_id Map.new(@syntax_titles, fn title ->
                 id =
                   title
                   |> String.downcase()
                   |> String.replace(~r/[^a-z0-9]+/u, "_")
                   |> String.trim("_")
                   |> String.to_atom()

                 {title, id}
               end)
  @entries Enum.reduce(@syntax_titles, @seed_entries, fn title, acc ->
             id = Map.get(@title_to_id, title, :syntax_problem)

             Map.put_new(acc, id, %{
               title: title,
               source_title: title,
               summary: "I ran into this syntax issue while parsing your Elm code.",
               hint:
                 "Check the surrounding syntax and delimiters, then compare with a valid nearby construct.",
               example: "See nearby Elm syntax for the expected shape.",
               span_semantics: :inferred
             })
           end)

  @spec catalog_version() :: String.t()
  def catalog_version, do: @catalog_version

  @spec source_reference() :: String.t()
  def source_reference, do: @source_reference

  @spec all_titles() :: [String.t()]
  def all_titles, do: @syntax_titles

  @spec all_ids() :: [atom()]
  def all_ids do
    @entries
    |> Map.keys()
    |> Enum.sort()
  end

  @spec coverage_matrix() :: [map()]
  def coverage_matrix do
    Enum.map(@syntax_titles, fn title ->
      id = title_to_id(title)

      %{
        title: title,
        catalog_id: id,
        mapper_entrypoint: "from_title/6",
        compiler_hint_entrypoint: "compiler_parser_hint/1",
        default_origin: "tokenizer/compiler parser diagnostics"
      }
    end)
  end

  @spec entry(atom()) :: map() | nil
  def entry(id) when is_atom(id), do: Map.get(@entries, id)

  @spec entry_by_title(String.t()) :: map() | nil
  def entry_by_title(title) when is_binary(title) do
    title
    |> title_to_id()
    |> entry()
  end

  @spec title_to_id(String.t()) :: atom()
  def title_to_id(title) when is_binary(title) do
    Map.get(@title_to_id, title, :syntax_problem)
  end

  @spec build_message(atom(), map()) :: String.t()
  def build_message(id, details \\ %{}) when is_atom(id) and is_map(details) do
    case entry(id) do
      nil ->
        normalize_detail(details[:detail] || details["detail"] || "Unknown syntax problem.")

      entry ->
        detail =
          details[:detail] || details["detail"] ||
            ""
            |> normalize_detail()

        lines =
          [
            entry.title,
            entry.summary,
            detail,
            "Hint: " <> entry.hint
          ]
          |> Enum.reject(&(&1 == ""))

        Enum.join(lines, "\n\n")
    end
  end

  @spec normalize_detail(term()) :: term()
  defp normalize_detail(value) when is_binary(value), do: String.trim(value)
  defp normalize_detail(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp normalize_detail(value) when is_list(value), do: value |> List.to_string() |> String.trim()
  defp normalize_detail(value) when is_number(value), do: value |> to_string() |> String.trim()
  defp normalize_detail(value), do: value |> inspect() |> String.trim()
end
