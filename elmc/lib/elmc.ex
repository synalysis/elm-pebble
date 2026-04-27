defmodule Elmc do
  @moduledoc """
  Public API for the Elm-to-C compiler.
  """

  alias Elmc.Backend.CCodegen
  alias Elmc.Backend.Pebble
  alias Elmc.Backend.Ports
  alias Elmc.Backend.Worker
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.DeadCode
  alias ElmEx.IR.Lowerer
  alias Elmc.Runtime.Generator

  @type compile_options :: %{
          optional(:entry_module) => String.t(),
          optional(:out_dir) => String.t(),
          optional(:runtime_dir) => String.t(),
          optional(:strip_dead_code) => boolean(),
          optional(:prune_runtime) => boolean()
        }

  @doc """
  Typechecks and extracts frontend metadata for an Elm project.
  """
  @spec check(String.t()) :: {:ok, map()} | {:error, map()}
  def check(project_dir) do
    Bridge.load_project(project_dir)
  end

  @doc """
  Compiles a supported Elm subset into C artifacts.
  """
  @spec compile(String.t(), compile_options()) :: {:ok, map()} | {:error, map()}
  def compile(project_dir, opts \\ %{}) do
    entry_module = opts[:entry_module] || "Main"

    with {:ok, project} <- Bridge.load_project(project_dir),
         {:ok, ir0} <- Lowerer.lower_project(project),
         ir <- maybe_strip_dead_code(ir0, entry_module, opts[:strip_dead_code]),
         :ok <- Ports.write_port_headers(ir, opts[:out_dir] || "build"),
         :ok <-
           Pebble.write_pebble_shim(
             ir,
             opts[:out_dir] || "build",
             entry_module
           ),
         :ok <-
           Worker.write_worker_adapter(
             ir,
             opts[:out_dir] || "build",
             entry_module
           ),
         :ok <-
           CCodegen.write_project(
             ir,
             opts[:out_dir] || "build"
           ),
         :ok <-
           Generator.write_runtime(
             opts[:runtime_dir] || Path.join(opts[:out_dir] || "build", "runtime"),
             prune_from_dir: if(opts[:prune_runtime], do: opts[:out_dir] || "build", else: nil)
           ) do
      {:ok, %{project: project, ir: ir}}
    end
  end

  @spec maybe_strip_dead_code(ElmEx.IR.t(), String.t(), boolean() | nil) :: ElmEx.IR.t()
  defp maybe_strip_dead_code(ir, _entry_module, false), do: ir
  defp maybe_strip_dead_code(ir, entry_module, _), do: DeadCode.strip(ir, entry_module)
end
