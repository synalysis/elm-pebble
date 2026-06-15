defmodule Elmc.Backend.CCodegen do
  @moduledoc """
  Writes C source files from lowered IR.

  Internal codegen helpers live under `Elmc.Backend.CCodegen.*` and are reached via
  `Elmc.Backend.CCodegen.Host` during compilation.
  """

  alias Elmc.Backend.CCodegen.ProjectWriter

  @spec write_project(ElmEx.IR.t(), String.t(), Elmc.Backend.CCodegen.Types.codegen_opts()) ::
          :ok | {:error, Elmc.Backend.CCodegen.Types.file_error()}
  defdelegate write_project(ir, out_dir, opts \\ %{}), to: ProjectWriter, as: :write

  @spec write_project_multi(ElmEx.IR.t(), String.t(), Elmc.Backend.CCodegen.Types.codegen_opts()) ::
          :ok | {:error, Elmc.Backend.CCodegen.Types.file_error()}
  defdelegate write_project_multi(ir, out_dir, opts \\ %{}), to: ProjectWriter, as: :write_multi
end
