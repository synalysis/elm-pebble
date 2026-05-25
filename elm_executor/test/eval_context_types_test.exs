defmodule ElmExecutor.Runtime.EvalContextTypesTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR
  alias ElmExecutor.Runtime.CoreIREvaluator
  defp minimal_core_ir(module_name, decls) do
    %{
      "version" => "elm_ex.core_ir.v1",
      "modules" => [
        %{
          "name" => module_name,
          "imports" => [],
          "unions" => %{
            "Msg" => %{
              "tags" => %{"Tick" => 0},
              "payload_specs" => %{}
            }
          },
          "declarations" => decls
        }
      ],
      "diagnostics" => [],
      "deterministic_sha256" => "test"
    }
  end

  test "index_functions builds typed function index from two modules" do
    ir = %ElmEx.IR{
      modules: [
        %ElmEx.IR.Module{
          name: "Main",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "main",
              args: [],
              expr: %{op: :int_literal, value: 1},
              ownership: []
            }
          ]
        },
        %ElmEx.IR.Module{
          name: "Helper",
          imports: [],
          declarations: [
            %ElmEx.IR.Declaration{
              kind: :function,
              name: "tick",
              args: ["model"],
              expr: %{op: :int_literal, value: 2},
              ownership: []
            }
          ]
        }
      ]
    }

    assert {:ok, core_ir} = CoreIR.from_ir(ir)
    functions = CoreIREvaluator.index_functions(core_ir)

    assert functions[{"Main", "main", 0}].module == "Main"
    assert functions[{"Helper", "tick", 1}].name == "tick"
  end

  test "index_record_aliases and constructor_tags populate eval context fields" do
    core_ir =
      minimal_core_ir("Main", [
        %{
          "kind" => "type_alias",
          "name" => "Model",
          "args" => [],
          "ownership" => [],
          "expr" => %{
            "op" => "record_alias",
            "fields" => ["count"],
            "field_types" => %{"count" => "Int"}
          }
        },
        %{
          "kind" => "function",
          "name" => "init",
          "args" => [],
          "ownership" => [],
          "expr" => %{"op" => "record", "fields" => [%{"name" => "count", "value" => %{"op" => "int_literal", "value" => 0}}]}
        }
      ])

    aliases = CoreIREvaluator.index_record_aliases(core_ir)
    field_types = CoreIREvaluator.index_record_alias_field_types(core_ir)
    tags = CoreIREvaluator.index_constructor_tags(core_ir)

    assert aliases[{"Main", "Model"}] == ["count"]
    assert field_types[{"Main", "Model"}]["count"] == "Int"
    assert Enum.any?(tags, &(&1.ctor == "Tick" and &1.module == "Main"))

    ctx = %{
      functions: CoreIREvaluator.index_functions(core_ir),
      record_aliases: aliases,
      record_alias_field_types: field_types,
      constructor_tags: tags,
      launch_context: %{"supports_health" => true}
    }

    assert match?(%{functions: %{}, record_aliases: %{}, constructor_tags: [_ | _]}, ctx)
    assert ctx.launch_context["supports_health"] == true
  end
end
