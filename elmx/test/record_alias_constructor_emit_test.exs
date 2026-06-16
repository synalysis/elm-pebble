defmodule Elmx.RecordAliasConstructorEmitTest do
  use ExUnit.Case, async: false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.TestSupport.TemplateProject

  @tag timeout: 180_000
  test "companion emit references record alias constructors as lambdas" do
    {:ok, dir} = TemplateProject.scaffold_phone("watchface-tangram-time")
    revision = "record-alias-#{System.unique_integer([:positive])}"

    try do
      assert {:ok, result} =
               Elmx.compile_in_memory(dir, %{
                 entry_module: "CompanionApp",
                 revision: revision,
                 strip_dead_code: true,
                 mode: :ide_runtime
               })

      source =
        Enum.find_value(result.modules, fn mod ->
          if String.contains?(mod.name, "CompanionApp"), do: mod.source
        end)

      assert is_binary(source)

      companion_ir = Enum.find(result.ir.modules, &(&1.name == "CompanionApp"))

      field_types =
        Enum.reduce(companion_ir.declarations, %{}, fn
          %{kind: :type_alias, name: name, expr: %{op: :record_alias, field_types: types}}, acc
          when is_map(types) ->
            Map.put(acc, name, types)

          _, acc ->
            acc
        end)

      assert Map.has_key?(field_types, "RawPoint"),
             "missing RawPoint alias, keys: #{inspect(Map.keys(field_types))}"

      assert {:ok, ctor_code} = Helpers.record_alias_constructor_code("RawPoint", %{record_field_types: field_types})
      assert IO.iodata_to_binary(ctor_code) =~ "elmx_alias_"

      assert source =~ "elmx_alias_"
      refute source =~ ~r/maybe_map2\([^)]*:RawPoint\)/
    after
      File.rm_rf(dir)
    end
  end
end
