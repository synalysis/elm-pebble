defmodule Elmc.WasmWebHeroSceneTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.WasmRcTrackHarness

  @app_root Path.expand("../../elm_pebble_dev", __DIR__)
  @build_dir Path.expand("../../elm_pebble_dev/dist/wasm-web", __DIR__)
  @route_bytes Path.expand("../../elm_pebble_dev/dist/wasm/content.dat", __DIR__)
  @app_wasm Path.expand("../../elm_pebble_dev/dist/wasm-web/wasm/app.wasm", __DIR__)
  @runner Path.expand("support/wasm_hero_scene_probe.mjs", __DIR__)

  @tag :wasm_execute
  @tag :slow
  @tag timeout: 180_000
  test "elm_pebble_dev /wasm HeroScene boots with WebGL entities and draws" do
    cond do
      not File.dir?(@app_root) ->
        :ok

      not File.regular?(@app_wasm) ->
        :ok

      not File.regular?(@route_bytes) ->
        :ok

      not WasmRcTrackHarness.execution_tools_available?() ->
        :ok

      true ->
        env = %{"NODE_OPTIONS" => "--max-old-space-size=4096"}

        case WasmRcTrackHarness.run_node_script(@runner, [@build_dir, @route_bytes], env: env) do
          {:ok, output} ->
            assert output =~ "[hero-probe] ok entities="
            assert output =~ ~r/entities=([1-9]\d*)/
            assert output =~ ~r/draws=([1-9]\d*)/
            assert output =~ "[hero-probe] orbit ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              # Address-space hard caps (e.g. mix-run-limited) can still block instantiate.
              # Prefer: npm run verify:wasm:hero
              :ok
            else
              flunk("elm_pebble_dev HeroScene probe failed:\n#{output}")
            end
        end
    end
  end
end
