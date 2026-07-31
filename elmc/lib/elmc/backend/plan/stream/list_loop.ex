defmodule Elmc.Backend.Plan.Stream.ListLoop do
  @moduledoc """
  Bridges DirectRender list-loop peels (`ListLoopPlans`) into the Plan stream
  emit path for `*_commands_append` helpers.

  Map/indexedMap/range tick pipelines are not yet lowered as verified Plan SSA;
  this module reuses the generic C loop emitters until stream fusions land.
  """
  alias Elmc.Backend.CCodegen.DirectRender.ListLoopPlans
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types, as: Types

  @tracked_gaps [
    :static_draw_tables,
    :affine_text_templates,
    :nested_dr_call_stream_abi
  ]

  @spec tracked_gaps() :: [atom()]
  def tracked_gaps, do: @tracked_gaps

  @spec try_emit_body(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          {:ok, String.t()} | :error
  def try_emit_body(decl, module_name, decl_map) do
    arg_names = List.wrap(decl.args)
    target = {module_name, decl.name, arg_names}

    env =
      stream_env(module_name, decl, decl_map, arg_names)
      |> Map.put(:__direct_emit_target__, target)

    case Map.get(decl, :expr) do
      %{op: _} = expr ->
        if ListLoopPlans.pipeline_fragment?(expr, env) do
          emit_list_loop(expr, target, env)
        else
          :error
        end

      _ ->
        :error
    end
  end

  @spec emit_list_loop(Types.ir_expr(), Types.direct_emit_target(), Types.compile_env()) ::
          {:ok, String.t()} | :error
  defp emit_list_loop(expr, target, env) do
    with {:ok, plans} <- ListLoopPlans.analyze(expr, env),
         true <- ListLoopPlans.fusion_plans?(plans),
         {:ok, body, _counter} <-
           ListLoopPlans.emit_map_loops(plans, target, "", [], "", env, 0) do
      {:ok, String.trim_trailing(body) <> "\n"}
    else
      _ -> :error
    end
  end

  @spec stream_env(
          String.t(),
          Types.function_declaration(),
          Types.function_decl_map(),
          [String.t()]
        ) :: Types.compile_env()
  defp stream_env(module_name, decl, decl_map, arg_names) do
    c_bindings = Host.c_arg_bindings(arg_names)

    c_bindings
    |> Enum.reduce(
      %{
        __module__: module_name,
        __program_decls__: decl_map,
        __rc_catch__: true,
        __rc_required__: true,
        __hoisted_native_ints_enabled__: true
      },
      fn {source_arg, c_arg, _index}, acc ->
        Map.put(acc, source_arg, c_arg)
      end
    )
    |> Host.put_typed_arg_bindings(c_bindings, decl.type)
    |> EnvBindings.put_direct_param_refs(c_bindings)
  end
end
