defmodule Elmc.Backend.CCodegen.SequenceLoopCodegen do
  @moduledoc false

  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.ListLoopCodegen
  alias Elmc.Backend.CCodegen.Types

  @spec emit_native_head_loop(String.t(), pos_integer(), String.t(), String.t(), Types.compile_env(), String.t(), keyword()) ::
          String.t()
  def emit_native_head_loop(list_ref, loop_id, head_native_var, inner_body, env, list_arg, opts \\ [])
      when is_binary(list_ref) and is_binary(head_native_var) and is_binary(inner_body) and
             is_binary(list_arg) do
    repr = loop_repr_option(env, list_arg, opts)

    ListLoopCodegen.emit_native_list_int_head_loop(
      list_ref,
      loop_id,
      head_native_var,
      inner_body,
      repr: repr
    )
  end

  @spec emit_boxed_head_walk(String.t(), pos_integer(), String.t(), String.t(), Types.compile_env(), String.t(), keyword()) ::
          String.t()
  def emit_boxed_head_walk(list_ref, loop_id, head_var, inner_body, env, list_arg, opts \\ [])
      when is_binary(list_ref) and is_binary(head_var) and is_binary(inner_body) and
             is_binary(list_arg) do
    repr = loop_repr_option(env, list_arg, opts)

    ListLoopCodegen.emit_boxed_head_list_walk(list_ref, loop_id, head_var, inner_body,
      repr: repr,
      env: env
    )
  end

  @spec emit_length_count(String.t(), pos_integer(), Types.compile_env(), String.t(), keyword()) ::
          {String.t(), String.t()}
  def emit_length_count(list_var, loop_id, env, list_arg, opts \\ []) do
    repr = loop_repr_option(env, list_arg, opts)
    ListLoopCodegen.emit_length_native_count(list_var, loop_id, repr: repr)
  end

  defp loop_repr_option(env, list_arg, opts) do
    case Keyword.get(opts, :repr) do
      nil ->
        module = Map.get(env, :__module__, "Main")
        fun = Map.get(env, :__function_name__, "")

        module
        |> LayoutSolver.param_plan(fun, list_arg)
        |> LayoutSolver.codegen_loop_repr()

      repr ->
        repr
    end
  end
end
