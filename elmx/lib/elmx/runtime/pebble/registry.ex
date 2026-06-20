defmodule Elmx.Runtime.Pebble.Registry do
  @moduledoc """
  Handler table for `elmx_*` Pebble platform runtime calls.

  Used by `Elmx.Runtime.Generator`, `Pebble.runtime_dispatch/2`, and IDE-stepped apps.
  Several `elmx_core_*` symbols mirror `Intrinsics.Registry` so `Generator.compile_call/2`
  can resolve them without falling through. UI/http/dispatch handlers use `wrap_modules` for
  splat argument lists.
  """

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Pebble.Registry.{
    Cmd,
    Companion,
    Core,
    Device,
    Http,
    Json,
    Subscription,
    Task,
    Time,
    Ui
  }
  alias Elmx.Types

  @type handler :: Handler.t()

  @wrap_modules [
    Elmx.Runtime.Pebble.Dispatch,
    Elmx.Runtime.Http
  ]

  @spec handlers() :: %{String.t() => handler()}
  def handlers, do: handlers_map()

  @spec symbols() :: [String.t()]
  def symbols, do: handlers() |> Map.keys() |> Enum.sort()

  @spec known?(String.t()) :: boolean()
  def known?(name) when is_binary(name), do: Map.has_key?(handlers(), name)

  @spec compile_call(String.t(), [iodata()]) :: {:ok, String.t()} | :error
  def compile_call(name, arg_codes) when is_binary(name) and is_list(arg_codes) do
    case Map.get(handlers(), name) do
      nil -> :error
      handler -> {:ok, Handler.compile(handler, arg_codes, wrap_modules: @wrap_modules)}
    end
  end

  @spec apply(String.t(), Types.registry_args()) :: Types.runtime_dispatch_result()
  def apply(name, args) when is_binary(name) and is_list(args) do
    case Map.get(handlers(), name) do
      nil ->
        if Dispatch.kernel_runtime_function?(name) do
          Dispatch.kernel_runtime_stub(name, args)
        else
          raise ArgumentError, "unsupported elmx runtime call #{name}"
        end

      handler ->
        Handler.invoke(handler, args, wrap_modules: @wrap_modules)
    end
  end

  @spec handlers_map() :: %{String.t() => handler()}
  defp handlers_map do
    %{}
    |> Map.merge(Http.handlers())
    |> Map.merge(Ui.handlers())
    |> Map.merge(Core.handlers())
    |> Map.merge(Task.handlers())
    |> Map.merge(Time.handlers())
    |> Map.merge(Cmd.handlers())
    |> Map.merge(Subscription.handlers())
    |> Map.merge(Device.handlers())
    |> Map.merge(Companion.handlers())
    |> Map.merge(Json.handlers())
  end
end
