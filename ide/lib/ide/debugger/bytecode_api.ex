defmodule Ide.Debugger.BytecodeApi do
  @moduledoc """
  Debugger-facing bytecode manifest inspection and smoke execution.
  """

  alias Ide.Debugger.BytecodeRunner
  alias Ide.Projects
  alias Ide.Projects.Project

  @spec build_dir(Project.t()) :: String.t()
  def build_dir(%Project{} = project) do
    Path.join([Projects.project_workspace_path(project), "watch", ".elmc-build"])
  end

  @spec summary(Project.t()) :: map()
  def summary(%Project{} = project), do: BytecodeRunner.summary(build_dir(project))

  @spec functions(Project.t()) :: [map()]
  def functions(%Project{} = project), do: BytecodeRunner.functions(build_dir(project))

  @spec available?(Project.t()) :: boolean()
  def available?(%Project{} = project), do: BytecodeRunner.available?(build_dir(project))

  @spec run(Project.t(), {String.t(), String.t()}, keyword()) ::
          {:ok, term()} | {:error, term()}
  def run(%Project{} = project, target, opts \\ []) do
    BytecodeRunner.run(build_dir(project), target, opts)
  end

  @spec run_smoke(Project.t(), {String.t(), String.t()}) :: {:ok, term()} | {:error, term()}
  def run_smoke(%Project{} = project, {module, name} = target) do
    params = default_params(manifest_entry(project, module, name))
    run(project, target, params: params)
  end

  @spec manifest_entry(Project.t(), String.t(), String.t()) :: map() | nil
  def manifest_entry(%Project{} = project, module, name) do
    project
    |> functions()
    |> Enum.find(fn entry ->
      Map.get(entry, "module") == module and Map.get(entry, "name") == name
    end)
  end

  @spec default_params(map() | nil) :: [term()]
  def default_params(nil), do: []

  def default_params(%{"params" => params}) when is_list(params) do
    Enum.map(params, &default_param/1)
  end

  def default_params(_), do: []

  defp default_param(name) when is_binary(name) do
    cond do
      String.downcase(name) == "model" -> {:record, [0, nil]}
      String.ends_with?(name, "Model") -> {:record, [0, nil]}
      true -> 0
    end
  end

  defp default_param(_), do: 0
end
