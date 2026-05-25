defmodule Elmc.Runtime.ExecutionResultTypesTest do
  use ExUnit.Case, async: true

  alias Elmc.Runtime.Executor
  test "execute returns execution result contract keys" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 0},
        "msg_constructors" => ["Inc"],
        "update_case_branches" => ["Inc"],
        "view_case_branches" => ["Main"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"n" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert match?(
             %{
               model_patch: _,
               view_tree: _,
               view_output: _,
               runtime: _,
               protocol_events: _,
               followup_messages: _
             },
             result
           )
    assert is_map(result.model_patch)
    assert is_map(result.runtime)
    assert is_list(result.protocol_events)
    assert result.followup_messages == []
    assert result.view_output == []
  end
end
