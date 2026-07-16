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
    Stdlib.Set,
    Stdlib.WebKernel
  }

  alias Elmc.Backend.CCodegen.SpecialValues.Stdlib.String, as: StdlibString
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb

  @pebble_only_handlers [Draw, Cmd, Events, Phone]

  @shared_handlers [
    Platform,
    WebKernel,
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

  @handlers @pebble_only_handlers ++ @shared_handlers

  @spec special_value_from_target(String.t(), Types.special_value_args() | nil) ::
          Types.special_value_result()
  def special_value_from_target(target, args \\ [])

  def special_value_from_target(target, nil) when is_binary(target),
    do: special_value_from_target(target, [])

  def special_value_from_target(target, args) when is_binary(target) and is_list(args) do
    normalized = Core.normalize_special_target(target)

    case Core.operator_call_rewrite(normalized, args) do
      nil -> dispatch_handlers(normalized, args)
      expr -> expr
    end
  end

  def special_value_from_target(_target, _args), do: nil

  @spec dispatch_handlers(String.t(), Types.special_value_args()) :: Types.special_value_result()
  defp dispatch_handlers(target, args) do
    opts = Process.get(:elmc_codegen_opts, %{})

    handlers_for(opts)
    |> Enum.find_value(fn handler ->
      case handler.special_value_from_target(target, args) do
        nil -> nil
        expr -> expr
      end
    end)
  end

  defp handlers_for(opts) do
    if PlatformWeb.web_target?(opts) do
      @shared_handlers
    else
      @handlers
    end
  end

  @spec handlers() :: [module()]
  def handlers, do: @handlers
end
