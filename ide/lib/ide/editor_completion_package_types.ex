defmodule Ide.EditorCompletionPackageTypes do
  @moduledoc false

  alias Ide.EditorCompletionTypeParse
  alias Ide.EditorCompletion.Types, as: CompletionTypes

  @type package_type_maps :: CompletionTypes.package_type_maps()
  @type doc_package_row :: CompletionTypes.doc_package_row()

  @spec build([doc_package_row()] | nil) :: package_type_maps()
  def build(rows) when is_list(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      module_docs = row[:docs] || row["docs"] || []

      Enum.reduce(module_docs, acc, fn module_doc, module_acc ->
        module_name = module_doc[:name] || module_doc["name"]

        if is_binary(module_name) and module_name != "" do
          merge_module_aliases(module_acc, module_name, module_doc)
        else
          module_acc
        end
      end)
    end)
  end

  def build(_), do: %{}

  defp merge_module_aliases(acc, module_name, module_doc) do
    aliases = module_doc[:aliases] || module_doc["aliases"] || []

    Enum.reduce(aliases, acc, fn alias_doc, alias_acc ->
      name = alias_doc[:name] || alias_doc["name"]
      type_body = alias_doc[:type] || alias_doc["type"] || ""

      if is_binary(name) and name != "" do
        put_type(alias_acc, "#{module_name}.#{name}", type_body)
      else
        alias_acc
      end
    end)
  end

  defp put_type(acc, type_name, type_body) do
    specs = EditorCompletionTypeParse.record_field_specs(type_body)

    if specs == [] do
      acc
    else
      fields = Enum.map(specs, & &1.name)
      field_types = Map.new(specs, fn spec -> {spec.name, spec.type} end)
      short_name = type_name |> String.split(".") |> List.last()

      acc
      |> Map.put(type_name, %{fields: fields, field_types: field_types})
      |> Map.put(short_name, %{fields: fields, field_types: field_types})
    end
  end
end
