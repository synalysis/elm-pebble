defmodule Elmx do
  @moduledoc """
  Elm-to-Elixir compiler for debugger execution and optional disk export.
  """

  alias Elmx.Backend.ElixirCodegen
  alias Elmx.Backend.Pebble
  alias Elmx.CompileResult
  alias Elmx.IRDigest
  alias Elmx.Runtime.Loader
  alias Elmx.Runtime.ModuleRegistry
  alias Elmx.Types
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.DeadCode
  alias ElmEx.IR.Lowerer

  @type compile_options :: Types.compile_options()

  @doc """
  Typechecks and loads an Elm project via `elm_ex` bridge.
  """
  @spec check(String.t()) :: {:ok, map()} | {:error, map()}
  def check(project_dir), do: Bridge.load_project(project_dir)

  @doc """
  Compiles IR to Elixir on disk under `out_dir/elixir/`.
  """
  @spec compile(String.t(), compile_options()) ::
          {:ok, %{project: map(), ir: ElmEx.IR.t(), out_dir: String.t()}}
          | {:error, term()}
  def compile(project_dir, opts \\ %{}) do
    entry_module = opts[:entry_module] || "Main"
    out_dir = opts[:out_dir] || "build"

    source_overrides = Map.get(opts, :source_overrides, %{})

    with {:ok, project} <- Bridge.load_project_from_sources(project_dir, source_overrides),
         {:ok, ir0} <- Lowerer.lower_project(project) do
      ir = maybe_strip_dead_code(ir0, entry_module, opts[:strip_dead_code])
      ir_sha256 = IRDigest.sha256(ir)

      emit_opts = %{
        entry_module: entry_module,
        mode: opts[:mode] || :library,
        ir_sha256: ir_sha256,
        user_module_names: user_module_names(project)
      }

      with :ok <- Pebble.write_pebble_shim(ir, out_dir, entry_module),
           :ok <- ElixirCodegen.write_project(ir, out_dir, emit_opts) do
        {:ok, %{project: project, ir: ir, out_dir: out_dir}}
      end
    end
  end

  @doc """
  Compiles Elm → Elixir → BEAM entirely in memory for IDE hot-reload.
  """
  @spec compile_in_memory(String.t(), compile_options()) :: {:ok, CompileResult.t()} | {:error, term()}
  def compile_in_memory(project_dir, opts \\ %{}) when is_binary(project_dir) do
    _ = Application.ensure_all_started(:elmx)
    entry_module = opts[:entry_module] || "Main"
    revision = opts[:revision] || ir_revision_key(project_dir, opts)

    source_overrides = Map.get(opts, :source_overrides, %{})

    with {:ok, project} <- Bridge.load_project_from_sources(project_dir, source_overrides),
         {:ok, ir0} <- Lowerer.lower_project(project),
         ir <- maybe_strip_dead_code(ir0, entry_module, opts[:strip_dead_code]),
         ir_sha256 <- IRDigest.sha256(ir),
         emit_opts <- %{
           entry_module: entry_module,
           mode: opts[:mode] || :ide_runtime,
           ir_sha256: ir_sha256,
           user_module_names: user_module_names(project),
           ir_full: ir0
         },
         {:ok, modules} <- ElixirCodegen.emit_project(ir, emit_opts),
         {:ok, compiled_modules} <- Loader.compile_modules(modules),
         entry <- entry_compiled_module(compiled_modules, emit_opts) do
      if revision do
        ModuleRegistry.put(revision, entry.module)
      end

      manifest = %{
        "compiler" => "elmx",
        "contract" => "elmx.runtime_executor.v1",
        "entry_module" => entry_module,
        "generated_module" => entry.name,
        "ir_sha256" => ir_sha256,
        "elmx_version" => "0.1.0",
        "revision" => revision
      }

      {:ok,
       %CompileResult{
         entry_module: entry.module,
         entry_module_name: entry_module,
         generated_module_name: entry.name,
         modules: compiled_modules,
         manifest: manifest,
         ir: ir,
         diagnostics: []
       }}
    end
  end

  @doc """
  Resolves a previously registered module for a revision key.
  """
  @spec module_for_revision(String.t()) :: module() | nil
  def module_for_revision(revision) when is_binary(revision),
    do: ModuleRegistry.get(revision)

  @spec maybe_strip_dead_code(ElmEx.IR.t(), String.t(), boolean() | nil) :: ElmEx.IR.t()
  @doc false
  @spec user_module_names(map()) :: [String.t()]
  def user_module_names(%{project_dir: project_dir, modules: modules}) do
    src_root = Path.expand(Path.join(project_dir, "src"))

    Enum.flat_map(modules, fn mod ->
      case mod.path do
        path when is_binary(path) ->
          if String.starts_with?(Path.expand(path), src_root <> "/") or
               Path.expand(path) == Path.join(src_root, Path.basename(path)) do
            [mod.name]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  defp maybe_strip_dead_code(ir, _entry, false), do: ir

  defp maybe_strip_dead_code(ir, entry, _) do
    roots = Elmx.Backend.MainProgram.dead_code_roots(ir, entry)
    DeadCode.strip(ir, entry, roots: roots)
  end

  defp entry_compiled_module(modules, %{ir_sha256: hash, entry_module: entry}) do
    expected = ElixirCodegen.generated_module_name(entry, hash)

    case Enum.find(modules, &(&1.name == expected)) do
      %{} = mod -> mod
      _ -> List.first(modules)
    end
  end

  defp ir_revision_key(_project_dir, %{revision: rev}) when is_binary(rev) and rev != "", do: rev
  defp ir_revision_key(project_dir, _opts), do: "project:" <> project_dir
end
