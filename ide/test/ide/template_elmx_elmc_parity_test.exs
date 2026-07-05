defmodule Ide.TemplateElmxElmcParityTest do
  @moduledoc """
  Cross-backend parity between elmx and elmc for IDE project templates.

  Enable with:

      TEMPLATE_ELMX_ELMC_PARITY=1 mix test --only template_parity

  Heavy work runs in a memory-bounded subprocess via `scripts/mix-test-limited.sh`
  so the ExUnit parent does not OOM the IDE host.

  Optional filters:

      TEMPLATE_PARITY_TEMPLATE=watchface-minimal
      TEMPLATE_PARITY_PROFILE=basalt
  """

  use ExUnit.Case, async: false

  alias Ide.Test.TemplateElmxElmcParity, as: Parity

  @enabled? Parity.enabled?()
  @repo_root Path.expand("../../..", __DIR__)
  @limited_test_script Path.join(@repo_root, "scripts/mix-test-limited.sh")

  setup do
    on_exit(fn -> Parity.release_all!() end)
    :ok
  end

  @tag :template_parity
  test "harness modules are loadable" do
    assert function_exported?(Parity, :compare!, 2)
    assert function_exported?(Parity, :enabled?, 0)
    assert function_exported?(Parity, :prepare!, 1)
    assert Parity.watch_profiles() == ["basalt", "chalk"]
    assert File.regular?(@limited_test_script)
  end

  for template_key <- Parity.representative_template_keys() do
    @tag :template_parity
    @tag timeout: 600_000
    test "elmx/elmc parity #{template_key} when enabled" do
      template_key = unquote(template_key)

      if run_template?(template_key) do
        assert run_template_in_subprocess!(template_key)
      else
        assert true
      end
    end
  end

  @tag :template_parity
  @tag :slow
  @tag timeout: :infinity
  test "full template catalog parity when enabled" do
    if @enabled? and System.get_env("TEMPLATE_PARITY_FULL") in ["1", "true", "TRUE"] do
      failures =
        for template_key <- Parity.template_keys(), reduce: [] do
          acc ->
            if run_template?(template_key) do
              run_template_in_subprocess!(template_key)
              acc
            else
              acc
            end
        end

      assert failures == [],
             "full template parity subprocess failures (#{length(failures)}): #{inspect(Enum.reverse(failures))}"
    else
      assert true
    end
  end

  defp run_template_in_subprocess!(template_key) do
    env =
      System.get_env()
      |> Map.put("TEMPLATE_ELMX_ELMC_PARITY", "1")
      |> Map.put("TEMPLATE_PARITY_TEMPLATE", template_key)
      |> Map.new(fn {k, v} -> {k, v} end)

    args = [
      "ide",
      "test/ide/template_elmx_elmc_parity_case_test.exs",
      "--only",
      "template_parity_case",
      "--max-cases",
      "1"
    ]

    {output, status} =
      System.cmd(@limited_test_script, args,
        cd: @repo_root,
        env: Map.to_list(env),
        stderr_to_stdout: true
      )

    if status == 0 do
      true
    else
      flunk("""
      template parity subprocess failed for #{template_key} (exit #{status})

      #{String.slice(output, -8000, 8000)}
      """)
    end
  end

  defp run_template?(template_key) do
    @enabled? and template_filter?(template_key)
  end

  defp template_filter?(template_key) do
    case System.get_env("TEMPLATE_PARITY_TEMPLATE") do
      nil -> true
      wanted -> wanted == template_key
    end
  end
end
