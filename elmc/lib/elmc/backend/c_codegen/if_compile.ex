defmodule Elmc.Backend.CCodegen.IfCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec compile(Types.ir_if_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(
        %{
          op: :if,
          cond: %{op: :int_literal, value: value},
          then_expr: then_expr,
          else_expr: else_expr
        },
        env,
        counter
      ) do
    Host.compile_expr(if(value != 0, do: then_expr, else: else_expr), env, counter)
  end

  def compile(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      ) do
    compile_branches(cond_expr, then_expr, else_expr, env, counter)
  end

  @spec compile_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_branches(cond_expr, then_expr, else_expr, env, counter) do
    cond do
      Host.native_bool_expr?(cond_expr, env) and Host.native_int_expr?(then_expr, env) and
          Host.native_int_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and NativeString.boxed_expr?(then_expr, env) and
          NativeString.boxed_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and NativeString.boxed_non_null_expr?(then_expr, env) and
          NativeString.boxed_non_null_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      true ->
        compile_boxed_cond(cond_expr, then_expr, else_expr, env, counter)
    end
  end

  @spec compile_native_bool_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter) do
    {cond_code, cond_ref, counter} = Host.compile_native_bool_expr(cond_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {then_code, then_assignment, counter} =
      CaseCompile.branch_assignment(then_expr, out, env, next)

    {else_code, else_assignment, counter} =
      CaseCompile.branch_assignment(else_expr, out, env, counter)

    then_body = maybe_extract_if_branch_helper(then_expr, env, out, then_code, then_assignment)
    else_body = maybe_extract_if_branch_helper(else_expr, env, out, else_code, else_assignment)

    code =
      Enum.join(
        [
          cond_code,
          "ElmcValue *#{out};",
          "if (#{cond_ref}) {",
          format_if_branch_body(then_body),
          "} else {",
          format_if_branch_body(else_body),
          "}"
        ],
        "\n"
      )

    {code, out, counter}
  end

  @spec compile_boxed_cond(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_boxed_cond(cond_expr, then_expr, else_expr, env, counter) do
    {cond_code, cond_var, counter} = Host.compile_expr(cond_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    {then_code, then_assignment, counter} =
      CaseCompile.branch_assignment(then_expr, out, env, next)

    {else_code, else_assignment, counter} =
      CaseCompile.branch_assignment(else_expr, out, env, counter)

    then_body = maybe_extract_if_branch_helper(then_expr, env, out, then_code, then_assignment)
    else_body = maybe_extract_if_branch_helper(else_expr, env, out, else_code, else_assignment)

    code =
      Enum.join(
        [
          cond_code,
          "ElmcValue *#{out};",
          "if (elmc_as_int(#{cond_var}) != 0) {",
          format_if_branch_body(then_body),
          "} else {",
          format_if_branch_body(else_body),
          "}",
          "elmc_release(#{cond_var});"
        ],
        "\n"
      )

    {code, out, counter}
  end

  defp format_if_branch_body(body) do
    Util.format_c_block(body, 4)
  end

  defp maybe_extract_if_branch_helper(expr, env, out, branch_code, assignment_code) do
    inline_body = format_if_branch_body(Enum.join([branch_code, assignment_code], "\n"))

    if extract_if_branch_helper?(env, inline_body) do
      case if_branch_helper_params(expr, env) do
        {:ok, params} ->
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_if_branch_helper_#{Util.safe_c_suffix(Map.get(env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(env, :__function_name__, "fn"))}_#{helper_id}"

          helper_out = "branch_out"
          helper_assignment = String.replace(assignment_code, "#{out} =", "#{helper_out} =")

          helper_param_decls =
            params
            |> Enum.map_join(", ", fn {_key, c_ref} -> "ElmcValue *#{c_ref}" end)

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
            ElmcValue *#{helper_out} = NULL;
          #{Util.indent(branch_code, 2)}
            #{helper_assignment}
            return #{helper_out};
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          call_args = Enum.map_join(params, ", ", fn {_key, c_ref} -> c_ref end)

          """
              #{out} = #{helper_name}(#{call_args});
          """

        :error ->
          inline_body
      end
    else
      inline_body
    end
  end

  defp extract_if_branch_helper?(env, body) do
    not Map.get(env, :__inside_lambda__, false) and
      Process.get(:elmc_generic_helper_defs) != nil and emitted_line_count(body) >= 70
  end

  defp emitted_line_count(code), do: code |> String.split("\n") |> length()

  defp if_branch_helper_params(expr, env) do
    params =
      expr
      |> external_vars()
      |> Enum.sort()
      |> Enum.reduce_while([], fn var, acc ->
        case Map.get(env, var) do
          c_ref when is_binary(c_ref) ->
            if c_identifier?(c_ref), do: {:cont, [{var, c_ref} | acc]}, else: {:halt, :error}

          _other ->
            if zero_arg_function_var?(env, var), do: {:cont, acc}, else: {:halt, :error}
        end
      end)

    case params do
      :error ->
        :error

      params ->
        {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_key, c_ref} -> c_ref end)}
    end
  end

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

  defp zero_arg_function_var?(env, var) do
    module_name = Map.get(env, :__module__, "Main")

    case Map.get(env, :__program_decls__, %{}) do
      %{} = decl_map ->
        case Map.get(decl_map, {module_name, var}) do
          %{args: args} when args in [[], nil] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp external_vars(expr), do: external_vars(expr, MapSet.new())

  defp external_vars(%{op: :var, name: name}, bound) when is_binary(name) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp external_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound) do
    value_vars = external_vars(value_expr, bound)
    in_vars = external_vars(in_expr, MapSet.put(bound, EnvBindings.binding_key(name)))
    MapSet.union(value_vars, in_vars)
  end

  defp external_vars(%{op: :lambda, args: args, body: body}, bound) when is_list(args) do
    lambda_bound =
      Enum.reduce(args, bound, fn arg, acc -> MapSet.put(acc, EnvBindings.binding_key(arg)) end)

    external_vars(body, lambda_bound)
  end

  defp external_vars(%{op: :field_access, arg: arg}, bound) when is_binary(arg) do
    key = EnvBindings.binding_key(arg)
    if MapSet.member?(bound, key), do: MapSet.new(), else: MapSet.new([key])
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
end
