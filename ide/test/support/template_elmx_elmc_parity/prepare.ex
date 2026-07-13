defmodule Ide.Test.TemplateElmxElmcParity.Prepare do
  @moduledoc false

  alias ElmEx.Frontend.Bridge
  alias ElmEx.Frontend.Project
  alias Ide.Debugger.CompileContract
  alias Ide.Test.TemplateElmxElmcParity.ElmcHostHarness
  alias Ide.Test.TemplateElmxElmcParity.ElmcRunner
  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan
  alias Ide.Test.TemplateElmxElmcParity.Scaffold
  alias Ide.Test.TemplateElmxElmcParity.Types, as: ParityTypes

  @cache_key {__MODULE__, :prepared}

  @type t :: %{
          required(:template_key) => String.t(),
          required(:project_dir) => String.t(),
          optional(:project) => Project.t() | nil,
          optional(:contract) => CompileContract.contract() | nil,
          required(:plan) => ExecutionPlan.t(),
          required(:elmx) => ParityTypes.elmx_compile_bundle(),
          required(:elmc) => ParityTypes.elmc_compile_bundle()
        }

  @spec fetch(String.t()) :: t() | nil
  def fetch(template_key) when is_binary(template_key) do
    case Process.get(@cache_key, %{}) do
      %{^template_key => %{} = prepared} -> prepared
      _ -> nil
    end
  end

  @spec release!(String.t()) :: :ok
  def release!(template_key) when is_binary(template_key) do
    case fetch(template_key) do
      nil ->
        :ok

      %{project_dir: project_dir, elmc: %{out_dir: out_dir}, owned_project_dir?: true} ->
        stop_elmc!(out_dir)
        File.rm_rf!(project_dir)
        File.rm_rf!(out_dir)
        put_cached(Map.delete(Process.get(@cache_key, %{}), template_key))
        :ok

      %{elmc: %{out_dir: out_dir}} ->
        stop_elmc!(out_dir)
        File.rm_rf!(out_dir)
        put_cached(Map.delete(Process.get(@cache_key, %{}), template_key))
        :ok
    end
  end

  @spec release_all!() :: :ok
  def release_all! do
    Process.get(@cache_key, %{})
    |> Map.keys()
    |> Enum.each(&release!/1)

    ElmcHostHarness.cleanup_stale_harnesses!()
    :ok
  end

  @spec prepare!(String.t(), keyword()) :: {:ok, t()} | {:error, ParityTypes.prepare_error()}
  def prepare!(template_key, opts \\ []) when is_binary(template_key) do
    case fetch(template_key) do
      %{} = prepared ->
        {:ok, prepared}

      nil ->
        do_prepare!(template_key, opts)
    end
  end

  defp do_prepare!(template_key, opts) do
    _ = Application.ensure_all_started(:elmx)
    ElmcHostHarness.cleanup_stale_harnesses!()

    project_dir = Keyword.get(opts, :project_dir) || Scaffold.scaffold!(template_key)
    owned_project_dir? = not Keyword.has_key?(opts, :project_dir)

    elmx_revision =
      Keyword.get(
        opts,
        :elmx_revision,
        "parity-elmx-#{template_key}-" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    elmc_out_dir =
      Keyword.get(
        opts,
        :elmc_out_dir,
        Path.join(
          System.tmp_dir!(),
          "ide-template-parity-elmc-#{template_key}-#{System.unique_integer([:positive])}"
        )
      )

    strip_dead_code? = Keyword.get(opts, :strip_dead_code, true)

    with {:ok, %Project{} = project} <- Bridge.load_project(project_dir),
         {:ok, contract} <- CompileContract.build_from_project(project),
         plan <- ExecutionPlan.build!(project_dir, template_key, contract: contract),
         {:ok, elmc} <- compile_elmc(project_dir, project, elmc_out_dir, strip_dead_code?),
         _gc <- :erlang.garbage_collect(),
         {:ok, elmx} <- compile_elmx(project_dir, project, elmx_revision, strip_dead_code?) do
      prepared = %{
        template_key: template_key,
        project_dir: project_dir,
        project: nil,
        contract: nil,
        plan: plan,
        elmx: elmx,
        elmc: elmc,
        owned_project_dir?: owned_project_dir?
      }

      put_cached(Map.put(Process.get(@cache_key, %{}), template_key, prepared))
      {:ok, prepared}
    else
      {:error, _} = err ->
        if owned_project_dir?, do: File.rm_rf!(project_dir)
        File.rm_rf!(elmc_out_dir)
        err
    end
  end

  defp compile_elmx(project_dir, project, revision, strip_dead_code?) do
    case Elmx.compile_in_memory(project_dir, %{
           entry_module: "Main",
           revision: revision,
           mode: :ide_runtime,
           strip_dead_code: strip_dead_code?,
           project: project
         }) do
      {:ok, compile_result} ->
        {:ok,
         %{
           manifest: compile_result.manifest,
           revision: revision,
           module: compile_result.entry_module
         }}

      {:error, reason} ->
        {:error, {:elmx_compile_failed, reason}}
    end
  end

  defp compile_elmc(project_dir, _project, out_dir, strip_dead_code?) do
    File.rm_rf!(out_dir)

    header_path = Path.join(out_dir, "c/elmc_pebble.h")
    ide_root = Path.expand("../../..", __DIR__)
    script = Path.join(__DIR__, "compile_elmc_subprocess.exs")
    strip = if strip_dead_code?, do: "true", else: "false"

    bash = """
    ulimit -v #{compile_subprocess_ulimit_kb()} && \
    export ELIXIR_ERL_OPTIONS='+S 1:1 +MMscs 256' && \
    cd #{inspect(ide_root)} && \
    timeout 300 env MIX_ENV=test mix run --no-start #{inspect(script)} #{inspect(project_dir)} #{inspect(out_dir)} #{strip}
    """

    case System.cmd("bash", ["-c", bash], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "ok") do
          {:ok, tags} = ElmcRunner.parse_msg_tags(header_path)
          {:ok, %{out_dir: out_dir, tags: tags}}
        else
          {:error, {:elmc_subprocess_no_ok, output}}
        end

      {output, code} ->
        {:error, {:elmc_subprocess_failed, code, output}}
    end
  end

  defp compile_subprocess_ulimit_kb, do: System.get_env("PARITY_ELMC_ULIMIT_V_KB", "6291456")

  defp stop_elmc!(out_dir), do: ElmcHostHarness.stop_running_harnesses!(out_dir)

  defp put_cached(map) when is_map(map), do: Process.put(@cache_key, map)
end
