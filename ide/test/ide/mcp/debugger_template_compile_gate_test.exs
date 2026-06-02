defmodule Ide.Mcp.DebuggerTemplateCompileGateTest do
  @moduledoc """
  Full priv-template elmx compile sweep.

  Run with `ELMX_TEMPLATE_COMPILE_GATE=1 mix test --only template_compile_gate`.
  """

  use Ide.DataCase, async: false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.ProjectTemplates
  alias Ide.ProjectTemplates.SourceValidation

  @enabled? System.get_env("ELMX_TEMPLATE_COMPILE_GATE") in ["1", "true", "TRUE"]

  @tag :template_compile_gate
  @tag timeout: 600_000
  test "every project template watch workspace compiles with elmx when enabled" do
    if @enabled? do
      Corpus.ensure_compiled_elixir_backend!()

      failures =
        ProjectTemplates.template_keys()
        |> Enum.flat_map(fn template_key ->
          watch =
            case compile_template_watch(template_key) do
              :ok -> []
              {:error, reason} -> [{"#{template_key}/watch", reason}]
            end

          phone =
            case compile_template_phone(template_key) do
              :ok -> []
              {:skip, _} -> []
              {:error, reason} -> [{"#{template_key}/phone", reason}]
            end

          watch ++ phone
        end)

      if failures != [] do
        flunk("elmx compile gate failures:\n#{inspect(failures, limit: 10)}")
      end
    else
      assert true
    end
  end

  defp compile_template_watch(template_key) do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "elmx-compile-gate-#{template_key}-#{:erlang.unique_integer([:positive])}"
      )

    with :ok <- SourceValidation.validate_template(template_key),
         :ok <- ProjectTemplates.apply_template(template_key, workspace),
         watch_dir when is_binary(watch_dir) <- watch_workspace_dir(workspace) do
      try do
        revision =
          "gate-" <> template_key <> "-" <> Integer.to_string(:erlang.unique_integer([:positive]))

        case Ide.Compiler.build_elmx_artifacts_in_memory(watch_dir,
               revision: revision,
               strip_dead_code: true
             ) do
          {:ok, %{elmx_manifest: manifest}} ->
            if manifest["contract"] == "elmx.runtime_executor.v1" and
                 Elmx.module_for_revision(revision),
               do: :ok,
               else: {:error, :bad_manifest}

          {:error, reason} ->
            if Corpus.corpus_compile_smoke_failure?(reason), do: :ok, else: {:error, reason}
        end
      after
        _ = File.rm_rf(workspace)
      end
    else
      {:error, :missing_watch_dir} -> {:error, :missing_watch_dir}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  defp watch_workspace_dir(workspace_root) do
    watch_dir = Path.join(workspace_root, "watch")

    if File.dir?(watch_dir) do
      watch_dir
    else
      {:error, :missing_watch_dir}
    end
  end

  defp compile_template_phone(template_key) do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "elmx-compile-gate-phone-#{template_key}-#{:erlang.unique_integer([:positive])}"
      )

    with :ok <- SourceValidation.validate_template(template_key),
         :ok <- ProjectTemplates.apply_template(template_key, workspace),
         phone_dir when is_binary(phone_dir) <- phone_workspace_dir(workspace) do
      try do
        revision =
          "gate-phone-" <>
            template_key <> "-" <> Integer.to_string(:erlang.unique_integer([:positive]))

        case Ide.Compiler.build_elmx_artifacts_in_memory(phone_dir,
               revision: revision,
               entry_module: "CompanionApp",
               strip_dead_code: true
             ) do
          {:ok, %{elmx_manifest: manifest}} ->
            if manifest["contract"] == "elmx.runtime_executor.v1" and
                 Elmx.module_for_revision(revision),
               do: :ok,
               else: {:error, :bad_manifest}

          {:error, reason} ->
            if Corpus.corpus_compile_smoke_failure?(reason), do: :ok, else: {:error, reason}
        end
      after
        _ = File.rm_rf(workspace)
      end
    else
      {:skip, :no_phone_dir} -> {:skip, :no_phone_dir}
      {:error, :missing_watch_dir} -> {:skip, :no_phone_dir}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  defp phone_workspace_dir(workspace_root) do
    phone_dir = Path.join(workspace_root, "phone")

    if File.dir?(phone_dir) and File.exists?(Path.join(phone_dir, "src/CompanionApp.elm")) do
      phone_dir
    else
      {:skip, :no_phone_dir}
    end
  end
end
