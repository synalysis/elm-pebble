defmodule Elmc.PebbleContractCmdSubSdkMapTest do
  @moduledoc """
  Contract Cmd/Sub ids → Pebble SDK symbols in the canonical app template.

  Locks the runtime half of the Elm→SDK path: each `ELMC_PEBBLE_CMD_*` case and
  subscription enable path must call the SDK functions declared in the contract.
  """

  use ExUnit.Case, async: true

  alias Elmx.Pebble.Contract.{CmdSub, TemplateSdkAssert}

  test "every contract cmd case in pebble_app_template invokes declared SDK symbols" do
    source = TemplateSdkAssert.template_source!()

    for row <- CmdSub.cmds(), row.id != :none, row.sdk_calls != [] do
      TemplateSdkAssert.assert_cmd_sdk_calls!(source, row)
    end
  end

  test "every contract sub enable path invokes declared SDK symbols" do
    template = TemplateSdkAssert.template_source!()
    animation = TemplateSdkAssert.animation_dispatch_sources!()

    for row <- CmdSub.subs(), row.sdk_calls != [] do
      extra =
        if row.id == :animation_finished do
          [animation]
        else
          []
        end

      TemplateSdkAssert.assert_sub_sdk_calls!(template, row, extra_sources: extra)
    end
  end
end
