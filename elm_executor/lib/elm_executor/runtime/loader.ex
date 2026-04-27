defmodule ElmExecutor.Runtime.Loader do
  @moduledoc """
  Dynamic loader for compiled elm_executor modules with deterministic module naming.
  """

  @spec load_from_dir(String.t(), String.t()) :: {:ok, module()} | {:error, term()}
  def load_from_dir(out_dir, entry_module) when is_binary(out_dir) and is_binary(entry_module) do
    with {:ok, manifest} <- load_manifest(out_dir),
         :ok <- validate_manifest_entry(manifest, entry_module) do
      do_load_module(out_dir, manifest["generated_module"])
    end
  end

  @spec load_manifest(String.t()) :: {:ok, map()} | {:error, term()}
  def load_manifest(out_dir) when is_binary(out_dir) do
    manifest_path = Path.join([out_dir, "elixir", "elm_executor_manifest.json"])

    with true <- File.exists?(manifest_path),
         {:ok, content} <- File.read(manifest_path),
         {:ok, decoded} <- Jason.decode(content) do
      {:ok, decoded}
    else
      false -> {:error, {:missing_manifest, manifest_path}}
      {:error, _} = err -> err
    end
  end

  @spec validate_manifest_entry(term(), term()) :: term()
  defp validate_manifest_entry(manifest, entry_module)
       when is_map(manifest) and is_binary(entry_module) do
    if manifest["entry_module"] == entry_module do
      :ok
    else
      {:error, {:entry_module_mismatch, manifest["entry_module"], entry_module}}
    end
  end

  @spec do_load_module(term(), term()) :: term()
  defp do_load_module(out_dir, module_name) when is_binary(module_name) do
    module_file = Path.join([out_dir, "elixir", Macro.underscore(module_name) <> ".ex"])
    module_atom =
      module_name
      |> String.split(".")
      |> Module.concat()

    if Code.ensure_loaded?(module_atom) do
      :code.purge(module_atom)
      :code.delete(module_atom)
    end

    with true <- File.exists?(module_file),
         {:ok, source} <- File.read(module_file),
         [{loaded_module, _bin}] <- Code.compile_string(source, module_file) do
      {:ok, loaded_module}
    else
      false -> {:error, {:missing_compiled_module, module_file}}
      {:error, _} = err -> err
      other -> {:error, {:module_load_failed, other}}
    end
  end

  @spec purge(module()) :: :ok
  def purge(module) when is_atom(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end
end
