defmodule Elmc.TestSupport.TemplateCompile do
  @moduledoc false

  @repo_root Path.expand("../../..", __DIR__)

  alias Elmc.CLI.Types, as: ElmcCliTypes
  alias Elmc.TestSupport.CompileCache

  defp shared_elm_sources do
    bundled = Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm")
    checkout = Path.join(@repo_root, "shared/elm")

    cond do
      File.regular?(Path.join(bundled, "Companion/Internal.elm")) -> bundled
      File.regular?(Path.join(checkout, "Companion/Internal.elm")) -> checkout
      true -> bundled
    end
  end

  @spec compile_watch_template(String.t(), keyword()) ::
          {:ok, ElmcCliTypes.compile_result()} | {:error, ElmcCliTypes.compile_error()}
  def compile_watch_template(template_name, opts \\ []) when is_binary(template_name) do
    template_src = Path.join(@repo_root, "ide/priv/project_templates/#{template_name}")
    out_dir = Keyword.get_lazy(opts, :out_dir, fn ->
      Path.join(System.tmp_dir!(), "elmc-template-out-#{template_name}-#{System.unique_integer([:positive])}")
    end)

    compile_opts =
      opts
      |> then(&build_compile_opts(&1, out_dir))
      |> CompileCache.inject_compile_opts()

    cache_key = cache_key(template_name, template_src, compile_opts)

    case CompileCache.fetch(cache_key) do
      {:hit, result, out_cache} ->
        CompileCache.materialize_out(out_cache, out_dir, :auto)
        {:ok, result}

      :miss ->
        do_compile(template_name, template_src, opts, compile_opts, cache_key)
    end
  end

  defp do_compile(template_name, template_src, opts, compile_opts, cache_key) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elmc-template-#{template_name}-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(Path.join(tmp, "src"))
      File.cp_r!(Path.join(template_src, "src"), Path.join(tmp, "src"))

      deps = %{
        "elm/core" => "1.0.5",
        "elm/json" => "1.1.3",
        "elm/time" => "1.0.0"
      }

      deps =
        if template_name in [
             "watchface_poke_battle",
             "game_jump_n_run",
             "game_2048",
             "game_elmtris",
             "game_tiny_bird"
           ],
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

      elm_json =
        Elmc.TestSupport.ElmJson.minimal_application(
          source_directories: sources,
          direct: deps
        )

      File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))

      case Elmc.compile(tmp, compile_opts) do
        {:ok, result} = ok ->
          CompileCache.store(cache_key, result, compile_opts.out_dir)
          ok

        other ->
          other
      end
    after
      unless Keyword.get(opts, :keep_tmp, false), do: File.rm_rf(tmp)
    end
  end

  defp build_compile_opts(opts, out_dir) do
    %{
      out_dir: out_dir,
      entry_module: "Main",
      strip_dead_code: Keyword.get(opts, :strip_dead_code, true),
      plan_ir_mode: Keyword.get(opts, :plan_ir_mode, :primary),
      pebble_int32: Keyword.get(opts, :pebble_int32, false)
    }
    |> Map.merge(
      Map.new(
        Keyword.take(opts, [
          :plan_ir_strict,
          :direct_render_only,
          :prune_runtime,
          :prune_native_wrappers,
          :codegen_profile,
          :emit_bytecode,
          :prod
        ])
      )
    )
  end

  defp cache_key(template_name, template_src, compile_opts) do
    opts_fingerprint = Map.drop(compile_opts, [:out_dir, :ir_cache_dir])

    fingerprint = {
      :template_compile_v2,
      template_name,
      opts_fingerprint,
      CompileCache.dir_stamp(Path.join(template_src, "src")),
      CompileCache.file_hash(Path.join(template_src, "protocol/src/Companion/Types.elm")),
      CompileCache.dir_stamp(Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src")),
      CompileCache.dir_stamp(shared_elm_sources()),
      CompileCache.compiler_identity()
    }

    CompileCache.key(fingerprint)
  end

  defp maybe_add_protocol_sources(sources, template_src, tmp) do
    protocol_src = Path.join(template_src, "protocol/src")
    types_path = Path.join(protocol_src, "Companion/Types.elm")

    if File.regular?(types_path) do
      File.mkdir_p!(Path.join(tmp, "protocol"))
      File.cp_r!(protocol_src, Path.join(tmp, "protocol/src"))
      generated_types = Path.join(tmp, "protocol/src/Companion/Types.elm")
      internal_path = Path.join(tmp, "protocol/src/Companion/Internal.elm")
      ensure_companion_internal!(generated_types, internal_path)
      ["protocol/src" | sources]
    else
      sources
    end
  end

  defp ensure_companion_internal!(types_path, internal_path) do
    types_hash = CompileCache.file_hash(types_path) || raise("missing Companion/Types.elm")
    cache_path = Path.join([CompileCache.cache_root(), "protocol", "#{types_hash}.elm"])

    if File.regular?(cache_path) do
      File.cp!(cache_path, internal_path)
    else
      ide_dir = Path.join(@repo_root, "ide")

      with :ok <- ensure_ide_deps(ide_dir),
           {_, 0} <-
             System.cmd(
               "mix",
               [
                 "run",
                 "--no-start",
                 "-e",
                 "case Ide.CompanionProtocolGenerator.generate_elm_internal(\"#{types_path}\", \"#{internal_path}\") do :ok -> :ok; err -> IO.inspect(err); System.halt(1) end"
               ],
               cd: ide_dir,
               stderr_to_stdout: true
             ) do
        File.mkdir_p!(Path.dirname(cache_path))
        File.cp!(internal_path, cache_path)
        :ok
      else
        {:error, reason} ->
          raise "failed to prepare ide deps for Companion/Internal.elm generation: #{reason}"

        {output, _} ->
          raise "failed to generate Companion/Internal.elm via ide mix run:\n#{output}"
      end
    end
  end

  defp ensure_ide_deps(ide_dir) do
    ide_app = Path.join(ide_dir, "_build/dev/lib/ide/ebin/ide.app")

    cond do
      File.regular?(ide_app) ->
        :ok

      File.regular?(Path.join(ide_dir, "deps/phoenix/mix.exs")) ->
        compile_ide(ide_dir)

      true ->
        with {_, 0} <- System.cmd("mix", ["deps.get"], cd: ide_dir, stderr_to_stdout: true),
             :ok <- compile_ide(ide_dir) do
          :ok
        else
          {output, _} -> {:error, String.slice(output, -2000, 2000)}
        end
    end
  end

  defp compile_ide(ide_dir) do
    case System.cmd("mix", ["compile", "--no-start"], cd: ide_dir, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, String.slice(output, -2000, 2000)}
    end
  end

  defp maybe_add_random_sources(sources, deps) do
    if Map.has_key?(deps, "elm/random") do
      sources ++ [Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")]
    else
      sources
    end
  end

  alias Elmc.CLI.Types, as: CliTypes

  @spec decl_map_from_result(CliTypes.compile_result()) :: %{
          optional({String.t(), String.t()}) => ElmEx.IR.Declaration.t()
        }
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
