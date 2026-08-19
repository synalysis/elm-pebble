defmodule Elmc.Backend.Plan.Lower.IntCall do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.{FunctionCallAbi, FunctionEmit}
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.Plan.Lower.{Arith, Expr}
  alias Elmc.Backend.Plan.{Builder, Context, Types}

  @binary_ops %{
    "__add__" => :add_vars,
    "__mul__" => :mul_vars,
    "__sub__" => :sub_vars,
    "__idiv__" => :idiv_vars
  }

  @runtime_ops %{
    "modBy" => "elmc_basics_mod_by",
    "Basics.modBy" => "elmc_basics_mod_by",
    "remainderBy" => "elmc_basics_remainder_by",
    "Basics.remainderBy" => "elmc_basics_remainder_by",
    "Basics.min" => "elmc_basics_min",
    "Basics.max" => "elmc_basics_max"
  }

  @spec compile(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile(%{op: :call, name: name, args: [left, right]}, ctx, b) when is_binary(name) do
    cond do
      name == "__fdiv__" ->
        Arith.emit_boxed_binop(:fdiv, left, right, ctx, b)

      name == "__pow__" ->
        compile_runtime_binop_with_native_box("elmc_basics_pow", left, right, ctx, b)

      # Proven native-int only. Bare vars / field accesses may be Float
      # (Scene3d `center.x * scale` must not become as_int+i32.mul).
      Map.has_key?(@binary_ops, name) and prefer_int_binop?(left, right, ctx) ->
        Arith.emit_binary(Map.fetch!(@binary_ops, name), left, right, ctx, b)

      name in ["__add__", "__sub__", "__mul__", "__idiv__"] ->
        kind = Map.fetch!(@binary_ops, name)

        op =
          case name do
            "__add__" -> :add
            "__sub__" -> :sub
            "__mul__" -> :mul
            "__idiv__" -> :idiv
          end

        cond do
          float_mixture?(left, right, ctx) ->
            Arith.emit_boxed_binop(op, left, right, ctx, b, float: true)

          # Soft float risk alone must not force f64: untyped Int params (e.g. Dict
          # map `key * 3 + 1`, Result.andThen `\x -> Ok (x * 2)`) are soft-float
          # but must stay on as_int / i32. Typed Float uses float_mixture above;
          # WASM float-promotes floatish regs (record_get, new_float, basics_abs).
          soft_float_risk?(left, ctx) or soft_float_risk?(right, ctx) ->
            Arith.emit_boxed_binop(op, left, right, ctx, b)

          true ->
            # Calls that return Int (hourHandOffset: currentHour model * 30) are not
            # `int_operand?` shapes, but after compiling both sides the regs are i32
            # candidates — keep the pre-prefer_int emit_int_arith_regs fallback.
            operand_ctx = Context.for_branch_arm(ctx)

            with {:ok, l, b1} <- Expr.compile(left, operand_ctx, b),
                 {:ok, r, b2} <- Expr.compile(right, operand_ctx, b1) do
              Arith.emit_int_arith_regs(kind, l, r, ctx, b2)
            else
              _ -> Arith.emit_boxed_binop(op, left, right, ctx, b)
            end
        end

      name == "__append__" ->
        folded =
          Elmc.Backend.CCodegen.StaticString.fold_append_literals(%{
            op: :call,
            name: "__append__",
            args: [left, right]
          })

        compile_folded_append(folded, ctx, b)

      Map.has_key?(@runtime_ops, name) ->
        target = Map.fetch!(@runtime_ops, name)

        cond do
          # Only native-int min/max may use i32 arith. Bare vars and field accesses
          # may be Floats (e.g. Extent.combine); those must keep boxed Basics.min/max.
          name in ["Basics.min", "Basics.max"] and proven_native_int_binop?(left, right, ctx) ->
            kind = if name == "Basics.min", do: :min_vars, else: :max_vars
            Arith.emit_binary(kind, left, right, ctx, b)

          # Same soft-int fallback as `__add__`: after compiling both sides the regs are
          # often native ints (`Basics.max 10 (r // 5)`) even when IR shape is not yet
          # proven — avoid boxing into `elmc_basics_max` on size-sensitive layouts.
          # Exclude bare field access / vars: those may be Float (Extent.combine).
          name in ["Basics.min", "Basics.max"] and not float_mixture?(left, right, ctx) ->
            kind = if name == "Basics.min", do: :min_vars, else: :max_vars
            operand_ctx = Context.for_branch_arm(ctx)

            with {:ok, l, b1} <- Expr.compile(left, operand_ctx, b),
                 {:ok, r, b2} <- Expr.compile(right, operand_ctx, b1) do
              if Expr.peelable_int_reg?(l, b2, ctx) and Expr.peelable_int_reg?(r, b2, ctx) do
                Arith.emit_int_arith_regs(kind, l, r, ctx, b2)
              else
                compile_runtime_binop_with_native_box(target, left, right, ctx, b)
              end
            else
              _ -> compile_runtime_binop_with_native_box(target, left, right, ctx, b)
            end

          # Prefer native mod/rem whenever both operands are int-shaped, including
          # native-int params (`modBy 4 index`). Mixed boxed ops (e.g. List.length)
          # fail `int_binop_operands?` and still box via the runtime path below.
          name in ["modBy", "Basics.modBy"] and int_binop_operands?(left, right) ->
            Arith.emit_binary(:mod_vars, left, right, ctx, b)

          name in ["remainderBy", "Basics.remainderBy"] and int_binop_operands?(left, right) ->
            Arith.emit_binary(:rem_vars, left, right, ctx, b)

          true ->
            compile_runtime_binop_with_native_box(target, left, right, ctx, b)
        end

      true ->
        :unsupported
    end
  end

  def compile(%{op: :qualified_call, target: target, args: [left, right]}, ctx, b)
      when is_binary(target) do
    compile(%{op: :call, name: target, args: [left, right]}, ctx, b)
  end

  def compile(_, _, _), do: :unsupported

  @spec compile_folded_append(map() | Types.expr(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp compile_folded_append(%{op: :string_literal} = lit, ctx, b),
    do: Expr.compile(lit, ctx, b)

  defp compile_folded_append(%{op: :call, name: "__append__", args: [left, right]}, ctx, b) do
    append_builtin =
      cond do
        list_append_operand?(left, ctx) or list_append_operand?(right, ctx) -> :list_append
        string_append_operands?(left, right, ctx) -> :string_append
        # Untyped vars historically defaulted to List.append (see plan_lower_ir_test).
        true -> :list_append
      end

    cond do
      append_builtin == :list_append and Context.stream_mode?(ctx) ->
        Elmc.Backend.Plan.Lower.Stream.List.compile_append(left, right, ctx, b)

      true ->
        with {:ok, arg_regs, b1} <- Expr.compile_args([left, right], ctx, b) do
          Expr.compile_runtime_builtin(append_builtin, arg_regs, ctx, b1)
        end
    end
  end

  defp compile_folded_append(expr, ctx, b), do: Expr.compile(expr, ctx, b)

  @spec compile_runtime_binop_with_native_box(
          String.t(),
          Types.expr(),
          Types.expr(),
          Context.t(),
          Builder.t()
        ) :: Types.compile_result()

  defp compile_runtime_binop_with_native_box(target, left, right, ctx, b) do
    with {:ok, arg_regs, b1} <- Expr.compile_args([left, right], ctx, b),
         {boxed_regs, b2} <- box_native_int_call_args(arg_regs, ctx, b1),
         id when not is_nil(id) <- Elmc.Backend.Plan.RuntimeBuiltins.from_c_symbol(target) do
      Expr.compile_runtime_builtin(id, boxed_regs, ctx, b2)
    else
      _ -> :unsupported
    end
  end

  @spec box_native_int_call_args([Types.reg()], Context.t(), Builder.t()) ::
          {[Types.reg()], Builder.t()}

  defp box_native_int_call_args(regs, ctx, b) when is_list(regs) do
    Enum.map_reduce(regs, b, fn reg, b_acc ->
      idx = param_reg_index(reg, ctx, b_acc)

      if is_integer(idx) and native_int_param_index?(idx, ctx) do
        box_native_int_param_reg(idx, ctx, b_acc)
      else
        {reg, b_acc}
      end
    end)
  end

  @spec param_reg_index(Types.reg() | term(), Context.t(), Builder.t()) ::
          non_neg_integer() | nil

  defp param_reg_index(reg, ctx, b) when is_integer(reg) do
    Enum.find_value(Enum.with_index(ctx.params), fn {name, idx} ->
      if Map.get(b.param_regs, name) == reg, do: idx
    end)
  end

  defp param_reg_index(_, _, _), do: nil

  @spec native_int_param_index?(non_neg_integer(), Context.t()) :: boolean()

  defp native_int_param_index?(idx, ctx) do
    case Map.get(ctx.decl_map, {ctx.module, ctx.function_name}) do
      decl when is_map(decl) ->
        decl = %{decl | args: FunctionEmit.effective_decl_args(decl, ctx.module, ctx.decl_map)}
        Enum.at(NativeFunctionCall.arg_kinds(decl, ctx.module, ctx.decl_map), idx) == :native_int

      _ ->
        false
    end
  end

  @spec native_int_param_var?(Types.expr(), Context.t()) :: boolean()

  defp native_int_param_var?(expr, ctx) do
    case expr do
      %{op: :var, name: name} when is_binary(name) ->
        case Enum.find_index(ctx.params, &(&1 == name)) do
          idx when is_integer(idx) -> native_int_param_index?(idx, ctx)
          _ -> false
        end

      _ ->
        false
    end
  end

  @spec box_native_int_param_reg(non_neg_integer(), Context.t(), Builder.t()) ::
          {Types.reg(), Builder.t()}

  defp box_native_int_param_reg(idx, ctx, b) do
    c_ref = FunctionCallAbi.param_c_arg(idx, ctx.params)
    {box_reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: box_reg,
        args: %{builtin: :new_int, c_expr: c_ref},
        effects: Types.fallible_effects(box_reg)
      })

    {box_reg, b2}
  end

  @spec int_binop_operands?(Types.expr(), Types.expr()) :: boolean()

  defp int_binop_operands?(left, right), do: int_operand?(left) and int_operand?(right)

  @spec proven_native_int_binop?(Types.expr(), Types.expr(), Context.t()) :: boolean()

  defp proven_native_int_binop?(left, right, ctx),
    do: proven_native_int_operand?(left, ctx) and proven_native_int_operand?(right, ctx)

  @spec proven_native_int_operand?(map() | term(), Context.t()) :: boolean()

  defp proven_native_int_operand?(%{op: :int_literal}, _ctx), do: true
  defp proven_native_int_operand?(%{op: :bool_literal}, _ctx), do: true

  defp proven_native_int_operand?(%{op: :var, name: name} = var, ctx) when is_binary(name) do
    native_int_param_var?(var, ctx) or Map.get(ctx.local_types, name) == "Int"
  end

  defp proven_native_int_operand?(%{op: :field_access, field: field} = expr, ctx)
       when is_binary(field) do
    Elmc.Backend.Plan.Lower.Record.int_field?(field, ctx, field_access_base(expr))
  end

  defp proven_native_int_operand?(%{op: :add_const, var: name}, ctx) when is_binary(name),
    do: proven_native_int_operand?(%{op: :var, name: name}, ctx)

  defp proven_native_int_operand?(%{op: :sub_const, var: name}, ctx) when is_binary(name),
    do: proven_native_int_operand?(%{op: :var, name: name}, ctx)

  defp proven_native_int_operand?(%{op: op, left: left, right: right}, ctx)
       when op in [:add_vars, :sub_vars, :mul_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars],
       do:
         proven_native_int_operand?(named_arith_operand(left), ctx) and
           proven_native_int_operand?(named_arith_operand(right), ctx)

  defp proven_native_int_operand?(%{op: :call, name: name, args: [a, b]}, ctx)
       when name in [
              "modBy",
              "Basics.modBy",
              "remainderBy",
              "Basics.remainderBy",
              "Basics.min",
              "Basics.max",
              "__add__",
              "__sub__",
              "__mul__",
              "__idiv__"
            ],
       do: proven_native_int_operand?(a, ctx) and proven_native_int_operand?(b, ctx)

  defp proven_native_int_operand?(%{op: :qualified_call, target: target, args: [a, b]}, ctx)
       when target in [
              "modBy",
              "Basics.modBy",
              "remainderBy",
              "Basics.remainderBy",
              "Basics.min",
              "Basics.max"
            ],
       do: proven_native_int_operand?(a, ctx) and proven_native_int_operand?(b, ctx)

  defp proven_native_int_operand?(_, _ctx), do: false

  @spec prefer_int_binop?(Types.expr(), Types.expr(), Context.t()) :: boolean()

  defp prefer_int_binop?(left, right, ctx) do
    cond do
      float_mixture?(left, right, ctx) ->
        false

      # Known Float record fields (Scene3d) must stay on the boxed/float path.
      # Unknown field types follow HEAD: int_binop shape → i32 (piece.y + 1,
      # model.screenW - …). TypedReturn / field registry covers Float fields.
      known_float_field_operand?(left, ctx) or known_float_field_operand?(right, ctx) ->
        false

      proven_native_int_binop?(left, right, ctx) ->
        true

      int_binop_operands?(left, right) and not soft_float_risk?(left, ctx) and
          not soft_float_risk?(right, ctx) ->
        true

      # Int-returning helpers (integerLetArithmetic): let-bound Int locals may be
      # missing from local_types when TypedReturn cannot type the binding. Prefer
      # i32 when the op shape is int-only and no field-access float risk remains.
      int_binop_operands?(left, right) and function_returns_int?(ctx) and
          not field_access_float_risk?(left, ctx) and not field_access_float_risk?(right, ctx) ->
        true

      # HEAD-like int shape, but never for a *direct* untyped bare var operand.
      # Color.toCssString `pct x = x * 10000` must stay on f32 (as_int truncates
      # fractional channels). Nested field/call soft-float risk alone must not
      # block Int layouts like `screenW - cell / 2` / game-2048 view.
      int_binop_operands?(left, right) and not untyped_bare_var_operand?(left, ctx) and
          not untyped_bare_var_operand?(right, ctx) ->
        true

      true ->
        false
    end
  end

  # Direct operand only — do not recurse into nested calls/fields.
  # Untyped *params* (lambda/closure args) are often Float — Color.toCssString
  # `pct x`. Untyped *lets* are usually Int intermediates in layout math.
  @spec untyped_bare_var_operand?(map() | term(), Context.t()) :: boolean()

  defp untyped_bare_var_operand?(%{op: :var, name: name} = var, ctx) when is_binary(name) do
    cond do
      native_int_param_var?(var, ctx) -> false
      Map.get(ctx.local_types, name) in ["Int", "Bool"] -> false
      Map.get(ctx.local_types, name) == "Float" -> true
      name in ctx.params -> true
      true -> false
    end
  end

  defp untyped_bare_var_operand?(_, _), do: false

  @spec function_returns_int?(map()) :: boolean()

  defp function_returns_int?(%Context{} = ctx) do
    case Map.get(ctx.decl_map, {ctx.module, ctx.function_name}) do
      %{type: type} when is_binary(type) ->
        Elmc.Backend.CCodegen.Host.normalize_type_name(
          Elmc.Backend.CCodegen.TypeParsing.function_return_type(type)
        ) == "Int"

      _ ->
        false
    end
  end

  @spec field_access_float_risk?(map() | term(), Context.t()) :: boolean()

  defp field_access_float_risk?(%{op: :field_access, field: field} = expr, ctx)
       when is_binary(field) do
    # Mirror soft_float_risk?/2 for fields: only treat as float risk when the
    # field is known Float (or mjs Float). Unknown fields must not block
    # `piece.y + 1` int_arith (plan_lower_ir bumpY).
    soft_float_risk?(expr, ctx)
  end

  defp field_access_float_risk?(%{op: :field_access}, _ctx), do: true

  defp field_access_float_risk?(%{op: :call, name: name, args: args}, ctx) when is_list(args) do
    (float_like_unary?(name) and not Enum.all?(args, &proven_native_int_operand?(&1, ctx))) or
      Enum.any?(args, &field_access_float_risk?(&1, ctx))
  end

  defp field_access_float_risk?(%{op: :qualified_call, target: target, args: args}, ctx)
       when is_list(args) do
    (float_like_unary?(target) and not Enum.all?(args, &proven_native_int_operand?(&1, ctx))) or
      Enum.any?(args, &field_access_float_risk?(&1, ctx))
  end

  defp field_access_float_risk?(%{op: op, left: l, right: r}, ctx)
       when op in [:add_vars, :sub_vars, :mul_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars],
       do:
         field_access_float_risk?(named_arith_operand(l), ctx) or
           field_access_float_risk?(named_arith_operand(r), ctx)

  defp field_access_float_risk?(_, _), do: false

  @spec soft_float_risk?(map() | term(), Context.t()) :: boolean()

  defp soft_float_risk?(%{op: :field_access, field: field} = expr, ctx) when is_binary(field) do
    base = field_access_base(expr)

    cond do
      Elmc.Backend.Plan.Lower.Record.int_field?(field, ctx, base) ->
        false

      Elmc.Backend.CCodegen.Native.TypedReturn.expr_type(expr, type_env(ctx)) == "Float" ->
        true

      # Unknown field type: do not assume Float. Scene3d Float fields are typed
      # in the registry or via TypedReturn; treating every `.x` as soft-float
      # forced boxed_binop for Int records (`piece.y + 1`, Ui.Point).
      true ->
        false
    end
  end

  defp soft_float_risk?(%{op: :field_access}, _ctx), do: true

  defp soft_float_risk?(%{op: op, left: l, right: r}, ctx)
       when op in [:add_vars, :sub_vars, :mul_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars],
       do:
         soft_float_risk?(named_arith_operand(l), ctx) or
           soft_float_risk?(named_arith_operand(r), ctx)

  defp soft_float_risk?(%{op: :var, name: name} = var, ctx) when is_binary(name) do
    cond do
      # Typed Int params stay on the i32 path (integerLetArithmetic, etc.).
      native_int_param_var?(var, ctx) ->
        false

      true ->
        case Map.get(ctx.local_types, name) do
          "Float" ->
            true

          "Int" ->
            false

          "Bool" ->
            false

          # Untyped locals (lambda/pattern binds) are often Float — e.g. Color.toCssString
          # `pct x = ((x * 10000) |> round …)`. Treating them as Int does
          # `as_int(0.058)*10000` → 0 and paints every CSS color black.
          _ ->
            true
        end
    end
  end

  # Scene3d.updateViewBounds: `abs (a * i.x) + abs (b * i.y) + …` — abs/mul of
  # record fields are Float, but int_operand? still matches and the old path did
  # as_int+i32.add → Int dimensions → near≈far clip planes → empty framebuffer.
  # Abs/negate of proven Int params/locals stay on the native Int path.
  defp soft_float_risk?(%{op: :call, name: name, args: args}, ctx) when is_list(args) do
    cond do
      float_like_unary?(name) and Enum.all?(args, &proven_native_int_operand?(&1, ctx)) ->
        false

      float_like_unary?(name) ->
        true

      # Int-returning callees (`currentHour model * 30`) are not soft-float just
      # because an argument is an untyped record/model param.
      callee_returns_int?(name, length(args), ctx) ->
        false

      true ->
        Enum.any?(args, &soft_float_risk?(&1, ctx))
    end
  end

  defp soft_float_risk?(%{op: :qualified_call, target: target, args: args}, ctx) when is_list(args) do
    cond do
      float_like_unary?(target) and Enum.all?(args, &proven_native_int_operand?(&1, ctx)) ->
        false

      float_like_unary?(target) ->
        true

      callee_returns_int?(target, length(args), ctx) ->
        false

      true ->
        Enum.any?(args, &soft_float_risk?(&1, ctx))
    end
  end

  defp soft_float_risk?(_, _), do: false

  @spec callee_returns_int?(String.t(), non_neg_integer(), Context.t()) :: boolean()

  defp callee_returns_int?(name, arity, ctx) when is_binary(name) and is_integer(arity) do
    {mod, fun} = split_callee_name(name, ctx.module)

    case Map.get(ctx.decl_map, {mod, fun}) do
      %{type: type} when is_binary(type) ->
        arg_types = Elmc.Backend.CCodegen.TypeParsing.function_arg_types(type)

        length(arg_types) == arity and
          Elmc.Backend.CCodegen.Host.normalize_type_name(
            Elmc.Backend.CCodegen.TypeParsing.function_return_type(type)
          ) == "Int"

      _ ->
        false
    end
  end

  defp callee_returns_int?(_, _, _), do: false

  @spec split_callee_name(String.t(), String.t() | nil) :: {String.t(), String.t()}

  defp split_callee_name(name, default_mod) when is_binary(name) do
    case String.split(name, ".") do
      [single] ->
        {default_mod || "Main", single}

      parts ->
        {Enum.join(Enum.drop(parts, -1), "."), List.last(parts)}
    end
  end

  @spec float_like_unary?(String.t() | term()) :: boolean()

  defp float_like_unary?(name) when is_binary(name) do
    name in [
      "Basics.abs",
      "abs",
      "Basics.negate",
      "negate",
      "Basics.sqrt",
      "sqrt",
      "Basics.toFloat",
      "toFloat"
    ] or String.ends_with?(name, ".abs") or String.ends_with?(name, ".negate") or
      String.ends_with?(name, ".sqrt") or String.ends_with?(name, ".toFloat")
  end

  defp float_like_unary?(_), do: false

  @spec named_arith_operand(String.t() | map() | term()) :: Types.expr() | term()

  defp named_arith_operand(name) when is_binary(name), do: %{op: :var, name: name}
  defp named_arith_operand(expr) when is_map(expr), do: expr
  defp named_arith_operand(other), do: other

  # IR often stores field bases as bare name strings; Record.int_field?/3 expects
  # a var map (same normalization as Expr.base_expr_for_field_access/1).
  @spec field_access_base(map() | term()) :: Types.expr() | nil

  defp field_access_base(%{op: :field_access, arg: name}) when is_binary(name),
    do: %{op: :var, name: name}

  defp field_access_base(%{op: :field_access, arg: arg}) when is_map(arg), do: arg
  defp field_access_base(_), do: nil

  @spec known_float_field_operand?(map() | term(), Context.t()) :: boolean()

  defp known_float_field_operand?(%{op: :field_access} = expr, ctx) do
    Elmc.Backend.CCodegen.Native.TypedReturn.expr_type(expr, type_env(ctx)) == "Float"
  end

  defp known_float_field_operand?(%{op: :call, args: args}, ctx) when is_list(args),
    do: Enum.any?(args, &known_float_field_operand?(&1, ctx))

  defp known_float_field_operand?(%{op: :qualified_call, args: args}, ctx) when is_list(args),
    do: Enum.any?(args, &known_float_field_operand?(&1, ctx))

  defp known_float_field_operand?(%{op: op, left: l, right: r}, ctx)
       when op in [:add_vars, :sub_vars, :mul_vars, :idiv_vars],
       do:
         known_float_field_operand?(named_arith_operand(l), ctx) or
           known_float_field_operand?(named_arith_operand(r), ctx)

  defp known_float_field_operand?(_, _), do: false

  @spec float_mixture?(Types.expr(), Types.expr(), Context.t()) :: boolean()

  defp float_mixture?(left, right, ctx),
    do: float_operand?(left, ctx) or float_operand?(right, ctx)

  @spec float_operand?(map() | Types.expr(), Context.t()) :: boolean()

  defp float_operand?(%{op: :float_literal}, _ctx), do: true

  # Nested `x * y + 1` must see the mul as Float when either operand is Float.
  defp float_operand?(%{op: :call, name: name, args: [a, b]}, ctx)
       when name in ["__add__", "__sub__", "__mul__", "__fdiv__"],
       do: float_operand?(a, ctx) or float_operand?(b, ctx)

  defp float_operand?(%{op: :qualified_call, target: target, args: [a, b]}, ctx)
       when target in [
              "Basics.add",
              "Basics.sub",
              "Basics.mul",
              "Basics.fdiv",
              "__add__",
              "__sub__",
              "__mul__",
              "__fdiv__"
            ],
       do: float_operand?(a, ctx) or float_operand?(b, ctx)

  defp float_operand?(%{op: :field_access, field: field} = expr, ctx) when is_binary(field) do
    # Prefer Record.int_field? over TypedReturn's mjs Float heuristic for `.x`/`.y`.
    if Elmc.Backend.Plan.Lower.Record.int_field?(field, ctx, field_access_base(expr)) do
      false
    else
      Elmc.Backend.CCodegen.Native.TypedReturn.expr_type(expr, type_env(ctx)) == "Float"
    end
  end

  defp float_operand?(expr, ctx) do
    env = type_env(ctx)
    Elmc.Backend.CCodegen.Native.TypedReturn.expr_type(expr, env) == "Float"
  end

  @spec type_env(Context.t()) :: map()

  defp type_env(%Context{} = ctx) do
    %{
      __module__: ctx.module || "Main",
      __var_types__: ctx.local_types,
      __program_decls__: ctx.decl_map,
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  @spec int_operand?(map() | term()) :: boolean()

  defp int_operand?(%{op: :int_literal}), do: true
  defp int_operand?(%{op: :bool_literal}), do: true
  defp int_operand?(%{op: :var}), do: true
  defp int_operand?(%{op: :add_const, var: _, value: _}), do: true
  defp int_operand?(%{op: :sub_const, var: _, value: _}), do: true

  # Named binary arith (`sub_vars` etc.) appears nested under `__mul__` /
  # `__sub__` before Arith rewrites it — must count as an int operand or
  # prefer_int fails and Int helpers fall into boxed_binop (dropping params).
  defp int_operand?(%{op: op, left: _, right: _})
       when op in [:add_vars, :sub_vars, :mul_vars, :idiv_vars, :mod_vars, :rem_vars, :min_vars, :max_vars],
       do: true

  defp int_operand?(%{op: :call, name: name, args: [a, b]})
       when name in ["modBy", "Basics.modBy", "remainderBy", "Basics.remainderBy", "Basics.min", "Basics.max"],
       do: int_operand?(a) and int_operand?(b)

  defp int_operand?(%{op: :call, name: name, args: [a, b]})
       when name in ["__add__", "__sub__", "__mul__", "__idiv__"],
       do: int_operand?(a) and int_operand?(b)

  defp int_operand?(%{op: :qualified_call, target: target, args: args}) do
    case {target, args} do
      {t, [a, b]}
      when t in [
             "modBy",
             "Basics.modBy",
             "remainderBy",
             "Basics.remainderBy",
             "Basics.min",
             "Basics.max",
             "Basics.//",
             "__idiv__"
           ] ->
        int_operand?(a) and int_operand?(b)

      {"Basics.floor", [arg]} -> int_operand?(arg)
      {"Basics.round", [arg]} -> int_operand?(arg)
      {"Basics.abs", [arg]} -> int_operand?(arg)
      {"Basics.negate", [arg]} -> int_operand?(arg)
      {"Basics.ceiling", [arg]} -> int_operand?(arg)
      {"Basics.truncate", [arg]} -> int_operand?(arg)
      _ -> false
    end
  end

  defp int_operand?(%{op: :runtime_call, function: function, args: args}) when is_list(args) do
    case {function, args} do
      {f, [arg]}
      when f in [
             "elmc_basics_round",
             "elmc_basics_floor",
             "elmc_basics_mod_by",
             "elmc_basics_remainder_by",
             "elmc_basics_min",
             "elmc_basics_max",
             "elmc_basics_abs",
             "elmc_basics_negate",
             "elmc_basics_ceiling",
             "elmc_basics_truncate"
           ] ->
        int_operand?(arg)

      _ ->
        false
    end
  end

  defp int_operand?(%{op: :field_access, arg: arg}) when is_binary(arg), do: true
  defp int_operand?(%{op: :field_access, arg: arg}), do: int_operand?(arg)
  defp int_operand?(%{op: :record_literal, fields: fields}) when is_list(fields),
    do: Enum.all?(fields, fn f -> int_operand?(Map.get(f, :expr) || Map.get(f, :value)) end)

  defp int_operand?(_), do: false

  @string_append_runtime_functions ~w(
    elmc_string_from_int
    elmc_string_from_native_int
    elmc_string_from_float
    elmc_string_from_char
    elmc_string_from_list
    elmc_string_reverse
    elmc_string_to_upper
    elmc_string_to_lower
    elmc_string_trim
    elmc_string_trim_left
    elmc_string_trim_right
    elmc_string_left
    elmc_string_right
    elmc_string_drop_left
    elmc_string_drop_right
    elmc_string_cons
    elmc_string_repeat
    elmc_string_replace
    elmc_string_slice
    elmc_string_pad
    elmc_string_pad_left
    elmc_string_pad_right
    elmc_string_append
  )

  @string_append_call_targets ~w(
    String.fromInt
    String.fromFloat
    String.fromChar
    String.fromList
    String.reverse
    String.toUpper
    String.toLower
    String.trim
    String.trimLeft
    String.trimRight
    String.left
    String.right
    String.dropLeft
    String.dropRight
    String.cons
    String.repeat
    String.replace
    String.slice
    String.pad
    String.padLeft
    String.padRight
    fromInt
    fromFloat
    fromChar
    fromList
  )

  @spec string_append_operands?(Types.expr(), Types.expr(), Context.t()) :: boolean()

  defp string_append_operands?(left, right, ctx),
    do: string_append_operand?(left, ctx) or string_append_operand?(right, ctx)

  @spec string_append_operand?(map() | term(), Context.t()) :: boolean()

  defp string_append_operand?(%{op: :list_literal}, _ctx), do: false
  defp string_append_operand?(%{op: :string_literal}, _ctx), do: true

  defp string_append_operand?(%{op: :var, name: name}, ctx) when is_binary(name),
    do: local_type_is_string?(ctx, name)

  defp string_append_operand?(%{op: :call, name: name, args: args}, ctx) do
    name in @string_append_call_targets or
      (name == "__append__" and match?([_, _], args) and
         string_append_operands?(hd(args), Enum.at(args, 1), ctx))
  end

  defp string_append_operand?(%{op: :qualified_call, target: target, args: args}, ctx) do
    target in @string_append_call_targets or
      (target == "++" and match?([_, _], args) and
         string_append_operands?(hd(args), Enum.at(args, 1), ctx))
  end

  defp string_append_operand?(%{op: :runtime_call, function: function}, _ctx)
       when is_binary(function),
       do: function in @string_append_runtime_functions

  defp string_append_operand?(_, _), do: false

  @spec list_append_operand?(map() | term(), Context.t()) :: boolean()

  defp list_append_operand?(%{op: :list_literal}, _ctx), do: true

  defp list_append_operand?(%{op: :var, name: name}, ctx) when is_binary(name),
    do: local_type_is_list?(ctx, name)

  defp list_append_operand?(%{op: :call, name: name, args: [left, right]}, ctx)
       when name in ["__append__", "++"],
       do: list_append_operand?(left, ctx) or list_append_operand?(right, ctx)

  defp list_append_operand?(%{op: :qualified_call, target: target, args: [left, right]}, ctx)
       when target in ["++", "Basics.++"],
       do: list_append_operand?(left, ctx) or list_append_operand?(right, ctx)

  defp list_append_operand?(_, _), do: false

  @spec local_type_is_string?(Context.t(), String.t()) :: boolean()

  defp local_type_is_string?(ctx, name) when is_binary(name) do
    case Map.get(ctx.local_types, name) do
      "String" -> true
      "String.String" -> true
      _ -> false
    end
  end

  @spec local_type_is_list?(Context.t(), String.t()) :: boolean()

  defp local_type_is_list?(ctx, name) when is_binary(name) do
    case Map.get(ctx.local_types, name) do
      type when is_binary(type) ->
        trimmed = String.trim_leading(type)
        String.starts_with?(trimmed, "List ") or trimmed == "List" or
          String.starts_with?(trimmed, "List(")

      _ ->
        false
    end
  end
end
