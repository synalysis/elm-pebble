defmodule Ide.Debugger.RuntimeExecEventTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.Types.RuntimeExecEventPayload

  @mini_elm """
  module RuntimeExecEvent exposing (..)

  type Msg = Inc

  init _ = ( {}, Cmd.none )

  update _ model = ( model, Cmd.none )
  """

  test "from_runtime maps elm_executor snapshot fields" do
    runtime = %{
      "engine" => "elm_executor_runtime_v1",
      "source_byte_size" => 42,
      "msg_constructor_count" => 1,
      "update_case_branch_count" => 2,
      "view_case_branch_count" => 3,
      "runtime_model_source" => "init_model",
      "view_tree_source" => "parser_view_tree",
      "execution_backend" => "default",
      "runtime_mode" => "runtime_first",
      "followup_message_count" => 0,
      "init_cmd_count" => 0,
      "runtime_model_entry_count" => 1,
      "view_tree_node_count" => 2,
      "runtime_model_sha256" => String.duplicate("a", 64),
      "view_tree_sha256" => String.duplicate("b", 64)
    }

    payload = RuntimeExecEventPayload.from_runtime(runtime, "watch", %{trigger: "reload"})

    assert payload.target == "watch"
    assert payload.engine == "elm_executor_runtime_v1"
    assert payload.runtime_model_source == "init_model"
    assert payload.trigger == "reload"
    assert payload.runtime_model_sha256 == String.duplicate("a", 64)
  end

  test "reload appends debugger.runtime_exec with contract payload" do
    slug = "runtime_exec_event_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.reload(slug, %{
               "rel_path" => "src/RuntimeExecEvent.elm",
               "source_root" => "watch",
               "source" => @mini_elm
             })

    event = Enum.find(state.events, &(&1.type == "debugger.runtime_exec"))
    assert event
    assert event.payload.target == "watch"
    assert is_binary(event.payload.engine)
    assert is_integer(event.payload.runtime_model_entry_count)
  end
end
