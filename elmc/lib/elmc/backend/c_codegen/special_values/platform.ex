defmodule Elmc.Backend.CCodegen.SpecialValues.Platform do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()


  def special_value_from_target("Platform.Cmd.none", _args),
    do: Helpers.command_kind_expr(:none)

  def special_value_from_target("Platform.Sub.none", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Pebble.Platform.application", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Platform.worker", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Pebble.Platform.watchface", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Pebble.Platform.displayShapeIsRound", [shape]),
    do: Helpers.platform_union_is_constructor(shape, "Round", 2, "PBL_ROUND")

  def special_value_from_target("Pebble.Platform.colorCapabilityIsColor", [capability]),
    do: Helpers.platform_union_is_constructor(capability, "Color", 2, "PBL_COLOR")

  # --- Partial application: zero-arg references to known stdlib functions ---
  # When a qualified call is used as a value (0 args), wrap it in a lambda.

  def special_value_from_target(_target, _args), do: nil
end
