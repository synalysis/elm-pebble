defmodule Elmc.Backend.CCodegen.ProjectWriter do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.BuildArtifacts
  alias Elmc.Backend.CCodegen.GeneratedSource
  alias Elmc.Backend.CCodegen.PerModuleArtifacts
  alias Elmc.Backend.CCodegen.Types

  @spec write(IR.t(), String.t(), Types.codegen_opts()) :: :ok | {:error, Types.file_error()}
  def write(%IR{} = ir, out_dir, opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), GeneratedSource.header(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), GeneratedSource.source(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), BuildArtifacts.host_harness()),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), BuildArtifacts.cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), BuildArtifacts.makefile()) do
      :ok
    end
  end

  @spec write_multi(IR.t(), String.t(), Types.codegen_opts()) :: :ok | {:error, Types.file_error()}
  def write_multi(%IR{} = ir, out_dir, opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")

    with :ok <- File.mkdir_p(c_dir),
         :ok <- PerModuleArtifacts.write_headers(ir, c_dir),
         :ok <- PerModuleArtifacts.write_sources(ir, c_dir),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.h"), GeneratedSource.header(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "elmc_generated.c"), GeneratedSource.source(ir, opts)),
         :ok <- File.write(Path.join(c_dir, "host_harness.c"), BuildArtifacts.host_harness()),
         :ok <- File.write(Path.join(out_dir, "CMakeLists.txt"), BuildArtifacts.cmake()),
         :ok <- File.write(Path.join(out_dir, "Makefile"), BuildArtifacts.makefile()),
         :ok <- File.write(Path.join(out_dir, "link_manifest.json"), PerModuleArtifacts.link_manifest(ir)) do
      :ok
    end
  end
end
