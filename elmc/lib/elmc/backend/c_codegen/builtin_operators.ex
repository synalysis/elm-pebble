defmodule Elmc.Backend.CCodegen.BuiltinOperators do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Float, as: NativeFloat
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.CCodegen.OwnershipCompile
  alias Elmc.Backend.CCodegen.RuntimeCall
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @basics_operator_names ~w(
    __add__ __sub__ __mul__ __pow__ __fdiv__ __idiv__ __append__
    __eq__ __neq__ __lt__ __lte__ __gt__ __gte__
    modBy remainderBy round floor ceiling truncate toFloat
    abs negate not xor compare max min clamp
  )a

  @spec qualified_operator_name(String.t()) :: String.t() | nil
  def qualified_operator_name(target) when is_binary(target) do
    normalized = SpecialValues.normalize_special_target(target)

    case String.split(normalized, ".") do
      ["Basics", name] when is_binary(name) ->
        if Enum.member?(@basics_operator_names, name), do: name, else: nil

      _ ->
        nil
    end
  end

  @spec qualified_operator_member?(String.t(), [String.t()]) :: boolean()
  def qualified_operator_member?(target, operators)
      when is_binary(target) and is_list(operators) do
    case qualified_operator_name(target) do
      nil -> false
      name -> Enum.member?(operators, name)
    end
  end

  @spec call(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result_or_nil()
  def call("e", [], env, counter),
    do: Host.compile_expr(%{op: :float_literal, value: 2.718281828459045}, env, counter)

  def call("pi", [], env, counter),
    do: Host.compile_expr(%{op: :float_literal, value: 3.141592653589793}, env, counter)

  def call("LT", [], env, counter),
    do: Host.compile_expr(%{op: :int_literal, value: -1}, env, counter)

  def call("EQ", [], env, counter),
    do: Host.compile_expr(%{op: :int_literal, value: 0}, env, counter)

  def call("GT", [], env, counter),
    do: Host.compile_expr(%{op: :int_literal, value: 1}, env, counter)

  def call("__add__", [left, right], env, counter),
    do: int_binop(left, right, "+", env, counter)

  def call("__add__", args, env, counter) when length(args) in [0, 1],
    do: curried_binary("__add__", args, env, counter)

  def call("__sub__", [left, right], env, counter),
    do: int_binop(left, right, "-", env, counter)

  def call("__sub__", args, env, counter) when length(args) in [0, 1],
    do: curried_binary("__sub__", args, env, counter)

  def call("__mul__", [left, right], env, counter),
    do: int_binop(left, right, "*", env, counter)

  def call("__mul__", args, env, counter) when length(args) in [0, 1],
    do: curried_binary("__mul__", args, env, counter)

  def call("__pow__", [base, exponent], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_pow", args: [base, exponent]},
        env,
        counter
      )

  def call("__pow__", args, env, counter) when length(args) in [0, 1],
    do: curried_binary("__pow__", args, env, counter)

  def call("__fdiv__", [left, right], env, counter),
    do: float_div(left, right, env, counter)

  def call("__fdiv__", args, env, counter) when length(args) in [0, 1],
    do: curried_binary("__fdiv__", args, env, counter)

  def call("__idiv__", [left, right], env, counter),
    do: int_idiv(left, right, env, counter)

  def call("__idiv__", args, env, counter) when length(args) in [0, 1],
    do: curried_binary("__idiv__", args, env, counter)

  def call("__append__", [left, right], env, counter),
    do:
      Host.compile_expr(
        Elmc.Backend.CCodegen.RuntimeCall.flatten_append_ir(left, right),
        env,
        counter
      )

  def call("__append__", args, env, counter)
      when length(args) in [0, 1],
      do: curried_binary("__append__", args, env, counter)

  def call(name, [left, right], env, counter)
      when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"],
      do: compare_operator(left, right, name, env, counter)

  def call(name, args, env, counter)
      when name in ["__eq__", "__neq__", "__lt__", "__lte__", "__gt__", "__gte__"] and
             length(args) in [0, 1],
      do: curried_binary(name, args, env, counter)

  def call("modBy", [base, value], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
        env,
        counter
      )

  def call("remainderBy", [base, value], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_remainder_by", args: [base, value]},
        env,
        counter
      )

  def call("round", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_round", args: [x]},
        env,
        counter
      )

  def call("floor", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_floor", args: [x]},
        env,
        counter
      )

  def call("ceiling", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_ceiling", args: [x]},
        env,
        counter
      )

  def call("truncate", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_truncate", args: [x]},
        env,
        counter
      )

  def call("toFloat", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_to_float", args: [x]},
        env,
        counter
      )

  def call("sqrt", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_sqrt", args: [x]},
        env,
        counter
      )

  def call("logBase", [base, x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_log_base", args: [base, x]},
        env,
        counter
      )

  def call("sin", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_sin", args: [x]},
        env,
        counter
      )

  def call("cos", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_cos", args: [x]},
        env,
        counter
      )

  def call("tan", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_tan", args: [x]},
        env,
        counter
      )

  def call("acos", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_acos", args: [x]},
        env,
        counter
      )

  def call("asin", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_asin", args: [x]},
        env,
        counter
      )

  def call("atan", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_atan", args: [x]},
        env,
        counter
      )

  def call("atan2", [y, x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_atan2", args: [y, x]},
        env,
        counter
      )

  def call("degrees", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_degrees", args: [x]},
        env,
        counter
      )

  def call("radians", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_radians", args: [x]},
        env,
        counter
      )

  def call("turns", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_turns", args: [x]},
        env,
        counter
      )

  def call("fromPolar", [polar], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_from_polar", args: [polar]},
        env,
        counter
      )

  def call("toPolar", [point], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_to_polar", args: [point]},
        env,
        counter
      )

  def call("isNaN", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_is_nan", args: [x]},
        env,
        counter
      )

  def call("isInfinite", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_is_infinite", args: [x]},
        env,
        counter
      )

  def call("abs", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_abs", args: [x]},
        env,
        counter
      )

  def call("negate", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_negate", args: [x]},
        env,
        counter
      )

  def call("not", [x], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_not", args: [x]},
        env,
        counter
      )

  def call("xor", [a, b], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_xor", args: [a, b]},
        env,
        counter
      )

  def call("compare", [a, b], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_compare", args: [a, b]},
        env,
        counter
      )

  def call("max", [left, right], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_max", args: [left, right]},
        env,
        counter
      )

  def call("min", [left, right], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_min", args: [left, right]},
        env,
        counter
      )

  def call("clamp", [low, high, value], env, counter),
    do:
      Host.compile_expr(
        %{op: :runtime_call, function: "elmc_basics_clamp", args: [low, high, value]},
        env,
        counter
      )

  def call(_name, _args, _env, _counter), do: nil

  @spec curried_binary(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  defp curried_binary(name, [], env, counter) do
    Host.compile_expr(
      %{
        op: :lambda,
        args: ["__left", "__right"],
        body: %{
          op: :call,
          name: name,
          args: [%{op: :var, name: "__left"}, %{op: :var, name: "__right"}]
        }
      },
      env,
      counter
    )
  end

  defp curried_binary(name, [left], env, counter) do
    Host.compile_expr(
      %{
        op: :lambda,
        args: ["__right"],
        body: %{op: :call, name: name, args: [left, %{op: :var, name: "__right"}]}
      },
      env,
      counter
    )
  end

  defp float_operator_name("+"), do: "__add__"
  defp float_operator_name("-"), do: "__sub__"
  defp float_operator_name("*"), do: "__mul__"

  @spec int_binop(
          Types.ir_expr(),
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def int_binop(
        %{op: :int_literal, value: left},
        %{op: :int_literal, value: right},
        operator,
        _env,
        counter
      )
      when operator in ["+", "-", "*"] do
    value =
      case operator do
        "+" -> left + right
        "-" -> left - right
        "*" -> left * right
      end

    Host.compile_expr(%{op: :int_literal, value: value}, %{}, counter)
  end

  def int_binop(left, right, "-", env, counter) do
    case RuntimeCall.compile_int_sub_list_length(left, right, env, counter) do
      {:ok, code, out, c} ->
        {code, out, c}

      :error ->
        int_binop_dispatch(left, right, "-", env, counter)
    end
  end

  def int_binop(left, right, operator, env, counter) when operator in ["+", "*"] do
    int_binop_dispatch(left, right, operator, env, counter)
  end

  defp int_binop_dispatch(left, right, operator, env, counter) when operator in ["+", "-", "*"] do
    case ConstantInt.literal_binop(operator, left, right, env) do
      {:ok, value} ->
        Host.compile_expr(%{op: :int_literal, value: value}, env, counter)

      :error ->
        int_binop_dispatch_values(left, right, operator, env, counter)
    end
  end

  defp int_binop_dispatch(left, right, operator, env, counter) do
    int_binop_dispatch_values(left, right, operator, env, counter)
  end

  defp int_binop_dispatch_values(left, right, operator, env, counter) do
    cond do
      both_native_int_operands?(left, right, env) ->
        {left_code, left_var, counter} = compile_native_int_operand(left, env, counter)
        {right_code, right_var, counter} = compile_native_int_operand(right, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        code = """
        #{left_code}
          #{right_code}
          ElmcValue *#{out} = elmc_new_int(#{left_var} #{operator} #{right_var});
        """

        {code, out, next}

      Host.native_float_expr?(left, env) and Host.native_float_expr?(right, env) ->
        NativeFloat.compile_boxed(
          %{op: :call, name: float_operator_name(operator), args: [left, right]},
          env,
          counter
        )

      true ->
        {left_code, left_var, counter} = Host.compile_expr(left, env, counter)
        {right_code, right_var, counter} = Host.compile_expr(right, env, counter)
        next = counter + 1
        out = "tmp_#{next}"

        code = """
        #{left_code}
          #{right_code}
              ElmcValue *#{out} =
                  ((#{left_var} && #{left_var}->tag == ELMC_TAG_FLOAT) || (#{right_var} && #{right_var}->tag == ELMC_TAG_FLOAT))
                      ? elmc_new_float(elmc_as_float(#{left_var}) #{operator} elmc_as_float(#{right_var}))
                      : elmc_new_int(elmc_as_int(#{left_var}) #{operator} elmc_as_int(#{right_var}));
          elmc_release(#{left_var});
          elmc_release(#{right_var});
        """

        {code, out, next}
    end
  end

  @spec both_native_int_operands?(Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  defp both_native_int_operands?(left, right, env) do
    native_int_operand_available?(left, env) and native_int_operand_available?(right, env)
  end

  @spec native_int_operand_available?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defp native_int_operand_available?(%{op: :var, name: name}, env)
       when is_binary(name) or is_atom(name) do
    Host.native_int_expr?(%{op: :var, name: name}, env) or
      is_binary(EnvBindings.native_int_binding(env, name))
  end

  defp native_int_operand_available?(expr, env),
    do: Host.native_int_expr?(expr, env) or ConstantInt.native_let_value?(expr, env)

  @spec compile_native_int_operand(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter()}
  defp compile_native_int_operand(expr, env, counter) do
    case ConstantInt.compile_native_operand(expr, env, counter) do
      {:ok, code, ref, c} ->
        {code, ref, c}

      :error ->
        case expr do
          %{op: :var, name: name} ->
            case EnvBindings.native_int_binding(env, name) do
              ref when is_binary(ref) ->
                {"", ref, counter}

              nil ->
                {code, ref, c} = Host.compile_native_int_expr(expr, env, counter)
                {code, ref, c}
            end

          _ ->
            {code, ref, c} = Host.compile_native_int_expr(expr, env, counter)
            {code, ref, c}
        end
    end
  end

  @spec int_idiv(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def int_idiv(left, right, env, counter) do
    {left_code, left_var, counter} = Host.compile_native_int_expr(left, env, counter)

    {code, out, counter} =
      case NativeInt.static_nonzero_int_value(right, env) do
        value when is_integer(value) ->
          next = counter + 1
          out = "tmp_#{next}"

          """
          #{left_code}
            ElmcValue *#{out} = elmc_new_int(#{left_var} / #{value});
          """
          |> then(&{&1, out, next})

        nil ->
          {right_code, right_var, counter} = Host.compile_native_int_expr(right, env, counter)
          next = counter + 1
          out = "tmp_#{next}"

          """
          #{left_code}
            #{right_code}
            const elmc_int_t __den_#{next} = #{right_var};
            ElmcValue *#{out} = elmc_new_int(__den_#{next} == 0 ? 0 : (#{left_var} / __den_#{next}));
          """
          |> then(&{&1, out, next})
      end

    {code, out, counter}
  end

  @spec float_div(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def float_div(left, right, env, counter) do
    if Host.native_float_expr?(left, env) and Host.native_float_expr?(right, env) do
      NativeFloat.compile_boxed(
        %{op: :call, name: "__fdiv__", args: [left, right]},
        env,
        counter
      )
    else
      {left_code, left_var, counter} = Host.compile_expr(left, env, counter)
      {right_code, right_var, counter} = Host.compile_expr(right, env, counter)
      next = counter + 1
      out = "tmp_#{next}"

      code = """
      #{left_code}
        #{right_code}
          const double __denf_#{next} = elmc_as_float(#{right_var});
          const double __numf_#{next} = elmc_as_float(#{left_var});
        ElmcValue *#{out} = elmc_new_float(__numf_#{next} / __denf_#{next});
        elmc_release(#{left_var});
        elmc_release(#{right_var});
      """

      {code, out, next}
    end
  end

  @spec compare_operator(
          Types.ir_expr(),
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def compare_operator(left, right, operator, env, counter) do
    cond do
      Host.native_int_compare_safe?(operator, left, right, env) ->
        int_compare_operator(left, right, operator, env, counter)

      list_int_compare_safe?(operator, left, right, env) ->
        list_int_compare_operator(left, right, operator, env, counter)

      true ->
        {left_code, left_var, counter, left_borrowed?} =
          compile_compare_operand(left, env, counter)

        {right_code, right_var, counter, right_borrowed?} =
          compile_compare_operand(right, env, counter)

        next = counter + 1
        out = "tmp_#{next}"
        left_release = compare_operand_release(env, left_var, left_borrowed?)
        right_release = compare_operand_release(env, right_var, right_borrowed?)

        code =
          case operator do
            "__eq__" ->
              """
              #{left_code}
                #{right_code}
                ElmcValue *#{out} = elmc_new_bool(elmc_value_equal(#{left_var}, #{right_var}));
                #{left_release}#{right_release}\
              """

            "__neq__" ->
              """
              #{left_code}
                #{right_code}
                ElmcValue *#{out} = elmc_new_bool(!elmc_value_equal(#{left_var}, #{right_var}));
                #{left_release}#{right_release}\
              """

            _ ->
              comparison =
                case operator do
                  "__lt__" -> "<"
                  "__lte__" -> "<="
                  "__gt__" -> ">"
                  "__gte__" -> ">="
                end

              """
              #{left_code}
                #{right_code}
                ElmcValue *__cmp_#{next} = elmc_basics_compare(#{left_var}, #{right_var});
                ElmcValue *#{out} = elmc_new_bool(elmc_as_int(__cmp_#{next}) #{comparison} 0);
                elmc_release(__cmp_#{next});
                #{left_release}#{right_release}\
              """
          end

        {code, out, next}
    end
  end

  defp list_int_compare_safe?(operator, left, right, env)
       when operator in ["__eq__", "__neq__"] do
    TypedReturn.list_int_expr?(left, env) and TypedReturn.list_int_expr?(right, env)
  end

  defp list_int_compare_safe?(_operator, _left, _right, _env), do: false

  defp list_int_compare_operator(left, right, operator, env, counter) do
    {left_code, left_var, counter, left_borrowed?} = compile_compare_operand(left, env, counter)

    {right_code, right_var, counter, right_borrowed?} =
      compile_compare_operand(right, env, counter)

    next = counter + 1
    out = "tmp_#{next}"
    left_release = compare_operand_release(env, left_var, left_borrowed?)
    right_release = compare_operand_release(env, right_var, right_borrowed?)
    negate = if operator == "__neq__", do: "!", else: ""

    code = """
    #{left_code}
      #{right_code}
      ElmcValue *#{out} = elmc_new_bool(#{negate}elmc_list_equal_int(#{left_var}, #{right_var}));
      #{left_release}#{right_release}\
    """

    {code, out, next}
  end

  defp compile_compare_operand(%{op: :var, name: name}, env, counter) do
    case EnvBindings.lookup_binding(env, name) do
      source when is_binary(source) ->
        if c_identifier?(source) do
          {"", source, counter, true}
        else
          {code, var, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
          {code, var, counter, false}
        end

      _ ->
        {code, var, counter} = Host.compile_expr(%{op: :var, name: name}, env, counter)
        {code, var, counter, false}
    end
  end

  defp compile_compare_operand(expr, env, counter) do
    {code, var, counter} = Host.compile_expr(expr, env, counter)
    {code, var, counter, false}
  end

  defp compare_operand_release(_env, _var, true), do: ""

  defp compare_operand_release(env, var, false) do
    OwnershipCompile.release_if_owned(env, var, :compare)
  end

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

  @spec int_compare_operator(
          Types.ir_expr(),
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp int_compare_operator(
         %{op: :int_literal, value: left},
         %{op: :int_literal, value: right},
         operator,
         _env,
         counter
       ) do
    result =
      case operator do
        "__eq__" -> left == right
        "__neq__" -> left != right
        "__lt__" -> left < right
        "__lte__" -> left <= right
        "__gt__" -> left > right
        "__gte__" -> left >= right
      end

    next = counter + 1
    out = "tmp_#{next}"
    {"ElmcValue *#{out} = elmc_new_bool(#{if(result, do: 1, else: 0)});", out, next}
  end

  defp int_compare_operator(left, right, operator, env, counter) do
    {left_code, left_var, counter} = Host.compile_native_int_expr(left, env, counter)
    {right_code, right_var, counter} = Host.compile_native_int_expr(right, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    comparison =
      case operator do
        "__eq__" -> "=="
        "__neq__" -> "!="
        "__lt__" -> "<"
        "__lte__" -> "<="
        "__gt__" -> ">"
        "__gte__" -> ">="
      end

    code = """
    #{left_code}
      #{right_code}
      ElmcValue *#{out} = elmc_new_bool(#{left_var} #{comparison} #{right_var});
    """

    {code, out, next}
  end
end
