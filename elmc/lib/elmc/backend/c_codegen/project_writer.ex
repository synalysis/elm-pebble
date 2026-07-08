defmodule Elmc.Backend.CCodegen.ProjectWriter do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.BuildArtifacts
  alias Elmc.Backend.CCodegen.GeneratedSource
  alias Elmc.Backend.CCodegen.PerModuleArtifacts
  alias Elmc.Backend.CCodegen.StackEstimate
  alias Elmc.Backend.CCodegen.Types

  @spec write(IR.t(), String.t(), Types.codegen_opts()) :: :ok | {:error, Types.file_error()}
  def write(%IR{} = ir, out_dir, opts \\ %{}) do
    opts = normalize_codegen_opts(opts)
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), GeneratedSource.header(ir, opts)),
         generated_source <- GeneratedSource.source(ir, opts),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), generated_source),
         :ok <- write_stack_report(out_dir, ir, generated_source),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), BuildArtifacts.host_harness()),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), BuildArtifacts.cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), BuildArtifacts.makefile()),
         :ok <- Elmc.Backend.Bytecode.ProjectWriter.maybe_write(ir, out_dir, opts) do
      :ok
    end
  end

  @spec write_multi(IR.t(), String.t(), Types.codegen_opts()) :: :ok | {:error, Types.file_error()}
  def write_multi(%IR{} = ir, out_dir, opts \\ %{}) do
    opts = normalize_codegen_opts(opts)
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- PerModuleArtifacts.write_headers(ir, c_dir),
         :ok <- PerModuleArtifacts.write_sources(ir, c_dir, opts),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), GeneratedSource.header(ir, opts)),
         generated_source <- GeneratedSource.source(ir, opts),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), generated_source),
         :ok <- write_stack_report(out_dir, ir, generated_source),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), BuildArtifacts.host_harness()),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), BuildArtifacts.cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), BuildArtifacts.makefile()),
         :ok <- File.write(Path.join(out_dir, "link_manifest.json"), PerModuleArtifacts.link_manifest(ir)),
         :ok <- Elmc.Backend.Bytecode.ProjectWriter.maybe_write(ir, out_dir, opts) do
      :ok
    end
  end

  defp write_stack_report(out_dir, ir, generated_source) do
    report =
      ir
      |> StackEstimate.report(generated_source)
      |> Jason.encode!(pretty: true)

    File.write(Path.join(out_dir, "elmc_stack_report.json"), report)
  end

  defp normalize_codegen_opts(opts) when is_list(opts) do
    opts |> Map.new() |> normalize_codegen_opts()
  end

  defp normalize_codegen_opts(opts) when is_map(opts) do
    cond do
      Map.has_key?(opts, :prune_native_wrappers) -> opts
      pebble_production_build?(opts) -> Map.put(opts, :prune_native_wrappers, true)
      true -> opts
    end
  end

  defp pebble_production_build?(opts) do
    opts[:pebble_int32] == true or opts[:prune_runtime] == true
  end
end
