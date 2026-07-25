defmodule Elmc do
  @moduledoc """
  Public API for the Elm-to-C compiler.
  """

  alias Elmc.Backend.CCodegen
  alias Elmc.Backend.CCodegen.ObjectTextEstimate
  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.DebugUsage
  alias Elmc.Backend.Pebble
  alias Elmc.Backend.Ports
  alias Elmc.Backend.Worker
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.{PrimaryCoverage, StrictPolicy}
  alias Elmc.Backend.Plan
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias ElmEx.IR.PipeChain
  alias Elmc.Backend.Wasm.Targets
  alias Elmc.Backend.Wasm.WebKernelDiagnostics
  alias Elmc.Runtime.Generator

  alias Elmc.Types, as: RootTypes

  @type compile_options :: RootTypes.compile_options()
  @type compile_result :: RootTypes.compile_result()
  @type compile_error :: RootTypes.compile_error()
  @type object_text_estimate :: RootTypes.object_text_estimate()

  @doc """
  Estimates `.text` bytes for generated C objects under `out_dir` using the Pebble ARM toolchain.
  """
  @spec object_text_estimate(String.t(), keyword()) :: object_text_estimate()
  def object_text_estimate(out_dir, opts \\ []) when is_binary(out_dir) do
    ObjectTextEstimate.estimate(out_dir, opts)
  end

  @doc """
  Typechecks and extracts frontend metadata for an Elm project.

  Does **not** run IR lowering or dead-code stripping — those belong to `compile/2`.
  IDE save checks and `elmc check` use this lighter path for diagnostics feedback.
  """
  @spec check(String.t()) ::
          {:ok, ElmEx.Frontend.Project.t()} | {:error, RootTypes.frontend_bridge_error()}
  def check(project_dir) do
    Bridge.load_project(project_dir, lowerer_diagnostics: false)
  end

  @doc """
  Compiles a supported Elm subset into C artifacts.
  """
  @spec compile(String.t(), compile_options()) ::
          {:ok, compile_result()} | {:error, compile_error()}
  def compile(project_dir, opts \\ %{}) do
    opts = normalize_compile_opts(opts)
    entry_module = opts[:entry_module] || "Main"
    wasm_only? = Targets.wasm_only?(opts)

    compile_log("compile starting (#{Path.basename(project_dir)}, entry=#{entry_module})")

    with {:ok, project} <- project_for_compile(project_dir, opts),
         :ok <- check_missing_imports(project, opts),
         :ok <- compile_log(lowering_ir_log_message(opts)),
         {:ok, ir0} <- Lowerer.lower_project(project, lower_project_opts(project, opts)),
         :ok <- compile_log("IR lower complete (#{length(ir0.modules)} modules); emitting artifacts…"),
         ir0 = PipeChain.desugar_project(ir0),
         ir <- maybe_strip_dead_code(ir0, entry_module, opts[:strip_dead_code]),
         :ok <- compile_log("dead-code strip complete; planning/emitting…"),
         {:ok, ir, debug_usage_diagnostics} <- check_debug_usage(ir, opts),
         svg_dom = IRQueries.svg_attribute_dom_names(ir0),
         opts =
           opts
           |> Map.put(:svg_attribute_dom_names, svg_dom)
           |> Map.put(:svg_attribute_names, MapSet.new(Map.keys(svg_dom))),
         out_dir = opts[:out_dir] || "build",
         :ok <- seed_codegen_process_state(ir, opts),
         :ok <- maybe_write_c_artifacts(ir, out_dir, entry_module, opts, wasm_only?) do
      compile_log("artifact emit complete")
      layout_coercion_diagnostics =
        Process.get(:elmc_layout_coercion_diagnostics, [])
        |> Elmc.Backend.CCodegen.LayoutCoerceEmit.format_compile_warnings()

      decl_map = IRQueries.function_decl_map(ir)

      plan_primary_fallbacks =
        Process.get(:elmc_plan_primary_fallbacks, [])
        |> Enum.map(fn {mod, name} ->
          reachable? = PrimaryCoverage.reachable_function?(decl_map, mod, name, opts)

          %{
            "source" => "elmc/plan",
            "code" => "plan_primary_fallback",
            "severity" => StrictPolicy.fallback_severity(opts, reachable?),
            "message" =>
              "Function #{mod}.#{name} could not be lowered via Plan IR; emitted unsupported stub (legacy C codegen removed)."
          }
        end)

      bytecode_summary = Elmc.Backend.Bytecode.Artifacts.read_summary(out_dir)
      wasm_summary = Elmc.Backend.Wasm.Artifacts.read_summary(out_dir)

      plan_coverage_diagnostics =
        Elmc.Backend.Plan.PrimaryCoverage.compile_diagnostics(bytecode_summary, opts) ++
          wasm_plan_coverage_diagnostics(wasm_summary, opts)

      plan_legacy_diagnostics = plan_legacy_codegen_diagnostics(opts)

      web_kernel_diagnostics = WebKernelDiagnostics.compile_diagnostics()

      layout_and_plan_diagnostics =
        layout_coercion_diagnostics ++
          plan_primary_fallbacks ++
          plan_legacy_diagnostics ++
          plan_coverage_diagnostics ++
          web_kernel_diagnostics

      wasm_empty_export_diagnostics = wasm_empty_export_diagnostics(wasm_summary, opts)

      blocking_diagnostics =
        Elmc.Diagnostics.blocking_from_sources(
          debug_usage: debug_usage_diagnostics,
          layout_and_plan: layout_and_plan_diagnostics ++ wasm_empty_export_diagnostics
        )

      informational_diagnostics =
        (debug_usage_diagnostics ++ layout_and_plan_diagnostics ++ wasm_empty_export_diagnostics)
        |> Enum.reject(&Elmc.Diagnostics.error?/1)

      plan_coverage =
        case wasm_summary do
          %{available: true, plan_coverage: coverage} when not is_nil(coverage) -> coverage
          _ ->
            case bytecode_summary do
              %{available: true, plan_coverage: coverage} -> coverage
              _ -> nil
            end
        end

      plan_toolchain = plan_toolchain_summary(bytecode_summary, wasm_summary, opts)

      Process.delete(:elmc_layout_coercion_diagnostics)
      Process.delete(:elmc_plan_primary_fallbacks)
      Process.delete(:elmc_web_kernel_diagnostics)

      {:ok,
       %{
         project: project,
         ir: ir,
         debug_usage_diagnostics: debug_usage_diagnostics,
         layout_coercion_diagnostics: layout_and_plan_diagnostics,
         blocking_diagnostics: blocking_diagnostics,
         informational_diagnostics: informational_diagnostics,
         plan_coverage: plan_coverage,
         plan_toolchain: plan_toolchain,
         elmc_bytecode_summary: bytecode_summary,
         elmc_wasm_summary: wasm_summary
       }}
    end
  end

  defp check_missing_imports(%ElmEx.Frontend.Project{} = project, opts) when is_map(opts) do
    missing =
      (Map.get(project, :diagnostics) || [])
      |> Enum.filter(fn d -> is_map(d) and Map.get(d, "type") == "missing-import" end)

    if missing == [] do
      :ok
    else
      diagnostics =
        Enum.map(missing, fn d ->
          %{
            "source" => "elmc/frontend",
            "code" => "missing_import",
            "severity" => "error",
            "module" => Map.get(d, "module"),
            "message" => Map.get(d, "message") || "Missing import"
          }
        end)

      {:error, {:compile_diagnostics, diagnostics}}
    end
  end

  defp check_missing_imports(_project, _opts), do: :ok

  @spec normalize_compile_opts(compile_options() | keyword()) :: compile_options()
  defp normalize_compile_opts(opts) when is_list(opts),
    do: opts |> Map.new() |> normalize_compile_opts()

  defp normalize_compile_opts(opts) when is_map(opts) do
    opts
    |> Elmc.Backend.Plan.Defaults.apply_defaults()
    |> Elmc.Backend.SizeProfile.apply()
  end

  @spec check_debug_usage(ElmEx.IR.t(), compile_options()) ::
          {:ok, ElmEx.IR.t(), [CCodegenTypes.compile_warning_json()]}
          | {:error, {:compile_diagnostics, [CCodegenTypes.compile_warning_json()]}}
  defp check_debug_usage(ir, opts) do
    case DebugUsage.check(ir, opts) do
      :ok ->
        {:ok, ir, []}

      {:warn, diagnostics} ->
        {:ok, ir, diagnostics}

      {:error, diagnostics} ->
        {:error, {:compile_diagnostics, diagnostics}}
    end
  end

  @spec maybe_strip_dead_code(ElmEx.IR.t(), String.t(), boolean() | nil) :: ElmEx.IR.t()
  defp maybe_strip_dead_code(ir, _entry_module, false), do: ir
  defp maybe_strip_dead_code(ir, entry_module, _), do: ElmEx.IR.DeadCode.strip(ir, entry_module)

  defp compile_log(message) when is_binary(message) do
    IO.puts(:stderr, "[elmc] #{message}")
    :ok
  end

  @spec lowering_ir_log_message(compile_options()) :: String.t()
  defp lowering_ir_log_message(opts) do
    if Targets.emit_wasm?(opts) do
      "lowering IR (progress on stderr; cache/reachable-only enabled by default)…"
    else
      "lowering IR…"
    end
  end

  defp lower_project_opts(%ElmEx.Frontend.Project{} = project, opts) when is_map(opts) do
    strip? = Map.get(opts, :strip_dead_code, true) != false
    fast? = Map.get(opts, :fast, false) == true or System.get_env("ELMC_FAST") in ["1", "true"]

    parallel =
      Map.get(opts, :ir_parallel) ||
        case System.get_env("ELMC_IR_PARALLEL") do
          nil -> if fast?, do: 2, else: 1
          n -> String.to_integer(n)
        end

    cache? =
      Map.get(opts, :ir_cache, true) != false and
        is_binary(project.project_dir)

    cache_dir =
      Map.get(opts, :ir_cache_dir) ||
        (cache? && Path.join(project.project_dir, ".elmc-cache/ir"))

    [
      entry_module: opts[:entry_module] || "Main",
      reachable_only: Map.get(opts, :ir_reachable_only, strip?),
      cache: cache?,
      cache_dir: cache_dir,
      progress: Map.get(opts, :ir_progress, true),
      parallel: max(1, parallel)
    ]
    |> Enum.reject(fn
      {:cache_dir, nil} -> true
      _ -> false
    end)
  end

  @spec seed_codegen_process_state(ElmEx.IR.t(), compile_options()) :: :ok
  defp seed_codegen_process_state(ir, opts) do
    Process.put(:elmc_codegen_opts, opts)
    Process.put(:elmc_svg_attribute_names, Map.get(opts, :svg_attribute_names, MapSet.new()))
    Process.put(
      :elmc_svg_attribute_dom_names,
      Map.get(opts, :svg_attribute_dom_names, %{})
    )
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    Process.put(:elmc_module_ports, IRQueries.module_ports_map(ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_inline_record_literal_shapes, IRQueries.inline_record_literal_shape_map(ir))
    Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))
    # Per-compile memoization for type/native-arg analysis (large packages like
    # elm-geometry/elm-physics otherwise re-parse the same signatures millions of times).
    Process.put(:elmc_type_parsing_arrow_cache, %{})
    Process.put(:elmc_native_arg_kinds_cache, %{})
    Process.put(:elmc_native_arg_kinds_analysis_cache, %{})
    :ok
  end

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes

  @spec maybe_recompile_stream_view_fallback(
          ElmEx.IR.t(),
          String.t(),
          String.t(),
          compile_options(),
          String.t()
        ) :: {:ok, {compile_options(), String.t()}} | {:error, CCodegenTypes.file_error()}
  defp maybe_recompile_stream_view_fallback(ir, out_dir, entry_module, opts, generated_c) do
    if Pebble.stream_view_fallback_needed?(ir, generated_c, entry_module, opts) do
      fallback_opts = Map.put(opts, :stream_view_fallback, true)

      with :ok <- CCodegen.write_project(ir, out_dir, fallback_opts) do
        {:ok, {fallback_opts, File.read!(Path.join(out_dir, "c/elmc_generated.c"))}}
      end
    else
      {:ok, {opts, generated_c}}
    end
  end

  @spec project_for_compile(String.t(), compile_options()) ::
          {:ok, ElmEx.Frontend.Project.t()} | {:error, RootTypes.frontend_bridge_error()}
  defp project_for_compile(_project_dir, %{project: %ElmEx.Frontend.Project{} = project}),
    do: {:ok, project}

  defp project_for_compile(_project_dir, %{"project" => %ElmEx.Frontend.Project{} = project}),
    do: {:ok, project}

  defp project_for_compile(project_dir, _opts),
    do: Bridge.load_project(project_dir, lowerer_diagnostics: false)

  defp plan_legacy_codegen_diagnostics(opts) when is_map(opts) do
    if Map.get(opts, :plan_ir_mode_off_deprecated) == true do
      [
        %{
          "source" => "elmc/plan",
          "code" => "plan_ir_mode_off_removed",
          "severity" => "warning",
          "message" =>
            "plan_ir_mode: :off is no longer supported (legacy C codegen removed). Compiling with plan_ir_mode: :primary."
        }
      ]
    else
      []
    end
  end

  defp maybe_write_c_artifacts(ir, out_dir, _entry_module, opts, true = _wasm_only?) do
    with :ok <- Elmc.Backend.Wasm.ProjectWriter.write(ir, out_dir, opts),
         :ok <- write_wasm_runtime(out_dir, opts),
         :ok <- validate_wasm_only_artifacts(out_dir, opts) do
      :ok
    end
  end

  defp maybe_write_c_artifacts(ir, out_dir, entry_module, opts, false) do
    with :ok <- Ports.write_port_headers(ir, out_dir),
         :ok <- Worker.write_worker_adapter(ir, out_dir, entry_module, opts),
         :ok <- CCodegen.write_project(ir, out_dir, opts),
         generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c")),
         {:ok, {opts, generated_c}} <-
           maybe_recompile_stream_view_fallback(ir, out_dir, entry_module, opts, generated_c),
         :ok <-
           Pebble.write_pebble_shim(
             ir,
             out_dir,
             entry_module,
             Map.put(opts, :generated_c, generated_c)
           ),
         :ok <-
           Generator.write_runtime(
             opts[:runtime_dir] || Path.join(opts[:out_dir] || "build", "runtime"),
             prune_from_dir: if(opts[:prune_runtime], do: opts[:out_dir] || "build", else: nil),
             pebble_int32: opts[:pebble_int32] || false
           ) do
      :ok
    end
  end

  defp write_wasm_runtime(out_dir, opts) do
    if Map.get(opts, :wasm_runtime, true) do
      with :ok <-
             Generator.write_runtime(
               Path.join(out_dir, "runtime"),
               prune_from_dir: out_dir,
               pebble_int32: opts[:pebble_int32] || false
             ),
           :ok <- maybe_copy_wasm_host(out_dir, opts) do
        :ok
      end
    else
      :ok
    end
  end

  defp validate_wasm_only_artifacts(out_dir, opts) when is_map(opts) do
    summary = Elmc.Backend.Wasm.Artifacts.read_summary(out_dir)
    web? = Map.get(opts, :web, false) == true
    strict? = Map.get(opts, :wasm_strict, true)

    case summary do
      %{available: true, skipped: skipped} when is_list(skipped) ->
        unsupported =
          Enum.filter(skipped, fn entry ->
            reason = Map.get(entry, :reason) || Map.get(entry, "reason")
            is_binary(reason) and
              (String.starts_with?(reason, "unsupported") or String.starts_with?(reason, "{:unsupported"))
          end)

        missing_generated =
          Enum.filter(skipped, fn entry ->
            reason = Map.get(entry, :reason) || Map.get(entry, "reason")
            is_binary(reason) and String.contains?(reason, "missing_generated_helper")
          end)

        unsupported_errors = if strict?, do: unsupported, else: []

        if unsupported_errors == [] and missing_generated == [] do
          :ok
        else
          detail_diagnostics =
            Enum.map(unsupported_errors, fn entry ->
              mod = Map.get(entry, :module) || Map.get(entry, "module")
              name = Map.get(entry, :name) || Map.get(entry, "name")

              %{
                "source" => "elmc/wasm",
                "code" => "wasm_unsupported_function",
                "severity" => "error",
                "module" => mod,
                "function" => name,
                "message" =>
                  "WASM codegen does not yet support lowering #{mod}.#{name} (function skipped as unsupported)."
              }
            end)

          missing_generated_diagnostics =
            Enum.map(missing_generated, fn entry ->
              mod = Map.get(entry, :module) || Map.get(entry, "module")
              name = Map.get(entry, :name) || Map.get(entry, "name")
              reason = Map.get(entry, :reason) || Map.get(entry, "reason")

              %{
                "source" => "elmc/wasm",
                "code" => "wasm_missing_generated_helper",
                "severity" => "error",
                "module" => mod,
                "function" => name,
                "message" =>
                  "WASM lowering encountered a missing generated helper while compiling #{mod}.#{name}: #{reason}. This usually indicates your app's code generator produced references to helpers that were not defined (for example, a `.elm-pages` generated file referencing `w3_*` helpers that do not exist)."
              }
            end)

          diagnostics =
            if web? do
              [
                %{
                  "source" => "elmc/wasm",
                  "code" => "wasm_web_kernel_unimplemented",
                  "severity" => "error",
                  "message" =>
                    "Compiling a general Elm web app to WASM requires implementations of Elm's JS kernel/runtime surface (elm/core, elm/browser, elm/html, elm/virtual-dom, elm/file, elm/http, ...). This build skipped unsupported functions; implement the missing kernel/platform lowering instead of adding app-specific shims."
                }
                | (detail_diagnostics ++ missing_generated_diagnostics)
              ]
            else
              detail_diagnostics ++ missing_generated_diagnostics
            end

          {:error, {:compile_diagnostics, diagnostics}}
        end

      _ ->
        :ok
    end
  end

  defp maybe_copy_wasm_host(out_dir, opts) do
    if Map.get(opts, :wasm_host, true) do
      host_src = Path.expand("../../elmc-wasm-runtime/host", __DIR__)
      host_dst = Path.join(out_dir, "host")

      js_files =
        host_src
        |> Path.join("*.js")
        |> Path.wildcard()
        |> Enum.sort()

      with :ok <- File.mkdir_p(host_dst),
           :ok <- copy_host_files(js_files, host_dst),
           :ok <- File.cp(Path.join(host_src, "browser.html"), Path.join(host_dst, "browser.html")) do
        :ok
      end
    else
      :ok
    end
  end

  defp copy_host_files([], _host_dst), do: :ok

  defp copy_host_files([src | rest], host_dst) do
    dst = Path.join(host_dst, Path.basename(src))

    with :ok <- File.cp(src, dst) do
      copy_host_files(rest, host_dst)
    end
  end

  defp wasm_plan_coverage_diagnostics(%{available: true}, opts) when is_map(opts) do
    if Targets.emit_wasm?(opts) do
      []
    else
      []
    end
  end

  defp wasm_plan_coverage_diagnostics(_summary, _opts), do: []

  defp wasm_empty_export_diagnostics(%{available: true} = wasm_summary, opts) when is_map(opts) do
    if Targets.emit_wasm?(opts) and Map.get(opts, :strip_dead_code, true) == true do
      count =
        Map.get(wasm_summary, :function_count) ||
          Map.get(wasm_summary, "function_count") ||
          0

      skipped =
        Map.get(wasm_summary, :skipped_count) ||
          Map.get(wasm_summary, "skipped_count") ||
          0

      if is_integer(count) and is_integer(skipped) and count == 0 and skipped == 0 do
        entry = Map.get(opts, :entry_module, "Main")

        [
          %{
            "source" => "elmc/wasm",
            "code" => "wasm_empty_exports",
            "severity" => "error",
            "message" =>
              "WASM build produced 0 exported functions after dead-code stripping. This usually means entry_module=#{entry} is not the runtime root (for web apps, it is typically Main). Try compiling with entry_module: \"Main\" or disable strip_dead_code while debugging."
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp wasm_empty_export_diagnostics(_summary, _opts), do: []

  defp plan_toolchain_summary(bytecode_summary, wasm_summary, opts) do
    case wasm_summary do
      %{plan_toolchain: %{} = toolchain} ->
        normalize_plan_toolchain(toolchain)

      %{"plan_toolchain" => %{} = toolchain} ->
        normalize_plan_toolchain(toolchain)

      _ ->
        case bytecode_summary do
          %{plan_toolchain: %{} = toolchain} ->
            normalize_plan_toolchain(toolchain)

          %{"plan_toolchain" => %{} = toolchain} ->
            normalize_plan_toolchain(toolchain)

          _ ->
            %{
              mode: Plan.plan_ir_mode(opts),
              strict: Plan.strict_primary?(opts),
              targets: Targets.normalize(opts)
            }
        end
    end
  end

  defp normalize_plan_toolchain(%{"mode" => mode, "strict" => strict}),
    do: %{mode: normalize_plan_mode(mode), strict: strict}

  defp normalize_plan_toolchain(%{mode: mode, strict: strict}),
    do: %{mode: normalize_plan_mode(mode), strict: strict}

  defp normalize_plan_mode(mode) when is_atom(mode), do: mode
  defp normalize_plan_mode("primary"), do: :primary
  defp normalize_plan_mode("shadow"), do: :shadow
  defp normalize_plan_mode("off"), do: :off
  defp normalize_plan_mode(mode) when is_binary(mode), do: String.to_existing_atom(mode)
end
