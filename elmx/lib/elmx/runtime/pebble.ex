defmodule Elmx.Runtime.Pebble do
  @moduledoc """
  Pebble platform lowering and runtime stubs for generated Elixir code.
  """

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Pebble.Registry
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Types

  @spec rewrite_qualified_call(String.t(), Types.ir_arg_list()) :: Types.rewrite_result()
  def rewrite_qualified_call(target, args), do: SpecialValues.rewrite(target, args)

  @spec special_call?(String.t()) :: boolean()
  def special_call?(target) when is_binary(target) do
    String.starts_with?(target, "Pebble.") or String.starts_with?(target, "Platform.") or
      String.starts_with?(target, "Companion.") or
      String.starts_with?(target, "Elm.Kernel.PebbleWatch.") or
      String.starts_with?(target, "Elm.Kernel.PebblePhone.")
  end

  @spec special_call_code(String.t()) :: {:ok, String.t()} | :error
  def special_call_code(_target), do: :error

  @spec runtime_call(String.t(), iodata()) :: String.t()
  def runtime_call(function, arg_code) do
    "#{CodegenRefs.pebble()}.runtime_dispatch(#{inspect(function)}, [#{IO.iodata_to_binary(arg_code)}])"
  end

  @spec runtime_dispatch(String.t(), Types.registry_args()) :: Types.runtime_dispatch_result()
  def runtime_dispatch(function, args) when is_binary(function) and is_list(args) do
    if String.starts_with?(function, "elmc_") do
      case Generator.apply(function, args) do
        {:ok, value} -> value
        :error -> raise ArgumentError, "unsupported elmc runtime call #{function}"
      end
    else
      Registry.apply(function, args)
    end
  end
end
