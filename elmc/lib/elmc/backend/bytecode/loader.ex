defmodule Elmc.Backend.Bytecode.Loader do
  @moduledoc """
  Load `.elmcbc` artifacts emitted by `Bytecode.ProjectWriter`.
  """

  alias Elmc.Backend.Bytecode.{Lower, ManifestProgram, Program, Runtime}

  @type manifest :: %{
          optional(String.t()) => term()
        }

  @spec load_manifest(String.t()) :: {:ok, manifest()} | {:error, term()}
  def load_manifest(path) when is_binary(path) do
    with {:ok, bin} <- File.read(path),
         {:ok, decoded} <- Jason.decode(bin) do
      {:ok, decoded}
    end
  end

  @spec run_manifest_entry(String.t(), {String.t(), String.t()}, keyword()) ::
          {:ok, Runtime.value()} | {:error, term()}
  def run_manifest_entry(build_dir, {_module, _name} = target, opts \\ []) when is_binary(build_dir) do
    if Keyword.get(opts, :linked, true) do
      with {:ok, program} <- ManifestProgram.load_linked(build_dir, target) do
        ManifestProgram.run(program, target, opts)
      end
    else
      run_manifest_entry_unlinked(build_dir, target, opts)
    end
  end

  defp run_manifest_entry_unlinked(build_dir, {module, name}, opts) do
    manifest_path = Path.join(build_dir, "bytecode/elmc_bytecode.manifest.json")

    with {:ok, manifest} <- load_manifest(manifest_path),
         {:ok, entry} <- fetch_entry(manifest, module, name),
         {:ok, section} <- load_section(build_dir, entry),
         {:ok, result} <- Runtime.run_section(section, Keyword.merge(opts, entry_opts(entry, section))) do
      {:ok, result}
    end
  end

  @spec link_and_run(map(), {String.t(), String.t()}, keyword()) ::
          {:ok, Runtime.value()} | {:error, term()}
  def link_and_run(decl_map, {_module, _name} = root, opts \\ []) when is_map(decl_map) do
    case Program.link(decl_map, root, opts) do
      {:ok, program} -> Program.run(program, opts)
      other -> other
    end
  end

  defp fetch_entry(%{"functions" => functions}, module, name) do
    case Enum.find(functions, &(&1["module"] == module and &1["name"] == name)) do
      %{} = entry -> {:ok, entry}
      _ -> {:error, :missing_manifest_entry}
    end
  end

  @spec load_section(String.t(), map()) :: {:ok, Lower.section()} | {:error, term()}
  def load_section(build_dir, %{"file" => file} = entry) do
    path = Path.join([build_dir, "bytecode", file])

    with {:ok, bin} <- File.read(path) do
      section = Lower.decode_section(bin)
      {:ok, Map.put(section, :entry, entry)}
    end
  end

  defp entry_opts(%{"module" => module, "name" => name} = _entry, section) do
    [
      fn_table: Map.get(section, :fn_table, []),
      block_ips: Map.get(section, :block_ips, %{}),
      plan_key: {module, name}
    ]
  end

  defp entry_opts(_entry, section) do
    [
      fn_table: Map.get(section, :fn_table, []),
      block_ips: Map.get(section, :block_ips, %{}),
      plan_key: {:Main, "anon"}
    ]
  end
end
