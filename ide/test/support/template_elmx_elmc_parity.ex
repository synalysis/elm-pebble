defmodule Ide.Test.TemplateElmxElmcParity do
  @moduledoc """
  Compares elmx and elmc runtime output for project templates using a shared
  execution plan (init, update branches, view, subscriptions, phone messages).
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Ide.ProjectTemplates
  alias Ide.Test.TemplateElmxElmcParity.Compare
  alias Ide.Test.TemplateElmxElmcParity.ElmcRunner
  alias Ide.Test.TemplateElmxElmcParity.ElmxRunner
  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan
  alias Ide.Test.TemplateElmxElmcParity.Prepare

  @representative_templates ~w(
    watchface-minimal
    watchface-digital
    watchface-analog
    app-minimal
    starter
    companion-demo-weather-env
  )

  @watch_profiles ~w(basalt chalk)

  @doc """
  Gate for template parity tests.

  Run with `TEMPLATE_ELMX_ELMC_PARITY=1 scripts/mix-test-limited.sh ide test/ide/template_elmx_elmc_parity_test.exs --only template_parity`.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    System.get_env("TEMPLATE_ELMX_ELMC_PARITY") in ["1", "true", "TRUE"]
  end

  @spec watch_profiles() :: [String.t()]
  def watch_profiles, do: @watch_profiles

  @spec template_keys() :: [String.t()]
  def template_keys, do: ProjectTemplates.template_keys()

  @spec representative_template_keys() :: [String.t()]
  def representative_template_keys, do: @representative_templates

  @type compare_result :: %{
          template_key: String.t(),
          watch_profile_id: String.t(),
          plan: ExecutionPlan.t(),
          elmx_steps: [map()],
          elmc_steps: [map()],
          mismatches: [Compare.mismatch()]
        }

  @spec prepare!(String.t(), keyword()) :: {:ok, Prepare.t()} | {:error, term()}
  def prepare!(template_key, opts \\ []), do: Prepare.prepare!(template_key, opts)

  @spec release!(String.t()) :: :ok
  def release!(template_key), do: Prepare.release!(template_key)

  @spec release_all!() :: :ok
  def release_all!, do: Prepare.release_all!()

  @spec compare!(String.t(), String.t(), keyword()) ::
          {:ok, compare_result()}
          | {:error, term()}
          | {:mismatch, compare_result()}
  def compare!(template_key, watch_profile_id, opts \\ [])
      when is_binary(template_key) and is_binary(watch_profile_id) do
    cleanup? = Keyword.get(opts, :cleanup, false)

    prepared_result = resolve_prepared(template_key, opts)

    try do
      with {:ok, prepared} <- prepared_result do
        plan = prepared.plan |> ExecutionPlan.for_watch_profile(watch_profile_id)
        runner_opts = [prepared: prepared, keep_out_dir: true]

        with {:ok, elmx_steps} <- ElmxRunner.run!(plan, runner_opts),
             _gc <- :erlang.garbage_collect(),
             {:ok, elmc_steps} <- ElmcRunner.run!(plan, runner_opts) do
          mismatches = Compare.diff(elmx_steps, elmc_steps)

          result = %{
            template_key: template_key,
            watch_profile_id: watch_profile_id,
            plan: plan,
            elmx_steps: elmx_steps,
            elmc_steps: elmc_steps,
            mismatches: mismatches
          }

          if mismatches == [] do
            {:ok, result}
          else
            {:mismatch, result}
          end
        end
      end
    after
      if cleanup? do
        Prepare.release!(template_key)
      end
    end
  end

  defp resolve_prepared(template_key, opts) do
    case Keyword.get(opts, :prepared) do
      %{} = prepared ->
        {:ok, prepared}

      nil ->
        Prepare.prepare!(template_key, Keyword.take(opts, [:project_dir]))
    end
  end

  @spec format_mismatch_report(compare_result()) :: String.t()
  def format_mismatch_report(%{template_key: key, watch_profile_id: profile, mismatches: mismatches}) do
    Compare.format_report(key, profile, mismatches)
  end

  @spec assert_parity!(String.t(), String.t(), keyword()) :: compare_result()
  def assert_parity!(template_key, watch_profile_id, opts \\ []) do
    case compare!(template_key, watch_profile_id, opts) do
      {:ok, result} ->
        result

      {:mismatch, result} ->
        flunk(format_mismatch_report(result))

      {:error, reason} ->
        flunk("template parity failed for #{template_key}/#{watch_profile_id}: #{inspect(reason)}")
    end
  end

  @spec summarize_backends(compare_result()) :: %{elmx_only: [String.t()], elmc_only: [String.t()]}
  def summarize_backends(%{mismatches: mismatches}) do
    elmx_only =
      mismatches
      |> Enum.filter(fn
        %{elmx: :missing} -> true
        _ -> false
      end)
      |> Enum.map(& &1.step_id)

    elmc_only =
      mismatches
      |> Enum.filter(fn
        %{elmc: :missing} -> true
        _ -> false
      end)
      |> Enum.map(& &1.step_id)

    %{elmx_only: elmx_only, elmc_only: elmc_only}
  end
end
