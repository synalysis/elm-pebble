defmodule Elmc.UnionDebugCtorAppPreferTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.UnionMacros
  alias ElmEx.IR
  alias ElmEx.IR.Module

  test "debug ctor table prefers unique app multi-ctor name over colliding stdlib tags" do
    ir = %IR{
      modules: [
        %Module{
          name: "SimpleOptimize",
          unions: %{
            "Opcode" => %{tags: %{"Noop" => 1, "Target" => 2, "Char" => 3}}
          },
          declarations: [],
          imports: []
        },
        %Module{
          name: "Basics",
          unions: %{
            "Order" => %{tags: %{"LT" => 1, "EQ" => 2, "GT" => 3}}
          },
          declarations: [],
          imports: []
        },
        %Module{
          name: "Json.Decode",
          unions: %{
            "Error" => %{tags: %{"Field" => 1, "Index" => 2, "OneOf" => 3, "Failure" => 4}}
          },
          declarations: [],
          imports: []
        }
      ]
    }

    fn_src =
      UnionMacros.debug_ctor_name_fn(ir,
        used_union_ctors: nil,
        entry_module: "CorpusHost",
        prod: false
      )

    assert fn_src =~ ~r/case 3:\s*return "Char";/
    assert fn_src =~ ~r/case 1:\s*return "Noop";/
    assert fn_src =~ ~r/case 2:\s*return "Target";/
  end
end
