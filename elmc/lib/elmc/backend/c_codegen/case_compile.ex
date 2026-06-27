defmodule Elmc.Backend.CCodegen.CaseCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstructorTagCase
  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.HelperParams
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec dispatch(
          Types.case_subject(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  @spec dispatch(Types.ir_case_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def dispatch(%{op: :case, subject: subject, branches: branches}, env, counter),
    do: dispatch(subject, branches, env, counter)

  def dispatch(subject, branches, env, counter) do
    subject_expr = subject_expr(subject)

    cond do
      NativeInt.expr?(subject_expr, env) and NativeIntCase.branches?(branches) ->
        NativeIntCase.compile(subject_expr, branches, env, counter)

      ConstructorTagCase.switch_eligible?(branches) and
          ConstructorTagCase.native_subject_switch?(subject_expr, branches, env) ->
        ConstructorTagCase.compile_native_subject(subject_expr, branches, env, counter)

      ConstructorTagCase.switch_eligible?(branches) ->
        ConstructorTagCase.compile(subject, branches, env, counter)

      true ->
        compile_boxed(subject, branches, env, counter)
    end
  end

  @spec subject_expr(Types.case_subject()) :: Types.ir_expr()
  def subject_expr(subject) when is_binary(subject), do: %{op: :var, name: subject}
  def subject_expr(subject), do: subject

  @spec branch_assignment(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter()}
  def branch_assignment(%{op: :string_literal, value: value}, out, env, counter) do
    literal = Util.string_literal_c_expr(value)

    if String.contains?(value, <<0>>) do
      {"", "#{out} = #{literal};", counter}
    else
      {"", RcRuntimeEmit.assign_into(env, out, "elmc_new_string", "\"#{Util.escape_c_string(value)}\""),
       counter}
    end
  end

  def branch_assignment(%{op: :bool_literal, value: value}, out, env, counter) do
    branch_assignment_rc(env, out, "elmc_new_bool", if(value, do: "1", else: "0"), counter)
  end

  def branch_assignment(%{op: :int_literal, value: value} = expr, out, env, counter)
      when is_integer(value) do
    cond do
      BuiltinUnion.maybe_nothing_literal?(expr) ->
        {"", "#{out} = elmc_maybe_nothing();", counter}

      value in [0, 1] and function_returns_bool?(env) ->
        branch_assignment_rc(env, out, "elmc_new_bool", Integer.to_string(value), counter)

      true ->
        branch_assignment_int_literal(expr, out, env, counter)
    end
  end

  def branch_assignment(%{op: op} = expr, out, env, counter)
      when op in [:call, :qualified_call] do
    {expr_code, expr_var, counter} =
      Host.compile_expr(expr, branch_assignment_env(env, out), counter)

    branch_assignment_finish(expr_code, expr_var, out, env, counter)
  end

  def branch_assignment(expr, out, env, counter) do
    {expr_code, expr_var, counter} =
      Host.compile_expr(expr, branch_assignment_env(env, out), counter)

    branch_assignment_finish(expr_code, expr_var, out, env, counter)
  end

  defp branch_assignment_env(env, out) do
    if ValueSlots.owned_ref?(out), do: Map.put(env, :__into_out__, out), else: env
  end

  defp branch_assignment_finish(expr_code, expr_var, out, env, counter) do
    case fold_result_binding(expr_code, expr_var, out) do
      {:ok, folded_code} ->
        {folded_code, "", counter}

      :error ->
        case fold_rc_allocator_binding(expr_code, expr_var, out, env) do
          {:ok, folded_code} ->
            {folded_code, "", counter}

          :error ->
            case rename_result_var(expr_code, expr_var, out) do
              {:ok, renamed} -> {renamed, "", counter}
              :error when expr_var == out ->
                if assigns_into_out?(expr_code, out) do
                  {strip_orphan_tmp_decl(expr_code, expr_var), "", counter}
                else
                  {expr_code, "", counter}
                end

              :error ->
                {expr_code, "#{out} = #{expr_var};", counter}
            end
        end
    end
  end

  defp assigns_into_out?(expr_code, out) when is_binary(expr_code) and is_binary(out) do
    String.contains?(expr_code, "&#{out},") or String.contains?(expr_code, "&#{out})")
  end

  defp strip_orphan_tmp_decl(expr_code, expr_var)
       when is_binary(expr_code) and is_binary(expr_var) do
    Regex.replace(~r/^[ \t]*ElmcValue \*#{Regex.escape(expr_var)} = NULL;\n/m, expr_code, "")
  end

  defp rename_result_var(expr_code, from, to), do: fold_result_binding(expr_code, from, to)

  @spec fold_result_binding(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | :error
  defp fold_result_binding(expr_code, expr_var, out)
       when is_binary(expr_code) and expr_code != "" and is_binary(expr_var) and
              is_binary(out) do
    lines =
      expr_code
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case List.pop_at(lines, -1) do
      {nil, _} ->
        :error

      {last, prefix_lines} ->
        case Regex.run(~r/^ElmcValue \*#{Regex.escape(expr_var)} = (.+);$/, last) do
          [_, rhs] ->
            if expr_var != out, do: ValueSlots.untrack(expr_var)

            folded_last = "#{out} = #{rhs};"

            folded_code =
              case prefix_lines do
                [] -> folded_last
                _ -> Enum.join(prefix_lines, "\n") <> "\n" <> folded_last
              end

            {:ok, folded_code}

          _ ->
            :error
        end
    end
  end

  defp fold_result_binding(_expr_code, _expr_var, _out), do: :error

  @spec fold_rc_allocator_binding(String.t(), String.t(), String.t(), map()) ::
          {:ok, String.t()} | :error
  defp fold_rc_allocator_binding(expr_code, expr_var, out, env) do
    trimmed = String.trim(expr_code)
    var = Regex.escape(expr_var)

    fallback =
      ~r/^(?:([\s\S]*?)\n)?ElmcValue \*#{var} = NULL;\nif \((\w+)\(&#{var}, ([^)]+)\) != RC_SUCCESS\)\s*#{var} = elmc_int_zero\(\);$/

  catch_pat =
      ~r/^(?:([\s\S]*?)\n)?(?:ElmcValue \*#{var} = NULL;\n|ElmcValue \*#{var};\n)?Rc = (\w+)\(&#{var}, ([^)]+)\);\n(?:CHECK_RC\(Rc\);|if \(Rc != RC_SUCCESS\) break;)$/

    cond do
      Regex.match?(fallback, trimmed) ->
        [_, prefix, function, call_args] = Regex.run(fallback, trimmed)

        if RcRuntimeEmit.rc_allocator?(function) do
          if expr_var != out, do: ValueSlots.untrack(expr_var)

          folded =
            [prefix, RcRuntimeEmit.assign_into(env, out, function, call_args)]
            |> Enum.reject(&(&1 == ""))
            |> Enum.join("\n")

          {:ok, folded}
        else
          :error
        end

      Regex.match?(catch_pat, trimmed) and RcRuntimeEmit.rc_mode?(env) ->
        [_, prefix, function, call_args] = Regex.run(catch_pat, trimmed)

        if RcRuntimeEmit.rc_allocator?(function) do
          if expr_var != out, do: ValueSlots.untrack(expr_var)

          folded =
            [prefix, RcRuntimeEmit.assign_into(env, out, function, call_args)]
            |> Enum.reject(&(&1 == ""))
            |> Enum.join("\n")

          {:ok, folded}
        else
          :error
        end

      true ->
        :error
    end
  end

  @spec compile_boxed(
          Types.case_subject(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def compile_boxed(subject, branches, env, counter) do
    {subject_setup, subject_ref, counter} =
      ConstructorTagCase.compile_subject_ref(subject, env, counter)

    {out, branch_counter, declare_out?} = result_out_binding(env, counter)

    case_env =
      env
      |> then(fn case_env ->
        if Patterns.maybe_unwrap_just_case?(branches),
          do: Map.put(case_env, :maybe_unwrap_just, true),
          else: case_env
      end)
      |> put_case_subject_payload_type(subject)
      |> put_declared_out(out)
    branch_counter = advance_counter_past_out(branch_counter, out, declare_out?)

    {branch_code, final_counter} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({"", branch_counter}, fn {branch, branch_index}, {acc, c} ->
        last_branch? = branch_index == length(branches) - 1

        {branch_env, unwrap_setup, unwrap_release, c} =
          Patterns.maybe_unwrap_var_branch(case_env, branch, subject_ref, c, subject)

        branch_env = Map.put(branch_env, :__rc_catch__, false)

        {expr_code, assignment_code, c2} =
          branch_assignment(branch.expr, out, branch_env, c)

        cond_code = pattern_condition_code(subject, subject_ref, branch.pattern, branch_env)

        enter_probe =
          env |> battery_alert_case_probe(branch_index, :enter) |> Host.agent_probe_region()

        after_expr_probe =
          env |> battery_alert_case_probe(branch_index, :after_expr) |> Host.agent_probe_region()

        branch_body =
          maybe_extract_branch_helper(
            branch,
            branch_env,
            subject_ref,
            out,
            enter_probe,
            unwrap_setup,
            expr_code,
            after_expr_probe,
            assignment_code,
            unwrap_release
          )

        cond do
          cond_code == "0" ->
            {:cont, {acc, c2}}

          cond_code == "1" and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          last_branch? and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          cond_code == "1" ->
            {:halt, {acc <> else_branch_snippet(branch_body), c2}}

          last_branch? and acc != "" ->
            {:halt, {acc <> else_branch_snippet(branch_body), c2}}

          true ->
            {:cont, {acc <> if_branch_snippet(cond_code, branch_body, acc == ""), c2}}
        end
      end)

    after_setup_probe =
      env |> battery_alert_case_probe(:case, :after_setup) |> Host.agent_probe_region()

    after_branches_probe =
      env |> battery_alert_case_probe(:case, :after_branches) |> Host.agent_probe_region()

    code =
      Enum.join(
        [
          subject_setup,
          result_out_decl(out, declare_out?),
          after_setup_probe,
          branch_code,
          after_branches_probe
        ],
        "\n"
      )

    {code, out, final_counter}
  end

  @spec result_out_binding(Types.compile_env(), Types.compile_counter()) ::
          {String.t(), Types.compile_counter(), boolean()}
  def result_out_binding(env, counter) do
    case Map.get(env, :__into_out__) do
      nil ->
        if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
          {ref, index} = ValueSlots.alloc()
          {ref, max(counter, index + 1), false}
        else
          next = counter + 1
          {"tmp_#{next}", next, true}
        end

      out ->
        {out, counter, false}
    end
  end

  @spec result_out_decl(String.t(), boolean()) :: String.t()
  def result_out_decl(_out, false), do: ""
  def result_out_decl(out, true), do: ValueSlots.boxed_null_decl(out)

  @spec advance_counter_past_out(Types.compile_counter(), String.t(), boolean()) ::
          Types.compile_counter()
  def advance_counter_past_out(counter, _out, false), do: counter

  def advance_counter_past_out(counter, out, true) do
    cond do
      match = Regex.run(~r/^tmp_(\d+)$/, out) ->
        [_, digits] = match
        max(counter, String.to_integer(digits) + 1)

      match = Regex.run(~r/^owned\[(\d+)\]$/, out) ->
        [_, digits] = match
        max(counter, String.to_integer(digits) + 1)

      true ->
        counter
    end
  end

  @spec fresh_var(Types.compile_counter(), Types.compile_env()) ::
          {String.t(), Types.compile_counter()}
  def fresh_var(counter, env) do
    if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
      {ref, index} = ValueSlots.alloc()

      if MapSet.member?(Map.get(env, :__declared_outs__, MapSet.new()), ref) do
        fresh_var(max(counter, index + 1), env)
      else
        {ref, max(counter, index + 1)}
      end
    else
      fresh_tmp_var(counter, env)
    end
  end

  @spec fresh_tmp_var(Types.compile_counter(), Types.compile_env()) ::
          {String.t(), Types.compile_counter()}
  def fresh_tmp_var(counter, env \\ %{}) do
    next = counter + 1
    var = "tmp_#{next}"

    if MapSet.member?(Map.get(env, :__declared_outs__, MapSet.new()), var) do
      fresh_tmp_var(next, env)
    else
      {var, next}
    end
  end

  defp if_branch_snippet(cond_code, branch_body, first_branch?) do
    keyword = if first_branch?, do: "if", else: "else if"
    prefix = if first_branch?, do: "", else: "} "

    """
    #{prefix}#{keyword} (#{cond_code}) {
    #{format_branch_body(branch_body)}

    """
  end

  defp else_branch_snippet(branch_body) do
    """
    } else {
    #{format_branch_body(branch_body)}
    }
    """
  end

  defp format_branch_body(body) do
    CSource.format_block(body, 4)
  end

  defp maybe_extract_branch_helper(
         branch,
         branch_env,
         subject_ref,
         out,
         enter_probe,
         unwrap_setup,
         expr_code,
         after_expr_probe,
         assignment_code,
         unwrap_release
       ) do
    inline_body =
      format_branch_body(
        Enum.join(
          [enter_probe, unwrap_setup, expr_code, after_expr_probe, assignment_code, unwrap_release],
          "\n"
        )
      )

    if extract_branch_helper?(branch_env, inline_body) do
      case branch_helper_params(branch, branch_env, subject_ref, expr_code, assignment_code) do
        {:ok, params} when params != [] ->
          if helper_params_collide_with_locals?(params, inline_body) do
            inline_body
          else
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_case_branch_helper_#{Util.safe_c_suffix(Map.get(branch_env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(branch_env, :__function_name__, "fn"))}_#{helper_id}"

          helper_param_decls = HelperParams.param_decls(params)

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
            ElmcValue *#{out} = NULL;
          #{CSource.indent(enter_probe, 2)}
          #{CSource.indent(unwrap_setup, 2)}
          #{CSource.indent(expr_code, 2)}
          #{CSource.indent(after_expr_probe, 2)}
            #{assignment_code}
          #{CSource.indent(unwrap_release, 2)}
            return #{out};
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          call_args = HelperParams.call_args(params)

          """
              #{out} = #{helper_name}(#{call_args});
          """
          end

        _ ->
          inline_body
      end
    else
      inline_body
    end
  end

  defp extract_branch_helper?(branch_env, body) do
    RcRuntimeEmit.generic_helper_extraction_allowed?(branch_env, body) and
      Process.get(:elmc_generic_helper_defs) != nil and emitted_line_count(body) >= 60
  end

  defp emitted_line_count(code), do: code |> String.split("\n") |> length()

  defp helper_params_collide_with_locals?(params, body) when is_binary(body) do
    param_refs =
      params
      |> Enum.map(fn {_var, spec} -> elem(spec, 1) end)
      |> MapSet.new()

    local_decls =
      body
      |> then(fn source ->
        Regex.scan(~r/ElmcValue \*([A-Za-z_][A-Za-z0-9_]*)\s*=/, source)
      end)
      |> Enum.map(fn [_, name] -> name end)
      |> MapSet.new()

    not MapSet.disjoint?(param_refs, local_decls)
  end

  defp branch_helper_params(branch, branch_env, subject_ref, expr_code, assignment_code) do
    excluded =
      case branch.pattern do
        %{kind: :var, name: name} when is_binary(name) -> MapSet.new([name])
        _ -> MapSet.new()
      end

    code = Enum.join([expr_code, assignment_code], "\n")

    ir_vars =
      branch.expr
      |> external_vars()
      |> MapSet.to_list()
      |> Enum.reject(&MapSet.member?(excluded, &1))

    code_vars = HelperParams.vars_in_c_source(code, branch_env)

    vars =
      (ir_vars ++ code_vars)
      |> Enum.uniq()
      |> Enum.sort()

    case HelperParams.collect(vars, branch_env) do
      :error ->
        :error

      {:ok, params} ->
        params =
          params
          |> maybe_add_subject_param(subject_ref)
          |> Enum.uniq_by(fn {_var, spec} -> spec end)

        {:ok, params}
    end
  end

  defp maybe_add_subject_param(params, subject_ref) when is_binary(subject_ref) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, subject_ref) do
      [{:__case_subject__, {:boxed, subject_ref}} | params]
    else
      params
    end
  end

  defp pattern_condition_code(subject, subject_ref, pattern, env) do
    case native_bool_pattern_condition(subject, pattern, env) do
      nil -> Patterns.pattern_condition(subject_ref, pattern, env)
      code -> code
    end
  end

  defp native_bool_pattern_condition(subject, pattern, env) do
    with name when is_binary(name) <- case_subject_name(subject),
         ref when is_binary(ref) <- EnvBindings.native_bool_binding(env, name) do
      case pattern do
        %{kind: :wildcard} -> "1"
        %{kind: :constructor, name: "True"} -> "(#{ref})"
        %{kind: :constructor, name: "False"} -> "!(#{ref})"
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp case_subject_name(subject) when is_binary(subject), do: subject
  defp case_subject_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp case_subject_name(_), do: nil

  defp external_vars(expr), do: external_vars(expr, MapSet.new())

  defp external_vars(%{op: :var, name: name}, bound) when is_binary(name) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp external_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound) do
    value_vars = external_vars(value_expr, bound)
    in_vars = external_vars(in_expr, MapSet.put(bound, name))
    MapSet.union(value_vars, in_vars)
  end

  defp external_vars(%{op: :lambda, args: args, body: body}, bound) when is_list(args) do
    lambda_bound = Enum.reduce(args, bound, &MapSet.put(&2, &1))
    external_vars(body, lambda_bound)
  end

  defp external_vars(%{op: :field_access, arg: arg}, bound) when is_binary(arg) do
    if MapSet.member?(bound, arg), do: MapSet.new(), else: MapSet.new([arg])
  end

  defp external_vars(expr, bound) when is_map(expr) do
    Enum.reduce(expr, MapSet.new(), fn
      {_key, value}, acc when is_map(value) or is_list(value) ->
        MapSet.union(acc, external_vars(value, bound))

      {_key, _value}, acc ->
        acc
    end)
  end

  defp external_vars(values, bound) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, external_vars(value, bound))
    end)
  end

  defp external_vars(_expr, _bound), do: MapSet.new()

  @spec battery_alert_case_probe(Types.compile_env(), term(), atom()) :: String.t()
  defp battery_alert_case_probe(_env, _branch_index, _position), do: ""

  defp branch_assignment_rc(env, out, function, call_args, counter) do
    {"", RcRuntimeEmit.assign_into(env, out, function, call_args), counter}
  end

  defp branch_assignment_int_literal(%{op: :int_literal, value: 0}, out, _env, counter),
    do: {"", "#{out} = elmc_int_zero();", counter}

  defp branch_assignment_int_literal(%{op: :int_literal} = expr, out, env, counter) do
    ref = IntLiteralRef.ref(expr, env)
    branch_assignment_rc(env, out, "elmc_new_int", ref, counter)
  end

  defp function_returns_bool?(env) when is_map(env) do
    case {Map.get(env, :__module__), Map.get(env, :__function_name__)} do
      {mod, name} when is_binary(mod) and is_binary(name) ->
        case Map.get(Map.get(env, :__program_decls__, %{}), {mod, name}) do
          %{type: type} -> Host.function_return_type(type) == "Bool"
          _ -> false
        end

      _ ->
        false
    end
  end

  defp put_declared_out(env, out) do
    Map.update(env, :__declared_outs__, MapSet.new([out]), &MapSet.put(&1, out))
  end

  defp put_case_subject_payload_type(env, subject) do
    case Expr.maybe_unwrapped_record_type(subject_expr(subject), env) do
      type when is_binary(type) -> Map.put(env, :__case_subject_payload_type__, type)
      _ -> env
    end
  end
end
