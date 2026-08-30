defmodule Elmc.Test.ElmPebbleDevWasmCompile do
  @moduledoc false

  @repo_root Path.expand("../../..", __DIR__)
  @elmc_root Path.join(@repo_root, "elmc")
  @default_out Path.join(@elmc_root, "tmp/elm_pebble_dev_wasm")
  @compile_script Path.join(@elmc_root, "test/support/compile_elm_pebble_dev_wasm.exs")
  @check_script Path.join(@elmc_root, "test/support/check_elm_pebble_dev_wasm.exs")
  @mix_run_limited Path.join(@repo_root, "scripts/mix-run-limited.sh")

  # HeroScene (/wasm) draws under elmc WASM via plan builtins:
  # Elm.Kernel.MJS.* → runtime.mjs_*, WebGL entity/toHtml → runtime.webgl_*,
  # Float.Extra.interpolateFrom → runtime.float_interpolate_from.
  # Browser.Events / VirtualDom.on already rewrite to dom_sub / html_cmd
  # and must not re-enter a host-bridge allowlist (that list is empty).

  @spec default_out_dir() :: String.t()
  def default_out_dir, do: @default_out

  @doc """
  True for leftover host-bridge stubs. The allowlist is empty; leftover
  MJS/WebGL/Float missing-callees are diagnosed (`missing_callee_stub`).
  """
  @spec allowed_host_bridge_stub?(map()) :: boolean()
  def allowed_host_bridge_stub?(entry) when is_map(entry) do
    Elmc.Backend.Wasm.StubFunctions.host_bridge?(entry)
  end

  @spec compile!(keyword()) :: String.t()
  def compile!(opts \\ []) do
    check? = Keyword.get(opts, :check, false)
    export_all? = Keyword.get(opts, :export_all, false)
    out_dir = Keyword.get(opts, :out_dir, @default_out)
    rm_rf? = Keyword.get(opts, :rm_rf, true)
    link_wasm? = Keyword.get(opts, :link_wasm, true)
    prepare? = Keyword.get(opts, :prepare, true)

    if prepare?, do: ensure_prepared!()

    script = if check?, do: @check_script, else: @compile_script
    script_arg = Path.relative_to(script, @elmc_root)

    env =
      System.get_env()
      |> Map.put("TEST_ULIMIT_V_KB", System.get_env("TEST_ULIMIT_V_KB", "10485760"))
      |> Map.put("ELIXIR_ERL_OPTIONS", System.get_env("ELIXIR_ERL_OPTIONS", "+S 1:1 +MMscs 256"))
      |> Map.put("ELMC_OUT_DIR", out_dir)
      |> Map.put("ELMC_RM_RF", if(rm_rf?, do: "1", else: "0"))
      |> Map.put("ELMC_LINK_WASM", if(link_wasm?, do: "1", else: "0"))
      |> then(fn map ->
        if export_all?, do: Map.put(map, "ELMC_WASM_EXPORT_ALL", "1"), else: map
      end)
      |> Enum.into([])

    {output, code} =
      System.cmd(@mix_run_limited, ["elmc", script_arg],
        cd: @repo_root,
        env: env,
        stderr_to_stdout: true
      )

    if code != 0 do
      raise "elm_pebble_dev wasm compile failed:\n#{output}"
    end

    out_dir
  end

  @doc false
  @spec ensure_prepared!() :: :ok
  def ensure_prepared! do
    app = Path.join(@repo_root, "elm_pebble_dev")
    main = Path.join(app, ".elm-pages/Main.elm")
    tw = Path.join(app, ".elm-tailwind/Tailwind.elm")
    pages_pkg =
      case System.get_env("ELM_HOME") do
        path when is_binary(path) and path != "" ->
          Path.join([Path.expand(path), "0.19.1/packages/dillonkearns/elm-pages"])

        _ ->
          Path.join([System.user_home!(), ".elm/0.19.1/packages/dillonkearns/elm-pages"])
      end

    if File.regular?(main) and File.regular?(tw) and File.dir?(pages_pkg) do
      :ok
    else
      script = Path.join(@repo_root, "scripts/prepare-elm-pebble-dev-wasm-gate.sh")
      {output, code} = System.cmd(script, [], cd: @repo_root, stderr_to_stdout: true)

      if code != 0 do
        raise "elm_pebble_dev wasm gate prep failed:\n#{output}"
      end

      :ok
    end
  end
end
