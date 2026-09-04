defmodule ElmEx.Typesys.Check do
  @moduledoc """
  Public Elm 0.19 typesys entry: canonicalize, infer, pattern nitpick.
  """

  alias ElmEx.Frontend.Project
  alias ElmEx.Typesys.{Canonicalize, Diagnostic, Env, Infer, Overlay, Pattern}

  @spec run(Project.t()) :: {Project.t(), [map()]}
  def run(%Project{} = project) do
    {project, overlay} = Overlay.attach(project)
    env = Env.build(project)

    {app_modules, dep_modules} =
      Enum.split_with(project.modules, &Canonicalize.application_module?(project, &1))

    env = Env.install_unannotated_exports(env, project.modules)
    {env, canon_diags} = Canonicalize.run(project, env)
    {app_modules, infer_diags, env} = Infer.run(app_modules, env)
    {app_modules, pattern_diags} = Pattern.nitpick(app_modules, env)

    modules =
      (app_modules ++ dep_modules)
      |> Overlay.strip(overlay)

    diagnostics =
      (canon_diags ++ infer_diags ++ pattern_diags)
      |> Enum.uniq_by(&{&1.code, &1.module, &1.function, &1.name, &1.message})

    {%{project | modules: modules}, diagnostics}
  end

  @spec diagnostics(Project.t()) :: [map()]
  def diagnostics(%Project{} = project) do
    {_project, diags} = run(project)
    Enum.map(diags, &Diagnostic.to_bridge/1)
  end

  @spec annotate(Project.t()) :: {Project.t(), [map()]}
  def annotate(%Project{} = project) do
    {project, diags} = run(project)
    {project, Enum.map(diags, &Diagnostic.to_bridge/1)}
  end
end
