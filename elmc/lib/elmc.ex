defmodule Elmc do
  @moduledoc """
  Public API for the Elm-to-C compiler.
  """

  alias Elmc.Backend.CCodegen
  alias Elmc.Backend.DebugUsage
  alias Elmc.Backend.Pebble
  alias Elmc.Backend.Ports
  alias Elmc.Backend.Worker
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.Plan.{PrimaryCoverage, StrictPolicy}
  alias Elmc.Backend.Plan
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.DeadCode
  alias ElmEx.IR.Lowerer
  alias ElmEx.IR.PipeChain
  alias Elmc.Runtime.Generator

  @type compile_options :: Elmc.Types.compile_options()

  @doc """
  Typechecks and extracts frontend metadata for an Elm project.
  """
  @spec check(String.t()) :: {:ok, map()} | {:error, map()}
  def check(project_dir) do
    Bridge.load_project(project_dir)
  end

  @doc """
  Compiles a supported Elm subset into C artifacts.
  """
  @spec compile(String.t(), compile_options()) :: {:ok, map()} | {:error, term()}
  def compile(project_dir, opts \\ %{}) do
    opts = normalize_compile_opts(opts)
    entry_module = opts[:entry_module] || "Main"

    with {:ok, project} <- project_for_compile(project_dir, opts),
         {:ok, ir0} <- Lowerer.lower_project(project),
         ir0 = PipeChain.desugar_project(ir0),
         ir <- maybe_strip_dead_code(ir0, entry_module, opts[:strip_dead_code]),
         {:ok, ir, debug_usage_diagnostics} <- check_debug_usage(ir, opts),
         out_dir = opts[:out_dir] || "build",
         :ok <- seed_codegen_process_state(ir, opts),
         :ok <- Ports.write_port_headers(ir, out_dir),
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
              "Function #{mod}.#{name} fell back to legacy C codegen because Plan IR lowering is not yet supported for this body."
          }
        end)

      bytecode_summary = Elmc.Backend.Bytecode.Artifacts.read_summary(out_dir)

      plan_coverage_diagnostics =
        Elmc.Backend.Plan.PrimaryCoverage.compile_diagnostics(bytecode_summary, opts)

      plan_legacy_diagnostics = plan_legacy_codegen_diagnostics(opts)

      plan_coverage =
        case bytecode_summary do
          %{available: true, plan_coverage: coverage} -> coverage
          _ -> nil
        end

      plan_toolchain = plan_toolchain_summary(bytecode_summary, opts)

      Process.delete(:elmc_layout_coercion_diagnostics)
      Process.delete(:elmc_plan_primary_fallbacks)

      {:ok,
       %{
         project: project,
         ir: ir,
         debug_usage_diagnostics: debug_usage_diagnostics,
         layout_coercion_diagnostics:
           layout_coercion_diagnostics ++
             plan_primary_fallbacks ++
             plan_legacy_diagnostics ++
             plan_coverage_diagnostics,
         plan_coverage: plan_coverage,
         plan_toolchain: plan_toolchain,
         elmc_bytecode_summary: bytecode_summary
       }}
    end
  end

  @spec normalize_compile_opts(compile_options() | keyword()) :: compile_options()
  defp normalize_compile_opts(opts) when is_list(opts),
    do: opts |> Map.new() |> normalize_compile_opts()

  defp normalize_compile_opts(opts) when is_map(opts) do
    opts
    |> Elmc.Backend.Plan.Defaults.apply_defaults()
    |> Elmc.Backend.SizeProfile.apply()
  end

  @spec check_debug_usage(ElmEx.IR.t(), compile_options()) ::
          {:ok, ElmEx.IR.t(), [map()]}
          | {:error, {:compile_diagnostics, [map()]}}
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
  defp maybe_strip_dead_code(ir, entry_module, _), do: DeadCode.strip(ir, entry_module)

  @spec seed_codegen_process_state(ElmEx.IR.t(), compile_options()) :: :ok
  defp seed_codegen_process_state(ir, opts) do
    Process.put(:elmc_codegen_opts, opts)
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))
    :ok
  end

  @spec maybe_recompile_stream_view_fallback(
          ElmEx.IR.t(),
          String.t(),
          String.t(),
          compile_options(),
          String.t()
        ) :: {:ok, {compile_options(), String.t()}} | {:error, term()}
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
          {:ok, ElmEx.Frontend.Project.t()} | {:error, term()}
  defp project_for_compile(_project_dir, %{project: %ElmEx.Frontend.Project{} = project}),
    do: {:ok, project}

  defp project_for_compile(_project_dir, %{"project" => %ElmEx.Frontend.Project{} = project}),
    do: {:ok, project}

  defp project_for_compile(project_dir, _opts), do: Bridge.load_project(project_dir)

  defp plan_legacy_codegen_diagnostics(opts) when is_map(opts) do
    if Map.get(opts, :plan_ir_mode_explicit_off) == true do
      [
        %{
          "source" => "elmc/plan",
          "code" => "plan_legacy_codegen",
          "severity" => "info",
          "message" =>
            "Compiling with plan_ir_mode: :off (legacy C codegen). Use :primary for verified Plan IR emission."
        }
      ]
    else
      []
    end
  end

  defp plan_toolchain_summary(bytecode_summary, opts) do
    case bytecode_summary do
      %{plan_toolchain: %{} = toolchain} -> normalize_plan_toolchain(toolchain)
      %{"plan_toolchain" => %{} = toolchain} -> normalize_plan_toolchain(toolchain)
      _ -> %{mode: Plan.plan_ir_mode(opts), strict: Plan.strict_primary?(opts)}
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
