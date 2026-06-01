defmodule Elmx.Runtime.Loader do
  @moduledoc """
  In-memory BEAM compile for generated Elixir sources (no File.read on hot path).
  """

  alias Elmx.CompileResult

  @type compile_error ::
          {:compile_failed, String.t(), term()}
          | {:missing_module_source, String.t()}

  @spec compile_modules([CompileResult.compiled_module()]) ::
          {:ok, [CompileResult.compiled_module()]} | {:error, compile_error()}
  def compile_modules(modules) when is_list(modules) do
    Enum.reduce_while(modules, {:ok, []}, fn mod, {:ok, acc} ->
      case compile_module(mod) do
        {:ok, compiled} -> {:cont, {:ok, [compiled | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, mods} -> {:ok, Enum.reverse(mods)}
      err -> err
    end
  end

  @spec compile_module(CompileResult.compiled_module()) ::
          {:ok, CompileResult.compiled_module()} | {:error, compile_error()}
  def compile_module(%{name: name, source: source, virtual_path: virtual_path} = mod)
      when is_binary(name) and is_binary(source) and is_binary(virtual_path) do
    module_atom = module_atom(name)

    purge(module_atom)

    try do
      case Code.compile_string(source, virtual_path) do
        [{loaded, _}] ->
          {:ok, Map.put(mod, :module, loaded)}

        other ->
          {:error, {:compile_failed, name, other}}
      end
    rescue
      e in [CompileError, SyntaxError, TokenMissingError] ->
        detail = %{
          message: Exception.message(e),
          file: Map.get(e, :file),
          line: Map.get(e, :line),
          description: Map.get(e, :description)
        }

        {:error, {:compile_failed, name, detail}}
    end
  end

  @spec purge(module()) :: :ok
  def purge(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      :code.purge(module)
      :code.delete(module)
    end

    :ok
  end

  defp module_atom(name) when is_binary(name) do
    name |> String.split(".") |> Module.concat()
  end
end
