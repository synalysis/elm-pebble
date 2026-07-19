defmodule ElmEx.Frontend.Pretty.ModuleNormalize do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.Frontend.Pretty.AstNormalize

  @doc """
  Returns true when two module ASTs are equivalent for formatter round-trip.

  Compares header metadata and normalized declaration payloads (expression
  bodies via `AstNormalize`, type aliases including extensible bases, unions).
  """
  @spec equivalent?(Module.t(), Module.t()) :: boolean()
  def equivalent?(left, right), do: normalize(left) == normalize(right)

  @spec normalize(Module.t()) :: map()
  def normalize(%Module{} = mod) do
    %{
      name: mod.name,
      module_exposing: Map.get(mod, :module_exposing),
      port_module: Map.get(mod, :port_module, false),
      ports: Map.get(mod, :ports, []),
      import_entries: normalize_import_entries(Map.get(mod, :import_entries, [])),
      declarations: Enum.map(mod.declarations, &normalize_declaration/1)
    }
  end

  @spec normalize_import_entries([map()]) :: [map()]
  defp normalize_import_entries(entries) do
    Enum.map(entries, fn entry ->
      %{
        module: entry["module"] || entry[:module],
        as: entry["as"] || entry[:as],
        exposing: entry["exposing"] || entry[:exposing]
      }
    end)
  end

  @spec normalize_declaration(map()) :: map()
  defp normalize_declaration(%{kind: :function_definition} = decl) do
    %{
      kind: :function_definition,
      name: decl.name,
      args: Map.get(decl, :args, []),
      expr: AstNormalize.normalize(decl.expr)
    }
  end

  defp normalize_declaration(%{kind: :function_signature} = decl) do
    %{kind: :function_signature, name: decl.name, type: decl.type}
  end

  defp normalize_declaration(%{kind: :type_alias} = decl) do
    %{
      kind: :type_alias,
      name: decl.name,
      fields: Map.get(decl, :fields, []),
      field_types: Map.get(decl, :field_types, %{}),
      extensible_base: Map.get(decl, :extensible_base),
      alias_type: Map.get(decl, :alias_type)
    }
  end

  defp normalize_declaration(%{kind: :union} = decl) do
    %{
      kind: :union,
      name: decl.name,
      constructors: decl.constructors
    }
  end

  defp normalize_declaration(other) do
    Map.drop(other, [:span, :body])
  end
end
