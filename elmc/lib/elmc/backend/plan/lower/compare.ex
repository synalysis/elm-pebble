defmodule Elmc.Backend.Plan.Lower.Compare do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.BuiltinUnion
  alias Elmc.Backend.CCodegen.{Host, TypeParsing}
  alias Elmc.Backend.CCodegen.Native.TypedReturn
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @nothing_names ~w(Nothing Maybe.Nothing)

  @spec compile(Types.compare_input(), Context.t(), Builder.t()) :: Types.compile_reg_result()
  def compile(%{op: :compare, kind: kind, left: left, right: right}, ctx, b) do
    compile(%{kind: kind, left: left, right: right}, ctx, b)
  end

  def compile(%{kind: kind, left: left, right: right}, ctx, b) do
    case empty_list_compare(kind, left, right) do
      {:ok, list_expr, compare_kind} ->
        compile_empty_list_compare(list_expr, compare_kind, ctx, b)

      :error ->
        compile_after_empty_list(kind, left, right, ctx, b)
    end
  end

  def compile(_, _, _), do: :unsupported

  defp compile_after_empty_list(kind, left, right, ctx, b) do
    case maybe_vs_nothing_compare(kind, left, right) do
      {:ok, maybe_expr, compare_kind} ->
        compile_maybe_vs_nothing(maybe_expr, compare_kind, ctx, b)

      :error ->
        case union_ctor_equality_compare(kind, left, right) do
          {:ok, subject_expr, ctor_name, compare_kind} ->
            compile_union_ctor_equality(subject_expr, ctor_name, compare_kind, ctx, b)

          :error ->
            case Elmc.Backend.Plan.Lower.PebbleWatchTrig.try_compile_compare(
                   %{kind: kind, left: left, right: right},
                   ctx,
                   b
                 ) do
              {:ok, reg, b1} ->
                {:ok, reg, b1}

              :unsupported ->
                compile_generic_compare(kind, left, right, ctx, b)
            end
        end
    end
  end

  @spec compile_generic_compare(atom(), Types.expr(), Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_reg_result()

  defp compile_generic_compare(kind, left, right, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, left_reg, left_owned?, b1} <- compile_operand(left, operand_ctx, b),
         {:ok, right_reg, right_owned?, b2} <- compile_operand(right, operand_ctx, b1) do
      {reg, b3} = Builder.fresh_reg(b2)

      consumes =
        [left_reg, right_reg]
        |> Enum.zip([left_owned?, right_owned?])
        |> Enum.flat_map(fn
          {r, true} -> [r]
          _ -> []
        end)

      borrows =
        [left_reg, right_reg]
        |> Enum.reject(&(&1 in consumes))

      {_, b4} =
        Builder.emit(b3, :compare, %{
          dest: reg,
          args: %{
            kind: kind || :eq,
            left: left_reg,
            right: right_reg,
            mode: compare_mode(kind || :eq, left, right, ctx)
          },
          effects: %{
            produces: {:owned, reg},
            consumes: consumes,
            borrows: borrows,
            fallible: false
          }
        })

      {:ok, reg, b4}
    else
      _ -> :unsupported
    end
  end

  @spec compile_maybe_vs_nothing(Types.expr(), atom(), Context.t(), Builder.t()) ::
          Types.compile_reg_result()

  defp compile_maybe_vs_nothing(maybe_expr, :eq, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, subj_owned?, b1} <- compile_operand(maybe_expr, operand_ctx, b),
         {:ok, nothing_reg, b2} <- emit_test_maybe_nothing(subj_reg, b1),
         {reg, b3} = Builder.fresh_reg(b2) do
      {_, b4} =
        Builder.emit(b3, :test_bool, %{
          dest: reg,
          args: %{subject: nothing_reg, want_true: true},
          effects: %{
            produces: {:owned, reg},
            consumes: [nothing_reg],
            borrows: [],
            fallible: false
          }
        })

      b5 = maybe_consume_owned(b4, subj_reg, subj_owned?)
      {:ok, reg, b5}
    else
      _ -> :unsupported
    end
  end

  defp compile_maybe_vs_nothing(maybe_expr, :neq, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, subj_owned?, b1} <- compile_operand(maybe_expr, operand_ctx, b),
         {:ok, nothing_reg, b2} <- emit_test_maybe_nothing(subj_reg, b1),
         {reg, b3} = Builder.fresh_reg(b2) do
      {_, b4} =
        Builder.emit(b3, :test_bool, %{
          dest: reg,
          args: %{subject: nothing_reg, want_true: false},
          effects: %{
            produces: {:owned, reg},
            consumes: [nothing_reg],
            borrows: [],
            fallible: false
          }
        })

      b5 = maybe_consume_owned(b4, subj_reg, subj_owned?)
      {:ok, reg, b5}
    else
      _ -> :unsupported
    end
  end

  @spec compile_union_ctor_equality(Types.expr(), String.t(), atom(), Context.t(), Builder.t()) ::
          Types.compile_reg_result()

  defp compile_union_ctor_equality(subject_expr, ctor_name, kind, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with tag when is_integer(tag) <- union_ctor_tag(ctor_name),
         {:ok, subj_reg, subj_owned?, b1} <- compile_operand(subject_expr, operand_ctx, b),
         {:ok, tag_reg, b2} <- emit_test_ctor_tag(subj_reg, tag, ctor_name, b1),
         {reg, b3} = Builder.fresh_reg(b2) do
      {_, b4} =
        Builder.emit(b3, :test_bool, %{
          dest: reg,
          args: %{subject: tag_reg, want_true: kind == :eq},
          effects: %{
            produces: {:owned, reg},
            consumes: [tag_reg],
            borrows: [],
            fallible: false
          }
        })

      b5 = maybe_consume_owned(b4, subj_reg, subj_owned?)
      {:ok, reg, b5}
    else
      _ -> :unsupported
    end
  end

  @spec union_ctor_equality_compare(atom(), Types.expr(), Types.expr()) ::
          {:ok, Types.expr(), String.t(), atom()} | :error

  defp union_ctor_equality_compare(kind, left, right) when kind in [:eq, :neq] do
    cond do
      union_ctor_ref?(right) and not maybe_ctor_ref?(right) ->
        {:ok, left, ctor_ref_name(right), kind}

      union_ctor_ref?(left) and not maybe_ctor_ref?(left) ->
        {:ok, right, ctor_ref_name(left), kind}

      union_ctor_literal?(right) and not maybe_ctor_literal?(right) ->
        {:ok, left, union_ctor_literal_name(right), kind}

      union_ctor_literal?(left) and not maybe_ctor_literal?(left) ->
        {:ok, right, union_ctor_literal_name(left), kind}

      true ->
        :error
    end
  end

  defp union_ctor_equality_compare(_kind, _left, _right), do: :error

  @spec union_ctor_ref?(map() | term()) :: boolean()

  defp union_ctor_ref?(%{op: :constructor_ref, target: target}) when is_binary(target), do: true
  defp union_ctor_ref?(_), do: false

  @spec maybe_ctor_ref?(Types.expr()) :: boolean()

  defp maybe_ctor_ref?(expr) do
    case expr do
      %{op: :constructor_ref, target: target} when is_binary(target) ->
        short_ctor_name(target) in @nothing_names

      _ ->
        false
    end
  end

  @spec ctor_ref_name(map()) :: String.t()

  defp ctor_ref_name(%{target: target}) when is_binary(target), do: target

  @spec union_ctor_literal?(map() | term()) :: boolean()

  defp union_ctor_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor), do: true
  defp union_ctor_literal?(_), do: false

  @spec maybe_ctor_literal?(Types.expr()) :: boolean()

  defp maybe_ctor_literal?(expr) do
    case expr do
      %{op: :int_literal, union_ctor: ctor} when is_binary(ctor) ->
        BuiltinUnion.maybe_nothing_literal?(%{op: :int_literal, union_ctor: ctor})

      _ ->
        false
    end
  end

  @spec union_ctor_literal_name(map()) :: String.t()

  defp union_ctor_literal_name(%{union_ctor: ctor}) when is_binary(ctor), do: ctor

  @spec union_ctor_tag(String.t()) :: non_neg_integer() | nil

  defp union_ctor_tag(name) when is_binary(name) do
    tags = Process.get(:elmc_constructor_tags, %{})
    Elmc.Backend.CCodegen.IRQueries.lookup_tag(tags, name)
  end

  @spec emit_test_ctor_tag(Types.reg(), integer(), String.t(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()}

  defp emit_test_ctor_tag(subject_reg, tag, ctor_name, b)
       when is_integer(tag) and is_binary(ctor_name) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_ctor_tag, %{
        dest: reg,
        args: %{subject: subject_reg, tag: tag, union_ctor: ctor_name},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  @spec empty_list_compare(atom(), Types.expr(), Types.expr()) ::
          {:ok, Types.expr(), atom()} | :error

  defp empty_list_compare(kind, left, right) when kind in [:eq, :neq] do
    cond do
      empty_list_ref?(right) -> {:ok, left, kind}
      empty_list_ref?(left) -> {:ok, right, kind}
      true -> :error
    end
  end

  defp empty_list_compare(_kind, _left, _right), do: :error

  defp empty_list_ref?(%{op: :list_literal, items: []}), do: true
  defp empty_list_ref?(%{op: :list_literal, elements: []}), do: true
  defp empty_list_ref?(%{op: :static_list, elements: []}), do: true
  defp empty_list_ref?(%{op: :constructor, name: name}) when name in ["[]", "List.[]"], do: true

  defp empty_list_ref?(%{op: :constructor_call, target: target, args: []})
       when target in ["[]", "List.[]"],
       do: true

  defp empty_list_ref?(%{op: :runtime_call, function: function})
       when function in ["elmc_list_nil", "list_nil"],
       do: true

  defp empty_list_ref?(_), do: false

  defp compile_empty_list_compare(list_expr, kind, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, subj_reg, subj_owned?, b1} <- compile_operand(list_expr, operand_ctx, b),
         {:ok, empty_reg, b2} <- emit_test_list_empty(subj_reg, b1),
         {reg, b3} = Builder.fresh_reg(b2) do
      {_, b4} =
        Builder.emit(b3, :test_bool, %{
          dest: reg,
          args: %{subject: empty_reg, want_true: kind == :eq},
          effects: %{
            produces: {:owned, reg},
            consumes: [empty_reg],
            borrows: [],
            fallible: false
          }
        })

      b5 = maybe_consume_owned(b4, subj_reg, subj_owned?)
      {:ok, reg, b5}
    else
      _ -> :unsupported
    end
  end

  defp emit_test_list_empty(subj_reg, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_list_empty, %{
        dest: reg,
        args: %{reg: subj_reg},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [subj_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  @spec maybe_vs_nothing_compare(atom(), Types.expr(), Types.expr()) ::
          {:ok, Types.expr(), atom()} | :error

  defp maybe_vs_nothing_compare(kind, left, right)
       when kind in [:eq, :neq] do
    cond do
      nothing_literal?(right) -> {:ok, left, kind}
      nothing_literal?(left) -> {:ok, right, kind}
      true -> :error
    end
  end

  defp maybe_vs_nothing_compare(_kind, _left, _right), do: :error

  @spec nothing_literal?(map() | Types.expr()) :: boolean()

  defp nothing_literal?(%{op: :constructor_call, target: target}) when is_binary(target) do
    short_ctor_name(target) in @nothing_names
  end

  defp nothing_literal?(%{op: :constructor_ref, target: target}) when is_binary(target) do
    short_ctor_name(target) in @nothing_names
  end

  defp nothing_literal?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    BuiltinUnion.maybe_nothing_literal?(%{op: :int_literal, union_ctor: ctor})
  end

  defp nothing_literal?(expr), do: BuiltinUnion.maybe_nothing_literal?(expr)

  @spec emit_test_maybe_nothing(Types.reg(), Builder.t()) :: {:ok, Types.reg(), Builder.t()}

  defp emit_test_maybe_nothing(subj_reg, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_maybe_nothing, %{
        dest: reg,
        args: %{reg: subj_reg},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [subj_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  @spec maybe_consume_owned(Builder.t(), Types.reg(), boolean()) :: Builder.t()

  defp maybe_consume_owned(b, _reg, false), do: b
  defp maybe_consume_owned(b, _reg, true), do: b

  @spec compile_operand(Types.expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg(), boolean(), Builder.t()} | :unsupported

  defp compile_operand(expr, ctx, b) do
    case Expr.compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, operand_owned?(expr), b1}
      other -> other
    end
  end

  @spec operand_owned?(map() | term()) :: boolean()

  defp operand_owned?(%{op: :field_access}), do: true

  defp operand_owned?(%{op: op})
       when op in [:int_literal, :bool_literal, :string_literal, :cmd_none, :sub_none],
       do: true

  defp operand_owned?(_), do: false

  @spec short_ctor_name(String.t()) :: String.t()

  defp short_ctor_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  @spec compare_mode(atom(), Types.expr(), Types.expr(), Context.t()) :: atom()

  defp compare_mode(kind, left, right, ctx) do
    mode = compare_equality_mode(left, right, ctx)
    env = type_env(ctx)

    cond do
      # Ordering must never use pointer identity. Polymorphic `number` payloads
      # (elm-units `Quantity.greaterThan (Quantity y) (Quantity x) = x > y`) have no
      # Int/Float type in the env, so mode would be `:pointer` and `i32.gt_s` on
      # handles follows allocation order — `Quantity.abs` boxes fresh Ints each
      # call, so Light.soft's intensity swap recurses forever.
      #
      # Prefer float when either side looks like Float (including `__mul__` trees
      # from `Frame3d.isRightHanded`'s triple product); `as_int` truncates and
      # turns `det > 0` into a false negative for |det| < 1.
      mode == :pointer and kind in [:gt, :gte, :lt, :lte] ->
        if float_compare_pair?(left, right, env), do: :float_boxed, else: :int_boxed

      # Elm `==` on Int/Bool is by value. Pointer `i32.eq` breaks
      # `Transformation.compose`'s `t1.isRightHanded == t2.isRightHanded`
      # (distinct True Int boxes). Prefer `:int_boxed` for unknown pointer
      # shapes, but never for Maybe/Result/List/tuple/record — `elmc_as_int`
      # returns 0 for those tags, so `Nothing /= Just day` became `0 == 0`
      # and YES never requested sun/weather.
      #
      # If either side is an Int (literal or typed), keep `:int_boxed`. Nested
      # HOF params can be mis-typed as the enclosing function's `List Int` arg
      # (`lambda_param_types_from_root`), which would otherwise force `:value`
      # and emit `elmc_value_equal(n, 0)` — a null pointer, not Int zero.
      mode == :pointer and kind in [:eq, :neq] ->
        if structural_equality_pair?(left, right, env) and
             not (int_equality_operand?(left, env) or int_equality_operand?(right, env)) do
          :value
        else
          :int_boxed
        end

      true ->
        mode
    end
  end

  @spec compare_equality_mode(Types.expr(), Types.expr(), Context.t()) :: atom()

  defp compare_equality_mode(left, right, ctx) do
    env = type_env(ctx)

    cond do
      boxed_bool_test_expr?(left) or boxed_bool_test_expr?(right) ->
        :bool_scalar

      TypedReturn.list_int_expr?(left, env) and TypedReturn.list_int_expr?(right, env) ->
        :list_int

      string_compare_pair?(left, right, env) ->
        :string

      # Float == 0 / Float < 1 must unbox — pointer i32.eq on handles never
      # terminates Scene3d-style countdown loops (`stripIndex == 0`).
      float_compare_pair?(left, right, env) ->
        :float_boxed

      int_equality_operand?(left, env) and int_equality_operand?(right, env) ->
        :int_boxed

      true ->
        :pointer
    end
  end

  @spec float_compare_pair?(Types.expr(), Types.expr(), Types.compile_env()) :: boolean()

  defp float_compare_pair?(left, right, env) do
    left_float? = float_equality_operand?(left, env)
    right_float? = float_equality_operand?(right, env)
    left_num? = numeric_literal_operand?(left)
    right_num? = numeric_literal_operand?(right)

    (left_float? and (right_float? or right_num?)) or
      (right_float? and (left_float? or left_num?))
  end

  @spec float_equality_operand?(map() | Types.expr(), Types.compile_env()) :: boolean()

  defp float_equality_operand?(%{op: :float_literal}, _env), do: true

  # Matrix4/VectorN.toRecord fields are always Floats; without a type env entry,
  # `projectionType == 0` was lowered as pointer i32.eq and never matched.
  # Prefer TypedReturn (which already applies the MJS toRecord Float heuristic).
  # Do not second-guess untyped x/y/z/w — Ui.Point / game rects are Int.
  defp float_equality_operand?(%{op: :field_access, field: field} = expr, env)
       when is_binary(field) do
    case TypedReturn.expr_type(expr, env) do
      "Float" -> true
      "Int" -> false
      _ -> false
    end
  end

  defp float_equality_operand?(%{op: :record_access, field: field}, _env)
       when is_binary(field) do
    # record_access has no TypedReturn clause; keep matrix-component heuristic only.
    match?(<<"m", r, c>> when r in ?1..?4 and c in ?1..?4, field)
  end

  # Polymorphic Basics operators on Float operands stay untyped (`number`); walk
  # the call tree so `a * e * i + … > 0` selects float_boxed, not truncating int.
  defp float_equality_operand?(%{op: :call, name: name, args: args}, env)
       when name in ["__add__", "__sub__", "__mul__", "__fdiv__", "/"] do
    Enum.any?(List.wrap(args), &float_equality_operand?(&1, env))
  end

  defp float_equality_operand?(%{op: :qualified_call, target: target, args: args}, env)
       when is_binary(target) do
    short = target |> String.split(".") |> List.last()

    if short in ["add", "sub", "mul", "fdiv"] do
      Enum.any?(List.wrap(args), &float_equality_operand?(&1, env))
    else
      TypedReturn.expr_type(%{op: :qualified_call, target: target, args: args}, env) == "Float"
    end
  end

  defp float_equality_operand?(expr, env) do
    TypedReturn.expr_type(expr, env) == "Float"
  end

  @spec numeric_literal_operand?(map() | term()) :: boolean()

  defp numeric_literal_operand?(%{op: :int_literal}), do: true
  defp numeric_literal_operand?(%{op: :float_literal}), do: true
  defp numeric_literal_operand?(_), do: false

  @spec boxed_bool_test_expr?(map() | Types.expr()) :: boolean()

  defp boxed_bool_test_expr?(%{op: :runtime_call, function: function}) when is_binary(function) do
    function in [
      "elmc_maybe_is_nothing",
      "elmc_list_is_empty",
      "maybe_is_nothing",
      "list_is_empty"
    ]
  end

  defp boxed_bool_test_expr?(%{op: :qualified_call, target: target}) when is_binary(target) do
    target in ["List.isEmpty", "Maybe.isNothing"]
  end

  defp boxed_bool_test_expr?(%{op: :call, name: name}) when is_binary(name) do
    name in ["isEmpty", "isNothing"]
  end

  defp boxed_bool_test_expr?(_expr), do: false

  @spec string_compare_pair?(Types.expr(), Types.expr(), Types.compile_env()) :: boolean()

  defp string_compare_pair?(left, right, env) do
    left_kind = string_operand_kind(left, env)
    right_kind = string_operand_kind(right, env)

    (left_kind == :string and right_kind != :non_string) or
      (right_kind == :string and left_kind != :non_string)
  end

  @spec string_operand_kind(map() | Types.expr(), Types.compile_env()) ::
          :string | :non_string | :unknown

  defp string_operand_kind(%{op: :string_literal}, _env), do: :string

  defp string_operand_kind(%{op: :runtime_call, function: function}, _env)
       when function in ["new_immortal_string", "elmc_new_immortal_string"],
       do: :string

  defp string_operand_kind(%{op: :call, name: name}, _env)
       when name in ["toString", "String.fromInt"],
       do: :string

  defp string_operand_kind(expr, env) do
    case TypedReturn.expr_type(expr, env) do
      "String" -> :string
      "Int" -> :non_string
      _ -> :unknown
    end
  end

  @spec structural_equality_pair?(Types.expr(), Types.expr(), Types.compile_env()) :: boolean()

  defp structural_equality_pair?(left, right, env) do
    structural_equality_operand?(left, env) or structural_equality_operand?(right, env)
  end

  @spec structural_equality_operand?(map() | Types.expr(), Types.compile_env()) :: boolean()

  defp structural_equality_operand?(%{op: :constructor, name: name}, _env)
       when name in ["Just", "Nothing", "Ok", "Err", "Maybe.Just", "Maybe.Nothing", "Result.Ok", "Result.Err"],
       do: true

  defp structural_equality_operand?(%{op: :call, name: name}, _env)
       when name in ["Just", "Nothing", "Ok", "Err"],
       do: true

  defp structural_equality_operand?(%{op: :qualified_call, target: target}, _env)
       when target in ["Maybe.Just", "Maybe.Nothing", "Result.Ok", "Result.Err"],
       do: true

  defp structural_equality_operand?(%{op: :runtime_call, function: function}, _env)
       when function in [
              "elmc_maybe_just",
              "elmc_maybe_just_own",
              "elmc_maybe_nothing",
              "maybe_just",
              "maybe_just_own",
              "maybe_nothing"
            ],
       do: true

  defp structural_equality_operand?(expr, env) do
    case TypedReturn.expr_type(expr, env) do
      "Maybe" <> _ -> true
      "Result" <> _ -> true
      "List" <> _ -> true
      "(" <> _ -> true
      type when is_binary(type) -> String.contains?(type, "{")
      _ -> false
    end
  end

  @spec int_equality_operand?(map() | Types.expr(), Types.compile_env()) :: boolean()

  defp int_equality_operand?(%{op: :int_literal}, _env), do: true

  defp int_equality_operand?(%{op: :string_length_expr}, _env), do: true

  defp int_equality_operand?(%{op: :runtime_call, function: function}, _env)
       when function in [
              "elmc_string_length",
              "elmc_string_length_val",
              "elmc_string_length_boxed",
              "string_length_boxed"
            ],
       do: true

  defp int_equality_operand?(%{op: :qualified_call, target: target}, _env)
       when target in ["String.length", "Basics.String.length"],
       do: true

  defp int_equality_operand?(expr, env) do
    case TypedReturn.expr_type(expr, env) do
      "Int" -> true
      _ -> false
    end
  end

  @spec type_env(Context.t()) :: Types.compile_env()

  defp type_env(%Context{} = ctx) do
    %{
      __module__: ctx.module || "Main",
      __var_types__:
        param_var_types(ctx)
        |> Map.merge(ctx.local_types),
      __program_decls__: ctx.decl_map,
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  @spec param_var_types(Context.t() | term()) :: %{optional(String.t()) => String.t()}

  defp param_var_types(%Context{decl_map: decl_map, module: module, params: params, function_name: fun})
       when is_binary(module) and is_binary(fun) and is_list(params) do
    with decl when is_map(decl) <- Map.get(decl_map, {module, fun}, %{}),
         type when is_binary(type) <- Map.get(decl, :type),
         arg_types when is_list(arg_types) <- TypeParsing.function_arg_types(type) do
      params
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {name, idx}, acc ->
        case Enum.at(arg_types, idx) do
          arg_type when is_binary(arg_type) ->
            Map.put(acc, name, Host.normalize_type_name(arg_type))

          _ ->
            acc
        end
      end)
    else
      _ -> %{}
    end
  end

  defp param_var_types(_), do: %{}
end
