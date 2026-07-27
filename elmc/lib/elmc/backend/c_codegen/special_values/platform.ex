defmodule Elmc.Backend.CCodegen.SpecialValues.Platform do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()

  def special_value_from_target("Platform.Cmd.none", _args),
    do: %{op: :cmd_none}

  def special_value_from_target("Platform.Sub.none", _args),
    do: %{op: :sub_none}

  def special_value_from_target("Platform.worker", [impl]) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) do
      %{op: :browser_cmd, kind: %{op: :int_literal, value: 8}, params: [impl]}
    else
      %{op: :int_literal, value: 0}
    end
  end

  def special_value_from_target("Platform.worker", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target("Pebble.Platform.application", _args) do
    if pebble_platform_allowed?(), do: %{op: :int_literal, value: 0}, else: nil
  end

  def special_value_from_target("Pebble.Platform.watchface", _args) do
    if pebble_platform_allowed?(), do: %{op: :int_literal, value: 0}, else: nil
  end

  def special_value_from_target("Pebble.Platform.displayShapeIsRound", [shape]) do
    if pebble_platform_allowed?() do
      Helpers.platform_union_is_constructor(shape, "Round", 2, "PBL_ROUND")
    else
      nil
    end
  end

  def special_value_from_target("Pebble.Platform.colorCapabilityIsColor", [capability]) do
    if pebble_platform_allowed?() do
      Helpers.platform_union_is_constructor(capability, "Color", 2, "PBL_COLOR")
    else
      nil
    end
  end

  def special_value_from_target(_target, _args), do: nil

  @spec pebble_platform_allowed?() :: boolean()

  defp pebble_platform_allowed? do
    not PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{}))
  end
end
