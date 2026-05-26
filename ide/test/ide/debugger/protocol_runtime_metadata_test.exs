defmodule Ide.Debugger.ProtocolRuntimeMetadataTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ProtocolRuntimeMetadata

  test "preserve copies protocol counters from previous model" do
    previous = %{
      "protocol_inbound_count" => 3,
      "runtime_model" => %{"protocol_last_inbound_from" => "watch"}
    }

    model = %{"runtime_model" => %{}}

    preserved = ProtocolRuntimeMetadata.preserve(model, previous)

    assert preserved["protocol_inbound_count"] == 3
    assert preserved["runtime_model"]["protocol_last_inbound_from"] == "watch"
  end
end
