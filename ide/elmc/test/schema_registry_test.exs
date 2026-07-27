defmodule Elmc.SchemaRegistryTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.SchemaRegistry

  test "all_native? for int-only records" do
    registry =
      SchemaRegistry.build_from_field_types(%{
        {"Main", "Point"} => %{"x" => "Int", "y" => "Int"},
        {"Grid", "Coord"} => %{"row" => "Int", "col" => "Int"}
      })

    assert SchemaRegistry.all_native?(registry, "Main", "Point")
    assert SchemaRegistry.all_native?(registry, "Grid", "Coord")
    refute SchemaRegistry.all_native?(registry, "Main", "Missing")
  end

  test "non-native record fields exclude compact record list schema" do
    registry =
      SchemaRegistry.build_from_field_types(%{
        {"Main", "Tagged"} => %{"tag" => "String", "value" => "Int"}
      })

    refute SchemaRegistry.all_native?(registry, "Main", "Tagged")
    assert SchemaRegistry.list_elem_schema(registry, "List Tagged") == {:boxed, :value}
  end

  test "field maps are stable for same-shaped records under different names" do
    shape_a =
      SchemaRegistry.build_from_field_types(%{
        {"Main", "Alpha"} => %{"x" => "Int", "y" => "Int"}
      })

    shape_b =
      SchemaRegistry.build_from_field_types(%{
        {"Main", "Beta"} => %{"x" => "Int", "y" => "Int"}
      })

    alpha = SchemaRegistry.record(shape_a, "Main", "Alpha")
    beta = SchemaRegistry.record(shape_b, "Main", "Beta")

    assert alpha.native_field_names == beta.native_field_names
    assert Map.keys(alpha.fields) == Map.keys(beta.fields)
  end

  test "list_elem_schema recognizes primitive list types" do
    registry = SchemaRegistry.build_from_field_types(%{})

    assert SchemaRegistry.list_elem_schema(registry, "List Int") == {:primitive, :int}
    assert SchemaRegistry.list_elem_schema(registry, "List Float") == {:primitive, :float}
    assert SchemaRegistry.list_elem_schema(registry, "List Bool") == {:primitive, :bool}
  end
end
