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
      format_declarations(mod.declarations, decl_opts)
    ])
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
      end) ++ [Doc.break()]
    )
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
      Enum.intersperse(
        Enum.map(declarations, &Declaration.format(&1, opts)),
        Doc.concat([Doc.break(), Doc.break()])
      )
    )
  end
end
