defmodule ElmEx do
  @moduledoc """
  Elm parser, AST, and IR frontend.

  ElmEx provides a backend-agnostic Elm language frontend that can be used
  to build compilers targeting different platforms (C, WASM, etc.).

  ## Usage

      {:ok, project} = ElmEx.Frontend.Bridge.load_project("path/to/elm/project")
      {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)

  The resulting IR can then be passed to any backend (e.g. `Elmc` for C codegen).
  """

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @doc """
  Parses and lowers an Elm project, returning the IR.
  """
  @spec parse_and_lower(String.t()) :: {:ok, ElmEx.IR.t()} | {:error, map()}
  def parse_and_lower(project_dir) do
    with {:ok, project} <- Bridge.load_project(project_dir),
         {:ok, ir} <- Lowerer.lower_project(project) do
      {:ok, ir}
    end
  end
end
