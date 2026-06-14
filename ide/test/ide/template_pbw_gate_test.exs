defmodule Ide.TemplatePbwGateTest do
  @moduledoc """
  Full priv-template Pebble SDK package gate.

  Every `ProjectTemplates.template_keys()` entry must produce a real `.pbw` via
  `PebbleToolchain.package/2` (elmc codegen + Pebble link), not only elmx compile.

  Run locally:

      ELMC_TEMPLATE_PBW_GATE=1 mix test --only template_pbw_gate

  Requires `pebble` on PATH and an activated Pebble SDK (see CI job `ide-template-pbw-gate`).
  """

  use Ide.DataCase, async: false

  alias Ide.ProjectTemplates
  alias Ide.TemplatePbwGate

  @enabled? System.get_env("ELMC_TEMPLATE_PBW_GATE") in ["1", "true", "TRUE"]

  @tag :template_pbw_gate
  @tag timeout: 300_000
  test "pebble CLI is available when template PBW gate is enabled" do
    if @enabled? do
      assert System.find_executable("pebble"),
             "pebble CLI not found; install pebble-tool and activate a Pebble SDK " <>
               "(ELMC_TEMPLATE_PBW_GATE requires a real Pebble build)"
    else
      assert true
    end
  end

  for template <- ProjectTemplates.template_keys() do
    @tag :template_pbw_gate
    @tag timeout: 300_000
    test "packages #{template} to a .pbw with Pebble SDK" do
      if @enabled? do
        template = unquote(template)

        case TemplatePbwGate.package_template(template) do
          {:ok, meta} ->
            assert meta.bytes > 0
            assert meta.platforms == ProjectTemplates.target_platforms_for_template(template)

          {:error, meta} ->
            flunk("""
            template #{template} Pebble package failed (#{inspect(Map.get(meta, :kind))}):

            #{TemplatePbwGate.format_failure(meta)}
            """)
        end
      else
        assert true
      end
    end
  end
end
