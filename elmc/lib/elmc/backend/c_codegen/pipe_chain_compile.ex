defmodule Elmc.Backend.CCodegen.PipeChainCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{EnvBindings, Host, RcRequired, Types, Util, ValueSlots}
  alias ElmEx.IR.PipeChain

  @pipeline_flatten_threshold 16
  @pipe_acc "__pipe_acc"

  @spec compile(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{steps: steps, base: base}, env, counter) when is_list(steps) do
    {homogeneous_prefix, rest} = split_homogeneous_prefix_steps(steps)

    cond do
      length(homogeneous_prefix) >= @pipeline_flatten_threshold ->
        compile_homogeneous_steps(hd(homogeneous_prefix), length(homogeneous_prefix), base, rest, env, counter)

      length(steps) < @pipeline_flatten_threshold ->
        Host.compile_expr(
          PipeChain.desugar(%{op: :pipe_chain, steps: steps, base: base}),
          env,
          counter
        )

      true ->
        compile_iterative(steps, base, env, counter)
    end
  end

  defp compile_iterative(steps, base, env, counter) do
    {base_code, acc_var, counter} = Host.compile_expr(base, env, counter)

    Enum.reduce(steps, {base_code, acc_var, counter}, fn step, {code_acc, acc_var, c} ->
      step_expr = PipeChain.append_pipe_arg(step, %{op: :var, name: @pipe_acc})
      step_env = Map.put(env, @pipe_acc, acc_var)
      {step_code, next_var, c2} = Host.compile_expr(step_expr, step_env, c)
      release = "  " <> ValueSlots.release_stmt(acc_var) <> "\n"
      {code_acc <> step_code <> release, next_var, c2}
    end)
  end

  defp compile_homogeneous_steps(step, count, base, rest, env, counter) do
    {base_code, base_var, c0} = Host.compile_expr(base, env, counter)
    acc_var = "pipe_acc_#{c0 + 1}"
    loop_id = c0 + 2

    {loop_code, acc_var, c1} =
      case direct_top_level_fn(step, env) do
        {fn_name, module, name} when is_binary(fn_name) ->
          callee_rc? =
            RcRequired.rc_required?(module, name) and
              not EnvBindings.direct_call_target?(env, module, name)

          code =
            if callee_rc? do
              IO.iodata_to_binary([
                "  ElmcValue *#{acc_var} = #{base_var};\n",
                "  for (elmc_int_t pipe_i_#{loop_id} = 0; pipe_i_#{loop_id} < #{count}; pipe_i_#{loop_id}++) {\n",
                "    ElmcValue *pipe_next_#{loop_id} = NULL;\n",
                "    RC pipe_rc_#{loop_id} = #{fn_name}(&pipe_next_#{loop_id}, (ElmcValue *[]){ #{acc_var} }, 1);\n",
                "    if (pipe_rc_#{loop_id} != RC_SUCCESS) {\n",
                "      ELMC_RC_LOG_FAIL(pipe_rc_#{loop_id}, \"#{fn_name}\", \"pipe step failed\");\n",
                "      #{acc_var} = NULL;\n",
                "      break;\n",
                "    }\n",
                "    " <> ValueSlots.release_stmt(acc_var) <> "\n",
                "    #{acc_var} = pipe_next_#{loop_id};\n",
                "  }\n"
              ])
            else
              IO.iodata_to_binary([
                "  ElmcValue *#{acc_var} = #{base_var};\n",
                "  for (elmc_int_t pipe_i_#{loop_id} = 0; pipe_i_#{loop_id} < #{count}; pipe_i_#{loop_id}++) {\n",
                "    ElmcValue *pipe_args_#{loop_id}[1] = { #{acc_var} };\n",
                "    ElmcValue *pipe_next_#{loop_id} = #{fn_name}(pipe_args_#{loop_id}, 1);\n",
                "    " <> ValueSlots.release_stmt(acc_var) <> "\n",
                "    #{acc_var} = pipe_next_#{loop_id};\n",
                "  }\n"
              ])
            end

          {code, acc_var, loop_id}

        :error ->
          compile_homogeneous_closure_loop(step, count, base_var, acc_var, loop_id, env, c0)
      end

    prefix = IO.iodata_to_binary([base_code | loop_code])

    case rest do
      [] ->
        {prefix, acc_var, c1}

      rest_steps ->
        {rest_code, final_var, c2} =
          Enum.reduce(rest_steps, {"", acc_var, c1}, fn step, {code_acc, acc_var, c} ->
            step_expr = PipeChain.append_pipe_arg(step, %{op: :var, name: @pipe_acc})
            step_env = Map.put(env, @pipe_acc, acc_var)
            {step_code, next_var, c2} = Host.compile_expr(step_expr, step_env, c)
            release = "  " <> ValueSlots.release_stmt(acc_var) <> "\n"
            {code_acc <> step_code <> release, next_var, c2}
          end)

        {prefix <> rest_code, final_var, c2}
    end
  end

  defp compile_homogeneous_closure_loop(step, count, base_var, acc_var, loop_id, env, counter) do
    {fun_code, fun_var, c1} = Host.compile_expr(step, env, counter + 2)

    code = IO.iodata_to_binary([
      fun_code,
      "  ElmcValue *#{acc_var} = #{base_var};\n",
      "  for (elmc_int_t pipe_i_#{loop_id} = 0; pipe_i_#{loop_id} < #{count}; pipe_i_#{loop_id}++) {\n",
      "    ElmcValue *pipe_args_#{loop_id}[1] = { #{acc_var} };\n",
      "    ElmcValue *pipe_next_#{loop_id} = elmc_closure_call(#{fun_var}, pipe_args_#{loop_id}, 1);\n",
      "    " <> ValueSlots.release_stmt(acc_var) <> "\n",
      "    #{acc_var} = pipe_next_#{loop_id};\n",
      "  }\n"
    ])

    {code, acc_var, c1}
  end

  defp direct_top_level_fn(%{op: :call, name: name, args: []}, env) when is_binary(name) do
    module = Map.get(env, :__module__, "Main")
    {Util.module_fn_name(module, name), module, name}
  end

  defp direct_top_level_fn(%{op: :var, name: name}, env) when is_binary(name) do
    module = Map.get(env, :__module__, "Main")
    {Util.module_fn_name(module, name), module, name}
  end

  defp direct_top_level_fn(_step, _env), do: :error

  defp split_homogeneous_prefix_steps([]), do: {[], []}

  defp split_homogeneous_prefix_steps([first | rest]) do
    {same, other} = Enum.split_while(rest, &(&1 == first))
    {[first | same], other}
  end
end
