defmodule ElmEx.Frontend.Pretty.Module do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.Frontend.Pretty.{Declaration, Doc}

  @type opts :: keyword()

  @spec format(Module.t(), opts()) :: Doc.t()
  def format(%Module{} = mod, opts \\ []) do
    decl_opts = Keyword.merge(opts, ports: Map.get(mod, :ports, []))

    Doc.concat([
      format_header(mod),
      Doc.break(),
      Doc.break(),
      format_imports(mod),
      format_declaration_leading_gap(mod),
      format_declarations(mod.declarations, decl_opts)
    ])
  end

  @doc false
  @spec format_declarations_only(Module.t(), opts()) :: Doc.t()
  def format_declarations_only(%Module{} = mod, opts \\ []) do
    decl_opts = Keyword.merge(opts, ports: Map.get(mod, :ports, []))
    format_declarations(mod.declarations, decl_opts)
  end

  @spec format_header(Module.t()) :: Doc.t()
  defp format_header(%Module{port_module: true} = mod) do
    Doc.concat([Doc.text("port "), format_header_module(mod)])
  end

  defp format_header(%Module{} = mod), do: format_header_module(mod)

  @spec format_header_module(Module.t()) :: Doc.t()
  defp format_header_module(%Module{name: name, module_exposing: exposing}) do
    exposing_text =
      case exposing do
        nil -> ""
        ".." -> " exposing (..)"
        list when is_list(list) -> " exposing (" <> Enum.join(list, ", ") <> ")"
        _ -> ""
      end

    Doc.text("module #{name}#{exposing_text}")
  end

  @spec format_imports(Module.t()) :: Doc.t()
  defp format_imports(%Module{import_entries: []}), do: Doc.text("")

  defp format_imports(%Module{import_entries: entries}) do
    Doc.concat(
      Enum.map(entries, fn entry ->
        module = entry["module"] || entry[:module]
        as = entry["as"] || entry[:as]
        exposing = entry["exposing"] || entry[:exposing]

        text =
          ["import ", module, as_clause(as), exposing_clause(exposing)]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("")

        Doc.concat([Doc.text(text), Doc.break()])
      end)
    )
  end

  @spec format_declaration_leading_gap(Module.t()) :: Doc.t()
  defp format_declaration_leading_gap(%Module{import_entries: [], declarations: [%{kind: :raw} | _]}),
    do: Doc.text("")

  defp format_declaration_leading_gap(%Module{import_entries: []}), do: Doc.break()

  defp format_declaration_leading_gap(%Module{import_entries: [_ | _]}) do
    Doc.concat([Doc.break(), Doc.break()])
  end

  defp as_clause(nil), do: ""
  defp as_clause(as), do: " as " <> as

  defp exposing_clause(nil), do: ""
  defp exposing_clause(".."), do: " exposing (..)"
  defp exposing_clause(list) when is_list(list), do: " exposing (" <> Enum.join(list, ", ") <> ")"
  defp exposing_clause(_), do: ""

  @spec format_declarations([map()], opts()) :: Doc.t()
  defp format_declarations(declarations, opts) do
    Doc.concat(
      declarations
      |> Enum.with_index()
      |> Enum.map(fn {decl, idx} ->
        separator =
          if idx == 0 do
            Doc.text("")
          else
            declaration_separator(Enum.at(declarations, idx - 1), decl)
          end

        Doc.concat([separator, Declaration.format(decl, opts)])
      end)
    )
  end

  @spec declaration_separator(map(), map()) :: Doc.t()
  defp declaration_separator(%{kind: :function_signature, name: name}, %{
         kind: :function_definition,
         name: name
       }) do
    Doc.break()
  end

  defp declaration_separator(%{kind: :raw, source: src}, %{kind: :function_definition})
       when is_binary(src) do
    if String.trim(src) == "{--}", do: Doc.break(), else: triple_break()
  end

  defp declaration_separator(%{kind: :function_definition}, %{kind: :raw, source: src})
       when is_binary(src) do
    cond do
      String.trim(src) == "--}" -> Doc.break()
      section_comment?(src) -> quad_break()
      true -> triple_break()
    end
  end

  defp declaration_separator(%{kind: :raw, source: prev_src}, %{kind: :raw, source: next_src}) do
    prev_trimmed = String.trim_trailing(prev_src)
    next_trimmed = String.trim(next_src)

    cond do
      String.trim(prev_src) == "--}" and String.starts_with?(next_trimmed, "{--") ->
        quad_break()

      String.ends_with?(prev_trimmed, "-}") and
          (section_border_line?(next_trimmed) or section_comment?(next_trimmed)) ->
        Doc.break()

      infix_declaration?(prev_src) and infix_declaration?(next_src) ->
        Doc.break()

      infix_declaration?(prev_src) and section_comment?(next_src) ->
        quad_break()

      true ->
        triple_break()
    end
  end

  defp declaration_separator(_prev, %{kind: :raw, source: next_src}) when is_binary(next_src) do
    trimmed = String.trim_leading(next_src)

    cond do
      section_comment?(trimmed) -> quad_break()
      String.starts_with?(trimmed, "{-") -> quad_break()
      true -> triple_break()
    end
  end

  defp declaration_separator(_prev, _next), do: triple_break()

  defp triple_break, do: Doc.concat([Doc.break(), Doc.break(), Doc.break()])

  defp quad_break, do: Doc.concat([Doc.break(), Doc.break(), Doc.break(), Doc.break()])

  defp infix_declaration?(source) when is_binary(source) do
    source |> String.trim_leading() |> infix_declaration_line?()
  end

  defp infix_declaration_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^infix(?:l|r)?\s+/u, trimmed)
  end

  defp section_comment?(source) when is_binary(source) do
    source |> String.trim_leading() |> String.starts_with?("--")
  end

  defp section_border_line?(trimmed) when is_binary(trimmed) do
    Regex.match?(~r/^-+$/u, trimmed)
  end
end