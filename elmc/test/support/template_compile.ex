defmodule Elmc.TestSupport.TemplateCompile do
  @moduledoc false

  @repo_root Path.expand("../../..", __DIR__)

  defp shared_elm_sources do
    bundled = Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm")
    checkout = Path.join(@repo_root, "shared/elm")

    cond do
      File.regular?(Path.join(bundled, "Companion/Internal.elm")) -> bundled
      File.regular?(Path.join(checkout, "Companion/Internal.elm")) -> checkout
      true -> bundled
    end
  end

  @spec compile_watch_template(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def compile_watch_template(template_name, opts \\ []) when is_binary(template_name) do
    template_src = Path.join(@repo_root, "ide/priv/project_templates/#{template_name}")
    tmp = Path.join(System.tmp_dir!(), "elmc-template-#{template_name}-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(Path.join(tmp, "src"))
      File.cp_r!(Path.join(template_src, "src"), Path.join(tmp, "src"))

      deps = %{
        "elm/core" => "1.0.5",
        "elm/json" => "1.1.3",
        "elm/time" => "1.0.0"
      }

      deps =
        if template_name in ["watchface_poke_battle", "game_jump_n_run"],
          do: Map.put(deps, "elm/random", "1.0.0"),
          else: deps

      sources =
        [
          "src",
          Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
          shared_elm_sources(),
          Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src")
        ]
        |> maybe_add_protocol_sources(template_src, tmp)
        |> maybe_add_random_sources(deps)

      elm_json = %{
        "type" => "application",
        "source-directories" => sources,
        "elm-version" => "0.19.1",
        "dependencies" => %{"direct" => deps, "indirect" => %{}}
      }

      File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))

      out_dir = Keyword.get(opts, :out_dir, Path.join(tmp, ".elmc-out"))

      compile_opts =
        %{
          out_dir: out_dir,
          entry_module: "Main",
          strip_dead_code: Keyword.get(opts, :strip_dead_code, true),
          plan_ir_mode: Keyword.get(opts, :plan_ir_mode, :primary),
          pebble_int32: Keyword.get(opts, :pebble_int32, false)
        }
        |> Map.merge(Map.new(Keyword.take(opts, [:plan_ir_strict, :direct_render_only, :prune_runtime, :codegen_profile])))

      Elmc.compile(tmp, compile_opts)
    after
      unless Keyword.get(opts, :keep_tmp, false), do: File.rm_rf(tmp)
    end
  end

  defp maybe_add_protocol_sources(sources, template_src, tmp) do
    protocol_src = Path.join(template_src, "protocol/src")
    types_path = Path.join(protocol_src, "Companion/Types.elm")

    if File.regular?(types_path) do
      File.mkdir_p!(Path.join(tmp, "protocol"))
      File.cp_r!(protocol_src, Path.join(tmp, "protocol/src"))
      generated_types = Path.join(tmp, "protocol/src/Companion/Types.elm")
      internal_path = Path.join(tmp, "protocol/src/Companion/Internal.elm")
      ide_dir = Path.join(@repo_root, "ide")

      {_, 0} =
        System.cmd(
          "mix",
          [
            "run",
            "-e",
            "Ide.CompanionProtocolGenerator.generate_elm_internal(\"#{generated_types}\", \"#{internal_path}\")"
          ],
          cd: ide_dir,
          stderr_to_stdout: true
        )

      ["protocol/src" | sources]
    else
      sources
    end
  end

  defp maybe_add_random_sources(sources, deps) do
    if Map.has_key?(deps, "elm/random") do
      sources ++ [Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")]
    else
      sources
    end
  end

  @spec decl_map_from_result(map()) :: map()
  def decl_map_from_result(%{ir: ir}) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
    end)
    |> Map.new()
  end
end
