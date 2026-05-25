defmodule Ide.Debugger.ProtocolResolutionCtxTest do
  use ExUnit.Case, async: true

  alias Ide.{CompanionProtocolGenerator, Debugger.ProtocolResolutionCtx}

  @types """
  module Companion.Types exposing (WatchToPhone(..), PhoneToWatch(..))

  type WatchToPhone
      = Ping Int

  type PhoneToWatch
      = Pong Int
  """

  test "with_message_resolution stores schema ctor and fields" do
    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(@types)
    [%{name: "Ping", fields: fields}] = schema.watch_to_phone

    ctx =
      ProtocolResolutionCtx.new(
        direction: :watch_to_phone,
        runtime_model: %{},
        simulator_settings: %{}
      )
      |> ProtocolResolutionCtx.with_message_resolution(schema, "Ping", fields)

    assert ProtocolResolutionCtx.schema(ctx) == schema
    assert [%{wire_type: :int} | _] = ProtocolResolutionCtx.message_fields(ctx)
    assert ctx.protocol_ctor == "Ping"
  end
end
