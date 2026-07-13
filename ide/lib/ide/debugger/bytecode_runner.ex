defmodule Ide.Debugger.BytecodeRunner do
  @moduledoc """
  Run lowered plan bytecode from `.elmc-build/bytecode` for debugger smoke tests.

  Full stepped debugging still uses the Pebble emulator; this module provides
  optional in-process interpretation when bytecode artifacts are present.
  """

  alias Elmc.Backend.Bytecode.{Artifacts, ManifestProgram, Runtime}
  alias Ide.Debugger.BytecodeTypes

  @type program :: ManifestProgram.t()
  @type summary :: BytecodeTypes.summary()
  @type function_entry :: BytecodeTypes.function_entry()
  @type load_error :: BytecodeTypes.bytecode_load_error()

  @spec available?(String.t()) :: boolean()
  def available?(build_dir) when is_binary(build_dir) do
    case Artifacts.read_summary(build_dir) do
      %{available: true} -> true
      _ -> false
    end
  end

  @spec summary(String.t()) :: summary()
  def summary(build_dir) when is_binary(build_dir), do: Artifacts.read_summary(build_dir)

  @spec load(String.t(), keyword()) :: {:ok, program()} | {:error, load_error()}
  def load(build_dir, opts \\ []) when is_binary(build_dir) do
    linked? = Keyword.get(opts, :linked, true)
    entry = Keyword.get(opts, :entry)

    cond do
      linked? and is_tuple(entry) ->
        ManifestProgram.load_linked(build_dir, entry)

      true ->
        ManifestProgram.load(build_dir)
    end
  end

  @spec run(String.t(), {String.t(), String.t()}, keyword()) ::
          {:ok, Runtime.value()} | {:error, load_error()}
  def run(build_dir, target, opts \\ []) when is_binary(build_dir) do
    with {:ok, program} <- load(build_dir, Keyword.put(opts, :entry, target)) do
      ManifestProgram.run(program, target, opts)
    end
  end

  @spec functions(String.t()) :: [function_entry()]
  def functions(build_dir) when is_binary(build_dir) do
    case ManifestProgram.load(build_dir) do
      {:ok, program} -> ManifestProgram.function_entries(program)
      _ -> []
    end
  end
end
