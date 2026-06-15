defmodule Elmc.Backend.Pebble.MsgCodegen.Fragments do
  @moduledoc false

  alias Elmc.Backend.Pebble.{IRAnalysis, MsgCodegen, Types, Util}

  @spec build(Types.msg_constructor_list(), Types.msg_constructor_arities()) ::
          Types.msg_fragments()
  def build(msg_constructors, msg_constructor_arities) do
    value_decode_cases = MsgCodegen.DecodeCases.switch_cases(msg_constructors)
    key_decode_cases = MsgCodegen.DecodeCases.switch_cases(msg_constructors)

    msg_constructor_arity_cases =
      msg_constructors
      |> Enum.map_join("\n", fn {name, _tag} ->
        arity = Map.get(msg_constructor_arities, name, 0)
        "      case ELMC_PEBBLE_MSG_#{Util.macro_name(name)}: return #{arity};"
      end)

    tick_has_payload? =
      Enum.any?(msg_constructors, fn {name, _} ->
        Map.get(msg_constructor_arities, name, 0) > 0
      end)

    %{
      value_decode_cases: value_decode_cases,
      key_decode_cases: key_decode_cases,
      msg_constructor_arity_cases: msg_constructor_arity_cases,
      tick_has_payload?: tick_has_payload?,
      current_second_helper: MsgCodegen.TickArity.current_second_helper(tick_has_payload?),
      storage_string_tag:
        IRAnalysis.pick_tag(msg_constructors, MsgCodegen.storage_string_callback_names()),
      msg_constructor_arity_fn:
        MsgCodegen.TickArity.constructor_arity_fn(tick_has_payload?, msg_constructor_arity_cases)
    }
  end
end
