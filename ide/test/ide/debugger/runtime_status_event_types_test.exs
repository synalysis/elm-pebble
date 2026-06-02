defmodule Ide.Debugger.RuntimeStatusEventTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.Types.RuntimeStatusEventPayload

  test "from_runtime maps status fields from runtime_execution snapshot" do
    runtime = %{
      "execution_backend" => "external",
      "runtime_mode" => "hybrid",
      "external_fallback_reason" => "boom",
      "followup_message_count" => 0,
      "init_cmd_count" => 2
    }

    payload =
      RuntimeStatusEventPayload.from_runtime(runtime, "watch", "runtime fallback external: boom")

    assert payload.target == "watch"
    assert payload.message =~ "fallback"
    assert payload.execution_backend == "external"
    assert payload.runtime_mode == "hybrid"
    assert payload.external_fallback_reason == "boom"
    assert payload.init_cmd_count == 2
  end
end
