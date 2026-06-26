defmodule Ide.TemplatePbwGate do
  @moduledoc """
  Packages IDE project templates through the Pebble SDK and verifies a `.pbw` artifact.

  Used by `test/ide/template_pbw_gate_test.exs` and `scripts/template_pbw_gate.exs`.

      ELMC_TEMPLATE_PBW_GATE=1 mix test --only template_pbw_gate
      mix run scripts/template_pbw_gate.exs
  """

  alias Ide.PebbleToolchain
  alias Ide.PebbleToolchain.Types, as: ToolchainTypes
  alias Ide.ProjectTemplates

  @type package_meta :: %{
          artifact_path: String.t(),
          bytes: non_neg_integer(),
          platforms: [String.t()]
        }

  @type error_kind :: :build_failed | :package | :missing_pbw | :exception

  @type error_meta :: %{
          optional(:kind) => error_kind(),
          optional(:reason) => ToolchainTypes.toolchain_error(),
          optional(:tail) => String.t(),
          optional(:message) => String.t()
        }

  @spec package_template(String.t(), keyword()) ::
          {:ok, package_meta()} | {:error, error_meta()}
  def package_template(template, opts \\ []) do
    unless template in ProjectTemplates.template_keys() do
      raise ArgumentError, "unknown template #{inspect(template)}"
    end

    workspace =
      Keyword.get_lazy(opts, :workspace, fn ->
        Path.join(
          System.tmp_dir!(),
          "pbw-gate-#{template}-#{System.unique_integer([:positive])}"
        )
      end)

    slug = Keyword.get(opts, :slug, "pbw-gate-#{template}")
    cleanup? = Keyword.get(opts, :cleanup, true)

    target_platforms =
      Keyword.get(opts, :target_platforms, ProjectTemplates.target_platforms_for_template(template))

    try do
      with :ok <- ProjectTemplates.apply_template(template, workspace),
           {:ok, pkg} <-
             PebbleToolchain.package(slug,
               workspace_root: workspace,
               target_type: ProjectTemplates.target_type_for_template(template),
               project_name: template,
               target_platforms: target_platforms
             ),
           true <- File.regular?(pkg.artifact_path) do
        {:ok,
         %{
           artifact_path: pkg.artifact_path,
           bytes: File.stat!(pkg.artifact_path).size,
           platforms: target_platforms
         }}
      else
        {:error, {:pebble_build_failed, %{output: output}}} ->
          {:error, %{kind: :build_failed, tail: build_output_tail(output)}}

        {:error, reason} ->
          {:error, %{kind: :package, reason: reason}}

        false ->
          {:error, %{kind: :missing_pbw}}
      end
    rescue
      error ->
        {:error, %{kind: :exception, message: Exception.message(error)}}
    after
      if cleanup?, do: File.rm_rf(workspace)
    end
  end

  @spec run_all(keyword()) :: [{String.t(), :ok | :error, package_meta() | error_meta()}]
  def run_all(opts \\ []) do
    templates = Keyword.get(opts, :templates, ProjectTemplates.template_keys())

    Enum.map(templates, fn template ->
      t0 = System.monotonic_time(:second)

      case package_template(template, opts) do
        {:ok, meta} ->
          elapsed = System.monotonic_time(:second) - t0
          {template, :ok, Map.put(meta, :elapsed_s, elapsed)}

        {:error, meta} ->
          elapsed = System.monotonic_time(:second) - t0
          {template, :error, Map.put(meta, :elapsed_s, elapsed)}
      end
    end)
  end

  @spec format_failure(error_meta()) :: String.t()
  def format_failure(%{kind: :build_failed, tail: tail}) when is_binary(tail) do
    tail
  end

  def format_failure(%{kind: :package, reason: reason}) do
    inspect(reason, limit: :infinity, printable_limit: :infinity)
  end

  def format_failure(%{kind: :exception, message: message}) when is_binary(message) do
    message
  end

  def format_failure(%{kind: :missing_pbw}) do
    "package succeeded but artifact_path is missing or not a regular file"
  end

  def format_failure(meta) do
    inspect(meta, limit: :infinity, printable_limit: :infinity)
  end

  defp build_output_tail(output) when is_binary(output) do
    if byte_size(output) > 3000 do
      String.slice(output, -3000, 3000)
    else
      output
    end
  end
end
