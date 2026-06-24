defmodule Elmc.Backend.CCodegen.SpecialValues.Dispatcher do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.{
    Cmd,
    Core,
    Draw,
    Events,
    Phone,
    Platform,
    Stdlib.Array,
    Stdlib.Basics,
    Stdlib.Dict,
    Stdlib.Effects,
    Stdlib.Json,
    Stdlib.List,
    Stdlib.MaybeResult,
    Stdlib.Set
  }

  alias Elmc.Backend.CCodegen.SpecialValues.Stdlib.String, as: StdlibString
  alias Elmc.Backend.CCodegen.Types

  @handlers [
    Draw,
    Cmd,
    Events,
    Phone,
    Platform,
    List,
    Dict,
    Set,
    Array,
    StdlibString,
    Basics,
    MaybeResult,
    Json,
    Effects,
    Core
  ]

  @spec special_value_from_target(String.t(), Types.special_value_args() | nil) ::
          Types.special_value_result()
  def special_value_from_target(target, args \\ [])

  def special_value_from_target(target, nil) when is_binary(target),
    do: special_value_from_target(target, [])

  def special_value_from_target(target, args) when is_binary(target) and is_list(args) do
    case dispatch_handlers(target, args) do
      nil ->
        normalized = Core.normalize_special_target(target)

        if normalized == target do
          nil
        else
          special_value_from_target(normalized, args)
        end

      expr ->
        expr
    end
  end

  def special_value_from_target(_target, _args), do: nil

  @spec dispatch_handlers(String.t(), Types.special_value_args()) :: Types.special_value_result()
  defp dispatch_handlers(target, args) do
    Enum.find_value(@handlers, fn handler ->
      case handler.special_value_from_target(target, args) do
        nil -> nil
        expr -> expr
      end
    end)
  end

  @spec handlers() :: [module()]
  def handlers, do: @handlers
end
