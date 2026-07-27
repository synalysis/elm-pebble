defmodule Elmc.Backend.Plan.Lower.Record do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.CCodegen.{Host, RecordFieldMacros, TypeParsing}
  alias Elmc.Backend.CCodegen.Expr, as: CExpr
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Call, Expr}
  alias Elmc.Backend.Plan.Types
  alias ElmEx.IR.TypeSignature

  @spec compile_update(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_update(%{base: base, fields: fields}, ctx, b) when is_list(fields) do
    base_expr = base_expr_for_field(base)
    # Base and update values are intermediates. Compiling the base under function-tail
    # context makes `call_fn dest=:fn_out` (e.g. CAF `initial`) emit as an early
    # `return`, dropping the subsequent `record_update` — `{ initial | field5 = 999 }`
    # became just `initial`.
    scratch_ctx = Context.for_branch_arm(ctx)

    with {:ok, base_reg, b1} <- resolve_base(base, scratch_ctx, b),
         {:ok, b2, result_reg} <- apply_field_updates(fields, ctx, b1, base_reg, base_expr) do
      {:ok, result_reg, b2}
    else
      _ -> :unsupported
    end
  end

  def compile_update(_, _, _), do: :unsupported

  @spec compile_field_call(Types.ir_expr() | String.t(), String.t(), [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_field_call(arg, field, args, ctx, b) when is_binary(field) do
    args = args || []

    cond do
      args == [] ->
        with {:ok, base, b1} <- resolve_base(arg, ctx, b) do
          compile_record_field_get(base, field, ctx, b1, base_expr_for_field(arg))
        end

      true ->
        with {:ok, base_reg, b1} <- resolve_base(arg, ctx, b),
             {:ok, fn_reg, b2} <-
               compile_record_field_get(base_reg, field, ctx, b1, base_expr_for_field(arg)) do
          Call.compile_closure_call_from_reg(fn_reg, args, ctx, b2)
        end
    end
  end

  @spec base_expr_for_field(map() | String.t()) :: Types.ir_expr()

  defp base_expr_for_field(%{op: :var, name: name}) when is_binary(name),
    do: %{op: :var, name: name}

  defp base_expr_for_field(base) when is_map(base), do: base
  defp base_expr_for_field(name) when is_binary(name), do: %{op: :var, name: name}

  @doc false
  @spec emit_record_field_get(integer(), String.t(), Context.t(), Builder.t(), Types.ir_expr() | nil, keyword()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported
  def emit_record_field_get(base_reg, field, ctx, b, base_expr \\ nil, opts \\ [])

      when is_integer(base_reg) and is_binary(field) do
    compile_record_field_get(base_reg, field, ctx, b, base_expr, opts)
  end

  @spec compile_record_field_get(Types.ir_expr() | integer(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.expr(), keyword()) :: Types.ir_expr()

  defp compile_record_field_get(base_reg, field, ctx, b, base_expr),
    do: compile_record_field_get(base_reg, field, ctx, b, base_expr, [])

  defp compile_record_field_get(base_reg, field, ctx, b, base_expr, opts) when is_integer(base_reg) do
    {reg, b1} = Builder.fresh_reg(b)

    field_index =
      case Keyword.get(opts, :index_override) do
        idx when is_integer(idx) and idx >= 0 ->
          RecordFieldMacros.format_index(idx, field, nil)

        _ ->
          field_index_ref(field, ctx, base_expr)
      end

    int_field? = int_field?(field, ctx, base_expr)

    op = if int_field?, do: :record_get_int, else: :record_get

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: reg,
        args: %{base: base_reg, field: field, field_index: field_index},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [base_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  @spec resolve_base(map() | String.t() | term(), Types.ir_expr() | term(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp resolve_base(%{op: :var, name: name}, ctx, b) when is_binary(name),
    do: Expr.compile(%{op: :var, name: name}, ctx, b)

  defp resolve_base(base, ctx, b) when is_map(base), do: Expr.compile(base, ctx, b)
  defp resolve_base(name, ctx, b) when is_binary(name),
    do: Expr.compile(%{op: :var, name: name}, ctx, b)

  defp resolve_base(_, _, _), do: :unsupported

  @spec apply_field_updates(term(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp apply_field_updates([field | rest], ctx, b, current_reg, base_expr) do
    field_name = Map.get(field, :field) || Map.get(field, :name)
    field_expr = Map.get(field, :expr) || Map.get(field, :value)
    value_ctx = Context.for_branch_arm(ctx)

    with {:ok, value_reg, b1} <- compile_field_expr(field_expr, value_ctx, b),
         {:ok, updated_reg, b2} <-
           cow_drop_update(current_reg, field_name, value_reg, ctx, b1, base_expr) do
      case rest do
        [] -> {:ok, b2, updated_reg}
        more -> apply_field_updates(more, ctx, b2, updated_reg, base_expr)
      end
    else
      _ -> :unsupported
    end
  end

  defp apply_field_updates([], _ctx, b, current_reg, _base_expr), do: {:ok, b, current_reg}

  @spec cow_drop_update(Types.ir_expr(), String.t(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp cow_drop_update(base_reg, field_name, value_reg, ctx, b, base_expr)
       when is_binary(field_name) do
    {value_reg, b0} = Builder.dup_named_local_if_bound(b, value_reg)

    {update_base_reg, b_base, retain_copy?} =
      if Builder.borrow_arg?(b0, base_reg) do
        {dup, b_copy} = Builder.copy_reg_owned(b0, base_reg)
        {dup, b_copy, true}
      else
        {base_reg, b0, false}
      end

    {dest, b1} = dest_for_update(ctx, b_base)

    {borrows, consumes} = partition_update_args(b1, update_base_reg, value_reg)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        Types.fallible_transfer(borrows, consumes)
      end

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1
    field_index = field_index_ref(field_name, ctx, base_expr)

    {_, b3} =
      Builder.emit(b2, :record_update, %{
        dest: dest,
        args: %{
          base: update_base_reg,
          field: field_name,
          field_index: field_index,
          value: value_reg,
          retain_copy: retain_copy?
        },
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3

    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  @doc false
  @spec canonicalize_literal_fields([Types.ir_record_field()], Context.t()) :: [Types.ir_record_field()]
  def canonicalize_literal_fields(fields, ctx) when is_list(fields) do
    names = Enum.map(fields, &field_name/1)

    case canonical_shape_for_names(names, ctx.module) do
      nil ->
        # Row-polymorphic callers (e.g. computeArrowDetails) index fields using a
        # union-ctor payload shape that may include extra slots (meander). A literal
        # that omits those slots must still be laid out like the superset, or
        # dense indices miss and WASM record_get returns int 0 (degenerate arrows).
        case unique_superset_shape(names) do
          {:ok, shape} ->
            expand_fields_to_shape(fields, shape)

          :none ->
            # Anonymous records: Elm stores fields alphabetically, and field_access on
            # anonymous / inline param types uses alphabetical indices. Write and read
            # must agree. Named alias shapes usually keep declaration order; a few
            # (Scene3d.Types.Transformation) are registered alphabetically.
            Enum.sort_by(fields, &to_string(field_name(&1)))
        end

      canonical_names ->
        ordered =
          Enum.map(canonical_names, fn name ->
            Enum.find(fields, &(field_name(&1) == name))
          end)

        if Enum.all?(ordered, & &1), do: ordered, else: fields
    end
  end

  # Prefer a unique minimal proper-superset shape from alias/union payload shapes.
  # Pad a single missing slot so dense field indices match callers that use the
  # full payload layout (Arrow.meander; Scene3d `{position,normal}` + trailing `uv`).
  #
  # Reject *leading* pads: `{radius, length}` uniquely sits under Cylinder3d/Cone3d
  # `{axis, radius, length}`, and padding `axis = 0` at index 0 makes centeredOn
  # read int-0 as radius → zero preScale / EmptyMesh fallout on HeroScene.
  # Middle pads (Arrow.meander) remain allowed when they are the unique +1 slot.
  @spec unique_superset_shape(list()) :: Types.ir_expr()

  defp unique_superset_shape(names) when is_list(names) do
    name_set = MapSet.new(Enum.map(names, &to_string/1))

    if MapSet.size(name_set) == 0 do
      :none
    else
      supersets =
        record_shapes_for_superset()
        |> Enum.filter(fn fields ->
          shape = Enum.map(fields, &to_string/1)
          field_set = MapSet.new(shape)
          missing = MapSet.difference(field_set, name_set)

          MapSet.subset?(name_set, field_set) and
            MapSet.size(field_set) == MapSet.size(name_set) + 1 and
            match?([_], MapSet.to_list(missing)) and
            # Missing slot must not be shape[0] (would shift every present index).
            Enum.find_index(shape, &(&1 == hd(MapSet.to_list(missing)))) != 0
        end)
        |> Enum.uniq_by(fn fields -> Enum.map(fields, &to_string/1) end)

      case supersets do
        [shape] -> {:ok, Enum.map(shape, &to_string/1)}
        _ -> :none
      end
    end
  end

  @spec record_shapes_for_superset() :: Types.ir_expr()

  defp record_shapes_for_superset do
    Process.get(:elmc_record_alias_shapes, %{})
    |> Map.merge(Process.get(:elmc_inline_record_literal_shapes, %{}))
    |> Map.values()
    |> Enum.filter(&(is_list(&1) and &1 != []))
  end

  @spec expand_fields_to_shape(list(), list()) :: Types.ir_expr()

  defp expand_fields_to_shape(fields, shape) when is_list(fields) and is_list(shape) do
    by_name = Map.new(fields, fn f -> {to_string(field_name(f)), f} end)

    Enum.map(shape, fn name ->
      case Map.get(by_name, name) do
        nil ->
          # Placeholder for an unread extension slot (e.g. Arrow.meander). Keep a
          # dense layout aligned with union-ctor field indices; value is unused.
          %{name: name, expr: %{op: :int_literal, value: 0}}

        field ->
          field
      end
    end)
  end

  @doc false
  @spec int_field?(String.t()) :: boolean()
  def int_field?(field_name) when is_binary(field_name) do
    # Unscoped lookup is unsafe: `Time` has `{ start : Int }` while Svg.Arrow
    # details use `.start` as a Point. Prefer `int_field?/3` with a base expr.
    _ = field_name
    false
  end

  @doc false
  @spec int_field?(String.t(), Context.t() | nil, Types.ir_expr() | nil) :: boolean()
  def int_field?(field_name, ctx, base_expr) when is_binary(field_name) do
    case field_type_from_access(field_name, ctx, base_expr) do
      "Int" -> true
      _ -> false
    end
  end

  @spec field_type_from_access(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp field_type_from_access(field_name, ctx, base_expr) when is_binary(field_name) do
    case resolve_field_type_key(field_name, ctx, base_expr) do
      {key, _idx} when is_tuple(key) ->
        Process.get(:elmc_record_field_types, %{})
        |> Map.get(key, %{})
        |> then(fn fields ->
          Map.get(fields, field_name) || Map.get(fields, to_string(field_name))
        end)

      _ ->
        nil
    end
  end

  @doc false
  @spec field_index_for(String.t(), Context.t() | nil, Types.ir_expr() | nil) :: String.t()
  def field_index_for(field_name, ctx \\ nil, base_expr \\ nil) when is_binary(field_name),
    do: field_index_ref(field_name, ctx, base_expr)

  @doc false
  @spec resolve_field_index_int(String.t(), Context.t() | nil, Types.ir_expr() | nil) ::
          {:ok, integer()} | :error
  def resolve_field_index_int(field_name, ctx \\ nil, base_expr \\ nil)
      when is_binary(field_name) do
    case field_index_from_mjs_to_record(field_name, base_expr) do
      idx when is_integer(idx) ->
        {:ok, idx}

      _ ->
        case field_index_from_callee_record_literal(field_name, ctx, base_expr) do
          idx when is_integer(idx) ->
            {:ok, idx}

          _ ->
            case field_index_from_binding_decl_type(field_name, ctx, base_expr) do
              idx when is_integer(idx) ->
                {:ok, idx}

              _ ->
                case resolve_field_type_key(field_name, ctx, base_expr) do
                  {_key, idx} when is_integer(idx) -> {:ok, idx}
                  _ -> :error
                end
            end
        end
    end
  end

  @spec field_name(Types.ir_expr()) :: Types.ir_expr()

  defp field_name(field), do: Map.get(field, :name) || Map.get(field, :field)

  # Top-level values like `Shared.template = { init, update, view, … }` are record
  # literals in IR. When lowering `Shared.template.view`, the base expression is the
  # zero-arg call — resolve field indices in the same order as record_new
  # (`canonicalize_literal_fields`), not raw IR source order.
  @spec field_index_from_callee_record_literal(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp field_index_from_callee_record_literal(field_name, ctx, base_expr)
       when is_binary(field_name) do
    case callee_decl_for_base_expr(base_expr, ctx) do
      %{expr: %{op: :record_literal, fields: fields}} when is_list(fields) ->
        fields
        |> canonicalize_literal_fields(ctx || %Context{})
        |> Enum.find_index(&(field_name(&1) == field_name))

      _ ->
        nil
    end
  end

  @spec callee_decl_for_base_expr(map() | term(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp callee_decl_for_base_expr(%{op: :field_access, arg: inner}, ctx) when is_map(inner) do
    callee_decl_for_base_expr(inner, ctx)
  end

  defp callee_decl_for_base_expr(%{op: :qualified_call, target: target, args: args}, ctx)
       when is_binary(target) and is_list(args) do
    if args == [] do
      callee_decl_for_qualified_target(target, ctx)
    end
  end

  defp callee_decl_for_base_expr(%{op: :qualified_ref, target: target}, ctx)
       when is_binary(target) do
    callee_decl_for_qualified_target(target, ctx)
  end

  defp callee_decl_for_base_expr(%{op: :call, name: name, args: args}, ctx)
       when is_binary(name) and is_list(args) do
    if args == [] and is_binary(ctx && ctx.module) do
      Map.get(ctx.decl_map || %{}, {ctx.module, name})
    end
  end

  # Zero-arity CAF / let-bound names appear as vars (`{ initial | field5 = 999 }`).
  # Resolve the decl so field indices use the alias shape (BigRecord.field5), not 0.
  defp callee_decl_for_base_expr(%{op: :var, name: name}, ctx) when is_binary(name) do
    if is_binary(ctx && ctx.module) do
      Map.get(ctx.decl_map || %{}, {ctx.module, name})
    end
  end

  defp callee_decl_for_base_expr(_, _), do: nil

  # Top-level bindings like `Route.Index.route : StatelessRoute …` are not record
  # literals in IR, but field access must use the alias record shape (StatefulRoute),
  # not unrelated inline shapes that happen to mention the same field name.
  @spec field_index_from_binding_decl_type(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp field_index_from_binding_decl_type(field_name, ctx, base_expr) when is_binary(field_name) do
    case callee_decl_for_base_expr(base_expr, ctx) do
      %{type: type} when is_binary(type) ->
        case record_shape_key_from_decl_type(type, ctx) do
          key when is_tuple(key) ->
            case Map.get(Process.get(:elmc_record_alias_shapes, %{}), key) do
              fields when is_list(fields) ->
                Enum.find_index(fields, &(&1 == field_name))

              _ ->
                nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @spec record_shape_key_from_decl_type(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp record_shape_key_from_decl_type(type, ctx) when is_binary(type) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    ctor = type |> Host.normalize_type_name() |> type_constructor_name()

    case CExpr.split_qualified_type_name(ctor) do
      {mod, name} ->
        key = {mod, name}
        record_shape_key_or_synonym(key, shapes)

      _ ->
        case shape_key_by_name(shapes, ctor, ctx) do
          key when is_tuple(key) -> record_shape_key_or_synonym(key, shapes)
          _ -> record_shape_key_or_synonym({nil, ctor}, shapes)
        end
    end
  end

  @spec record_shape_key_or_synonym(term(), Types.ir_expr()) :: Types.ir_expr()

  defp record_shape_key_or_synonym({mod, name}, shapes) when is_binary(name) do
    key = if is_binary(mod), do: {mod, name}, else: shape_key_by_name(shapes, name, %{module: mod})

    cond do
      is_tuple(key) and Map.has_key?(shapes, key) ->
        key

      is_binary(mod) and name == "StatelessRoute" and Map.has_key?(shapes, {mod, "StatefulRoute"}) ->
        {mod, "StatefulRoute"}

      name == "StatelessRoute" ->
        shape_key_by_record_name(shapes, "StatefulRoute")

      true ->
        nil
    end
  end

  @spec shape_key_by_record_name(map(), String.t()) :: Types.ir_expr()

  defp shape_key_by_record_name(shapes, record_name) when is_binary(record_name) and is_map(shapes) do
    case Enum.filter(shapes, fn {{_mod, name}, _fields} -> name == record_name end) do
      [{key, _}] -> key
      many when length(many) > 1 -> elem(hd(many), 0)
      _ -> nil
    end
  end

  @spec callee_decl_for_qualified_target(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp callee_decl_for_qualified_target(target, ctx) when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {module, name} when is_binary(module) and is_binary(name) ->
        decl_map = (ctx && ctx.decl_map) || %{}
        Map.get(decl_map, {module, name})

      _ ->
        nil
    end
  end

  @spec canonical_shape_for_names(list(), String.t()) :: Types.ir_expr()

  defp canonical_shape_for_names(field_names, module) when is_list(field_names) do
    normalized = field_names |> Enum.map(&to_string/1) |> Enum.sort()

    matches =
      Process.get(:elmc_record_alias_shapes, %{})
      |> Enum.filter(fn {{_mod, _name}, shape} ->
        Enum.sort(Enum.map(shape, &to_string/1)) == normalized
      end)

    matches =
      if matches == [] do
        Process.get(:elmc_inline_record_literal_shapes, %{})
        |> Enum.filter(fn {{_mod, _name}, shape} ->
          Enum.sort(Enum.map(shape, &to_string/1)) == normalized
        end)
      else
        matches
      end

    case matches do
      [] ->
        nil

      many ->
        case module do
          mod when is_binary(mod) ->
            case Enum.find(many, fn {{m, _}, _} -> m == mod end) do
              {{_, _}, shape} -> shape
              _ -> elem(hd(many), 1)
            end

          _ ->
            elem(hd(many), 1)
        end
    end
  end

  @spec field_index_ref(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp field_index_ref(field_name, ctx, base_expr) when is_binary(field_name) do
    case field_index_from_mjs_to_record(field_name, base_expr) do
      idx when is_integer(idx) ->
        RecordFieldMacros.format_index(idx, field_name, nil)

      _ ->
        case field_index_from_callee_record_literal(field_name, ctx, base_expr) do
          idx when is_integer(idx) ->
            RecordFieldMacros.format_index(idx, field_name, nil)

          _ ->
            case field_index_from_binding_decl_type(field_name, ctx, base_expr) do
              idx when is_integer(idx) ->
                RecordFieldMacros.format_index(idx, field_name, nil)

              _ ->
                case param_or_typed_var_field_index(field_name, ctx, base_expr) do
                  {key, idx} when is_integer(idx) ->
                    RecordFieldMacros.format_index(idx, field_name, key)

                  _ ->
                    field_index_ref_from_type(field_name, ctx, base_expr)
                end
            end
        end
    end
  end

  # elm-explorations/linear-algebra Kernel.MJS *toRecord always emits fields in
  # alphabetical order (see elmc-wasm-runtime/host/mjs_runtime.js). Without this
  # shape, `Matrix4.toRecord m |> .m44` fell back to index 0 (m11) and Scene3d
  # treated perspective cameras as orthographic (solid-white lighting).
  @spec field_index_from_mjs_to_record(String.t(), Types.expr()) :: Types.ir_expr()

  defp field_index_from_mjs_to_record(field_name, base_expr) when is_binary(field_name) do
    case mjs_to_record_fields(base_expr) do
      fields when is_list(fields) ->
        Enum.find_index(fields, &(&1 == field_name))

      _ ->
        nil
    end
  end

  @spec mjs_to_record_fields(map() | term()) :: Types.ir_expr()

  defp mjs_to_record_fields(%{op: :qualified_call, target: target}) when is_binary(target),
    do: mjs_to_record_fields_for_target(target)

  defp mjs_to_record_fields(%{op: :call, target: {mod, name}})
       when is_binary(mod) and is_binary(name),
       do: mjs_to_record_fields_for_target("#{mod}.#{name}")

  defp mjs_to_record_fields(%{op: :call, name: name}) when is_binary(name),
    do: mjs_to_record_fields_for_target(name)

  defp mjs_to_record_fields(%{op: :field_access, arg: inner}) when is_map(inner),
    do: mjs_to_record_fields(inner)

  defp mjs_to_record_fields(_), do: nil

  @spec mjs_to_record_fields_for_target(String.t()) :: Types.ir_expr()

  defp mjs_to_record_fields_for_target(target) when is_binary(target) do
    short = target |> String.split(".") |> List.last()

    cond do
      short in ["toRecord"] and String.contains?(target, "Matrix4") ->
        mat4_to_record_fields()

      short in ["toRecord"] and String.contains?(target, "Vector4") ->
        ["w", "x", "y", "z"]

      short in ["toRecord"] and String.contains?(target, "Vector3") ->
        ["x", "y", "z"]

      short in ["toRecord"] and String.contains?(target, "Vector2") ->
        ["x", "y"]

      short in ["m4x4toRecord"] ->
        mat4_to_record_fields()

      short in ["v4toRecord"] ->
        ["w", "x", "y", "z"]

      short in ["v3toRecord"] ->
        ["x", "y", "z"]

      short in ["v2toRecord"] ->
        ["x", "y"]

      true ->
        nil
    end
  end

  @spec mat4_to_record_fields() :: Types.ir_expr()

  defp mat4_to_record_fields do
    for i <- 1..4, j <- 1..4, do: "m#{i}#{j}"
  end

  @spec param_or_typed_var_field_index(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp param_or_typed_var_field_index(field_name, ctx, base_expr) when is_binary(field_name) do
    if param_var_base?(base_expr, ctx) do
      alias_result = alias_field_index_for_param(field_name, ctx, base_expr)

      case alias_result do
        {key, idx} when is_integer(idx) ->
          if extensible_param_var?(base_expr, ctx) do
            {key, idx}
          else
            inline_result = inline_field_index_from_base(field_name, ctx, base_expr)

            case reconcile_param_field_indices(inline_result, alias_result, field_name, ctx, base_expr) do
              {:inline, inferred_idx} when is_integer(inferred_idx) ->
                {nil, inferred_idx}

              {reconciled_key, reconciled_idx} when is_integer(reconciled_idx) ->
                {reconciled_key, reconciled_idx}
            end
          end

        :error ->
          case inline_field_index_from_base(field_name, ctx, base_expr) do
            {:inline, idx} when is_integer(idx) ->
              {nil, idx}

            {key, idx} when is_integer(idx) ->
              {key, idx}

            :error ->
              nil
          end
      end
    else
      nil
    end
  end

  @spec extensible_param_var?(Types.expr(), Types.ir_expr()) :: boolean()

  defp extensible_param_var?(base_expr, ctx) do
    case base_expr do
      %{op: :var, name: name} when is_binary(name) ->
        ctx
        |> compile_env()
        |> Map.get(:__var_types__, %{})
        |> Map.get(name)
        |> case do
          type when is_binary(type) -> extensible_record_type?(type)
          _ -> false
        end

      _ ->
        false
    end
  end

  @spec reconcile_param_field_indices(pos_integer(), term(), String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp reconcile_param_field_indices(inline, {key, alias_idx} = alias_result, field_name, ctx, base_expr)
       when is_integer(alias_idx) do
    case inline do
      :error ->
        {key, alias_idx}

      {:inline, inferred_idx} when inferred_idx != alias_idx ->
        if prefer_alias_field_index?(field_name, ctx, base_expr, key, alias_idx),
          do: {key, alias_idx},
          else: {:inline, inferred_idx}

      {_, inferred_idx} when inferred_idx != alias_idx ->
        if prefer_alias_field_index?(field_name, ctx, base_expr, key, alias_idx),
          do: alias_result,
          else: inline

      result ->
        result
    end
  end

  @spec prefer_alias_field_index?(String.t() | term(), Types.ir_expr() | term(), map() | term(), String.t() | term(), Types.ir_expr() | term()) :: boolean()

  defp prefer_alias_field_index?(field_name, ctx, %{op: :var, name: param}, key, _alias_idx)
       when is_binary(field_name) and is_binary(param) do
    inferred_fields = Map.get((ctx && ctx.inferred_param_fields) || %{}, param, [])
    alias_fields = Map.get(Process.get(:elmc_record_alias_shapes, %{}), key, [])

    inferred_names = Enum.map(inferred_fields, &to_string/1)
    alias_names = Enum.map(alias_fields, &to_string/1)
    inferred_alpha? = inferred_names != [] and inferred_names == Enum.sort(inferred_names)
    alias_alpha? = alias_names != [] and alias_names == Enum.sort(alias_names)

    cond do
      # Typed param (`Metadata` from withMetadata's combine type) must use the
      # declared alias layout even when ParamFieldInference only saw a subset
      # (`{statusCode}` → index 0). Host/runtime Metadata values are full records.
      param_typed_as_alias_key?(ctx, param, key) ->
        true

      inferred_fields == [] ->
        false

      not is_list(alias_fields) or alias_fields == [] ->
        false

      inferred_fields == alias_fields ->
        false

      normalize_field_names(inferred_fields) != normalize_field_names(alias_fields) ->
        false

      # Union payloads / anonymous records: inferred is alphabetical (storage order).
      # Do not let a declaration-order alias (or min_alias across unrelated shapes)
      # remap .vertices → index 0 (faceIndices) — Scene3d cylinders/spheres went blank.
      inferred_alpha? and not alias_alpha? ->
        false

      inferred_alpha? and alias_alpha? ->
        false

      Enum.find_index(inferred_fields, &(&1 == field_name)) !=
          Enum.find_index(alias_fields, &(&1 == field_name)) ->
        true

      true ->
        false
    end
  end

  defp prefer_alias_field_index?(_, _, _, _, _), do: false

  @spec param_typed_as_alias_key?(Types.ir_expr() | term(), Types.ir_expr() | term(), String.t() | term()) :: boolean()

  defp param_typed_as_alias_key?(ctx, param, key)
       when is_binary(param) and is_tuple(key) do
    type =
      ctx
      |> compile_env()
      |> Map.get(:__var_types__, %{})
      |> Map.get(param)

    is_binary(type) and record_key_from_type(type, ctx) == key
  end

  defp param_typed_as_alias_key?(_, _, _), do: false

  @spec alias_field_index_for_param(String.t() | term(), Types.ir_expr() | term(), map() | term()) :: Types.ir_expr()

  defp alias_field_index_for_param(field_name, ctx, %{op: :var, name: param_name})
       when is_binary(field_name) and is_binary(param_name) do
    env = compile_env(ctx)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    type =
      env
      |> Map.get(:__var_types__, %{})
      |> Map.get(param_name)

    cond do
      is_binary(type) and extensible_record_type?(type) ->
        case field_index_among_extensible_shapes(field_name, type, shapes) do
          {key, idx} when is_integer(idx) -> {key, idx}
          _ -> :error
        end

      is_binary(type) ->
        case record_key_from_type(type, ctx) do
          key when is_tuple(key) ->
            case Map.get(shapes, key) do
              fields when is_list(fields) ->
                case Enum.find_index(fields, &(&1 == field_name)) do
                  idx when is_integer(idx) -> {key, idx}
                  _ -> min_alias_field_index(field_name, shapes)
                end

              _ ->
                min_alias_field_index(field_name, shapes)
            end

          _ ->
            min_alias_field_index(field_name, shapes)
        end

      true ->
        case shape_key_for_inferred_fields(Map.get((ctx && ctx.inferred_param_fields) || %{}, param_name), ctx) do
          {key, fields} when is_tuple(key) and is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> min_alias_field_index(field_name, shapes)
            end

          key when is_tuple(key) ->
            case Map.get(shapes, key) do
              fields when is_list(fields) ->
                case Enum.find_index(fields, &(&1 == field_name)) do
                  idx when is_integer(idx) -> {key, idx}
                  _ -> min_alias_field_index(field_name, shapes)
                end

              _ ->
                min_alias_field_index(field_name, shapes)
            end

          _ ->
            min_alias_field_index(field_name, shapes)
        end
    end
  end

  defp alias_field_index_for_param(_, _, _), do: :error

  @spec min_alias_field_index(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp min_alias_field_index(field_name, shapes) when is_binary(field_name) do
    case min_field_index_among_shapes(field_name, shapes) do
      {key, idx} when is_integer(idx) -> {key, idx}
      _ -> :error
    end
  end

  @spec field_index_ref_from_type(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp field_index_ref_from_type(field_name, ctx, base_expr) when is_binary(field_name) do
    case resolve_field_type_key(field_name, ctx, base_expr) do
      {:inline, idx} ->
        RecordFieldMacros.format_index(idx, field_name, nil)

      {{mod, type}, idx} when is_integer(idx) ->
        RecordFieldMacros.format_index(idx, field_name, {mod, type})

      _ ->
        shapes = Process.get(:elmc_record_alias_shapes, %{})
        env = compile_env(ctx)

        container_type =
          case base_expr do
            expr when is_map(expr) -> CExpr.record_container_type_for_expr(expr, env)
            _ -> nil
          end

        cond do
          is_binary(container_type) and extensible_record_type?(container_type) ->
            case field_index_among_extensible_shapes(field_name, container_type, shapes) do
              {key, idx} when is_integer(idx) ->
                RecordFieldMacros.format_index(idx, field_name, key)

              _ ->
                field_index_macro_fallback(field_name, ctx, base_expr)
            end

          true ->
            case ambiguous_field_type_key(field_name, ctx, shapes, base_expr) do
              {key, idx} when is_integer(idx) ->
                RecordFieldMacros.format_index(idx, field_name, key)

              _ ->
                case ambiguous_field_candidates(field_name, shapes) do
                  [] ->
                    field_index_macro_fallback(field_name, ctx, base_expr)

                  [{key, idx}] ->
                    RecordFieldMacros.format_index(idx, field_name, key)

                  many ->
                    case pick_ambiguous_field_type_key(many, ctx, base_expr) do
                      {key, idx} when is_integer(idx) ->
                        RecordFieldMacros.format_index(idx, field_name, key)

                      _ ->
                        field_index_macro_fallback(field_name, ctx, base_expr)
                    end
                end
            end
        end
    end
  end

  @spec field_index_macro_fallback(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp field_index_macro_fallback(field_name, ctx, base_expr) when is_binary(field_name) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case ambiguous_field_candidates(field_name, shapes) do
      [] ->
        numeric_field_index_fallback(field_name)

      [{_key, idx}] ->
        "#{idx} /* #{field_name} */"

      many ->
        case pick_ambiguous_field_type_key(many, ctx, base_expr) do
          {key, idx} when is_integer(idx) ->
            RecordFieldMacros.format_index(idx, field_name, key)

          _ ->
            numeric_field_index_fallback(field_name)
        end
    end
  end

  @spec numeric_field_index_fallback(String.t()) :: Types.ir_expr()

  defp numeric_field_index_fallback(field_name) when is_binary(field_name) do
    case Process.get(:elmc_record_field_macros, %{}) do
      macros when is_map(macros) ->
        case Enum.find_value(macros, fn {{_mod, _type, name}, macro} ->
               if name == field_name, do: macro
             end) do
          macro when is_binary(macro) -> macro
          _ -> "0"
        end

      _ ->
        "0"
    end
  end

  @spec resolve_field_type_key(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp resolve_field_type_key(field_name, ctx, base_expr) when is_binary(field_name) do
    env = compile_env(ctx)

    container_type =
      case base_expr do
        expr when is_map(expr) -> CExpr.record_container_type_for_expr(expr, env)
        _ -> nil
      end

    if is_binary(container_type) and extensible_record_type?(container_type) do
      case field_index_among_extensible_shapes(
             field_name,
             container_type,
             Process.get(:elmc_record_alias_shapes, %{})
           ) do
        {key, idx} when is_integer(idx) -> {key, idx}
        _ -> resolve_field_type_key_concrete(field_name, ctx, base_expr)
      end
    else
      resolve_field_type_key_concrete(field_name, ctx, base_expr)
    end
  end

  @spec resolve_field_type_key_concrete(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp resolve_field_type_key_concrete(field_name, ctx, base_expr) when is_binary(field_name) do
    case inline_field_index_from_base(field_name, ctx, base_expr) do
      {:inline, idx} ->
        {:inline, idx}

      {{_mod, _type} = key, idx} when is_integer(idx) ->
        {key, idx}

      :error ->
        case inline_field_index_from_container_type(field_name, ctx, base_expr) do
          {:inline, idx} -> {:inline, idx}
          :error -> resolve_field_type_key_from_shapes(field_name, ctx, base_expr)
        end
    end
  end

  @spec inline_field_index_from_container_type(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp inline_field_index_from_container_type(field_name, ctx, base_expr)
       when is_binary(field_name) do
    env = compile_env(ctx)

    with type when is_binary(type) <- CExpr.record_container_type_for_expr(base_expr, env),
         false <- extensible_record_type?(type),
         true <- TypeSignature.record_type?(type),
         declared_fields when is_list(declared_fields) and declared_fields != [] <-
           TypeSignature.record_field_names(type),
         idx when is_integer(idx) <- inline_literal_shapes_field_index(field_name, declared_fields) do
      {:inline, idx}
    else
      _ ->
        with type when is_binary(type) <- CExpr.record_container_type_for_expr(base_expr, env),
             false <- extensible_record_type?(type),
             true <- TypeSignature.record_type?(type),
             fields when is_list(fields) and fields != [] <- elm_inline_record_field_names(type),
             idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
          {:inline, idx}
        else
          _ -> :error
        end
    end
  end

  @spec extensible_record_type?(String.t()) :: boolean()

  defp extensible_record_type?(type) when is_binary(type), do: String.contains?(type, "|")

  # Elm stores record fields in alphabetical order at runtime.
  @spec elm_inline_record_field_names(String.t()) :: Types.ir_expr()

  defp elm_inline_record_field_names(type) when is_binary(type) do
    type |> TypeSignature.record_field_names() |> Enum.sort()
  end

  @spec inline_literal_shapes_field_index(String.t(), Types.decl()) :: Types.ir_expr()

  defp inline_literal_shapes_field_index(field_name, declared_fields)
       when is_binary(field_name) and is_list(declared_fields) do
    normalized = declared_fields |> Enum.map(&to_string/1) |> Enum.sort()

    shapes =
      Process.get(:elmc_inline_record_literal_shapes, %{})
      |> Map.merge(Process.get(:elmc_record_alias_shapes, %{}))

    case Enum.find_value(shapes, fn {_key, shape} ->
           shape_names = shape |> Enum.map(&to_string/1)

           if Enum.sort(shape_names) == normalized do
             shape_names
           end
         end) do
      shape when is_list(shape) -> Enum.find_index(shape, &(&1 == field_name))
      _ -> nil
    end
  end

  @spec inline_field_index_from_base(String.t(), Types.ir_expr(), map() | Types.expr()) :: Types.ir_expr()

  defp inline_field_index_from_base(field_name, ctx, %{op: :var, name: name})
       when is_binary(field_name) and is_binary(name) do
    env = compile_env(ctx)

    with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
         key when is_tuple(key) <- record_key_from_type(type, ctx),
         fields when is_list(fields) <-
           Map.get(Process.get(:elmc_record_alias_shapes, %{}), key),
         idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
      {key, idx}
    else
      _ ->
        inline_field_index_from_concrete_var(field_name, ctx, name)
    end
  end

  defp inline_field_index_from_base(_field_name, _ctx, _base_expr), do: :error

  @spec inline_field_index_from_concrete_var(String.t(), Types.ir_expr(), String.t()) :: Types.ir_expr()

  defp inline_field_index_from_concrete_var(field_name, ctx, name)
       when is_binary(field_name) and is_binary(name) do
    # Prefer pattern_bind / union-payload inferred fields (already alphabetical) over
    # declaration-order type strings and same-field-set alias shapes. Otherwise
    # TriangularMesh.vertices reads faceIndices and indexed meshes draw empty.
    case inline_field_index_from_inferred_param(field_name, ctx, name) do
      {:inline, _} = ok ->
        ok

      {_, _} = ok ->
        ok

      :error ->
        case inline_field_index_from_declared_param_type(field_name, ctx, name) do
          {:inline, _} = ok -> ok
          {_, _} = ok -> ok
          :error -> :error
        end
    end
  end

  @spec inline_field_index_from_declared_param_type(String.t(), Types.ir_expr(), String.t()) :: Types.ir_expr()

  defp inline_field_index_from_declared_param_type(field_name, ctx, name)
       when is_binary(field_name) and is_binary(name) do
    env = compile_env(ctx)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
         key when is_tuple(key) <- record_key_from_type(type, ctx),
         fields when is_list(fields) <- Map.get(shapes, key),
         idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
      {key, idx}
    else
      _ ->
        with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
             false <- extensible_record_type?(type),
             declared_fields when is_list(declared_fields) and declared_fields != [] <-
               TypeSignature.record_field_names(type),
             idx when is_integer(idx) <-
               inline_literal_shapes_field_index(field_name, declared_fields) do
          {:inline, idx}
        else
          _ ->
            with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
                 false <- extensible_record_type?(type),
                 fields when is_list(fields) and fields != [] <- elm_inline_record_field_names(type),
                 idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
              {:inline, idx}
            else
              _ -> :error
            end
        end
    end
  end

  @spec inline_field_index_from_inferred_param(String.t(), Types.ir_expr(), String.t()) :: Types.ir_expr()

  defp inline_field_index_from_inferred_param(field_name, ctx, name)
       when is_binary(field_name) and is_binary(name) do
    fields =
      case ctx do
        %{inferred_param_fields: inferred} when is_map(inferred) -> Map.get(inferred, name)
        _ -> nil
      end

    case fields do
      list when is_list(list) and list != [] ->
        # Declared inline param type `{view : …}` (buildNoState) must win over a
        # same-module proper-superset alias such as StatefulRoute (view@3). Capturing
        # Int(0) from OOB record_get skips Index.view and leaves Document.title empty.
        case exact_declared_inline_record_field_index(field_name, list, ctx, name) do
          {:inline, _} = ok ->
            ok

          :error ->
            # Param type `{init, view, update}` must win over access-order subsets like
            # `{init, view}` and over same-module alias supersets (Browser.element's
            # `{init, subscriptions, update, view}` would map view→3 instead of impl@2).
            case declared_param_type_proper_superset_field_index(field_name, list, ctx, name) do
              {:inline, _} = ok ->
                ok

              :error ->
                # Nested lambdas (Platform.application subscriptions `\model ->`) often only
                # access a subset of a named alias. Alphabetical layout of that subset maps
                # `pageData`→0 (key) instead of Platform.Model@4 — Time.every never installs.
                # Same-module proper supersets are safe; cross-module supersets (Cylinder3d
                # for anonymous `{radius,length}`) must not win.
                case same_module_proper_superset_field_index(field_name, list, ctx) do
                  {key, idx} ->
                    {key, idx}

                  :error ->
                    as_strings = Enum.map(list, &to_string/1)
                    # Union ctor payloads (TriangularMesh, etc.) and anonymous records are stored
                    # alphabetically; pattern_bind seeds inferred fields already sorted. A
                    # declaration-order registered shape with the same field *set* must not
                    # override that — otherwise `.vertices` reads `faceIndices` (index 0) and
                    # WebGL.indexedTriangles gets (0,0,0) indices → invisible cylinders/spheres.
                    if as_strings == Enum.sort(as_strings) do
                      alphabetical_inferred_field_index(field_name, list)
                    else
                      # Access-order inference (ParamFieldInference) is unsorted. Only reuse a
                      # registered shape when it is an *exact* field-set match (declaration-order
                      # named type). Strict supersets such as Cylinder3d/Cone3d
                      # `{axis, length, radius}` for anonymous `{radius, length}` must not win —
                      # that mapped `.length`→1 and `.radius`→2, so centeredOn wrote radius into
                      # the length slot and left radius as missing/0 → modelScale [0,0,r,-1].
                      case shape_key_for_inferred_fields(list, ctx) do
                        {key, shape} when is_list(shape) ->
                          inferred_set = MapSet.new(as_strings)
                          shape_set = MapSet.new(Enum.map(shape, &to_string/1))

                          if MapSet.equal?(inferred_set, shape_set) do
                            # `shape` is already in the record's real runtime layout —
                            # declaration order for named aliases (elmc_record_alias_shapes
                            # keeps declaration order except a few registered exceptions),
                            # or alphabetical for anonymous/inline literals (already sorted
                            # when registered in elmc_inline_record_literal_shapes). Re-sorting
                            # here would silently override a declaration-order alias (e.g.
                            # MainResolveAndWalk.Options `{paths, name}`) with the wrong index.
                            case Enum.find_index(Enum.map(shape, &to_string/1), &(&1 == field_name)) do
                              idx when is_integer(idx) -> {key, idx}
                              _ -> alphabetical_inferred_field_index(field_name, list)
                            end
                          else
                            alphabetical_inferred_field_index(field_name, list)
                          end

                        _ ->
                          alphabetical_inferred_field_index(field_name, list)
                      end
                    end
                end
            end
        end

      _ ->
        :error
    end
  end

  # When the param's declared type is an anonymous record whose field *set* equals
  # the inferred accesses, use that layout (alphabetical). Do not let a larger
  # same-module alias (StatefulRoute for `{view}`) steal the index.
  @spec exact_declared_inline_record_field_index(String.t(), Types.ir_expr(), Types.ir_expr(), String.t()) :: Types.ir_expr()

  defp exact_declared_inline_record_field_index(field_name, inferred_fields, ctx, name)
       when is_binary(field_name) and is_list(inferred_fields) and is_binary(name) do
    env = compile_env(ctx)
    inferred_set = MapSet.new(inferred_fields, &to_string/1)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
         false <- extensible_record_type?(type),
         true <- TypeSignature.record_type?(type),
         # Named aliases registered in shapes (`Model`, `StatefulRoute`) keep
         # proper-superset recovery. `record_key_from_type` invents synthetic keys
         # for `{view : …}` strings, so only treat as named when the key exists.
         false <- named_registered_record_alias?(type, ctx, shapes),
         declared when is_list(declared) and declared != [] <- elm_inline_record_field_names(type),
         true <- MapSet.equal?(inferred_set, MapSet.new(declared)),
         idx when is_integer(idx) <- Enum.find_index(declared, &(&1 == field_name)) do
      {:inline, idx}
    else
      _ -> :error
    end
  end

  @spec named_registered_record_alias?(Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: boolean()

  defp named_registered_record_alias?(type, ctx, shapes)
       when is_binary(type) and is_map(shapes) do
    case record_key_from_type(type, ctx) do
      key when is_tuple(key) -> Map.has_key?(shapes, key)
      _ -> false
    end
  end

  # When ParamFieldInference only saw a subset of fields on a lambda/param, but a
  # unique same-module alias is a proper field-set superset, use that alias's
  # indices. Cross-module supersets stay rejected (anonymous cylinder args).
  #
  # Do not win over an *exact* field-set match registered in any module. Scene3d.Mesh
  # `TexturedFacetVertex` is `{position, uv, normal}` — a false proper-superset of
  # `collectSmooth`'s `{position, normal}` that maps `.normal`→2 (past the end of a
  # 2-field vertex) and shreds cylinder caps / tangram faces. Prefer the exact
  # `VertexWithNormal` layout instead. Platform.Model `{pageData, url}` has no exact
  # match, so same-module supersets still recover declaration indices there.
  @spec same_module_proper_superset_field_index(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp same_module_proper_superset_field_index(field_name, inferred_fields, ctx)
       when is_binary(field_name) and is_list(inferred_fields) do
    module = ctx && Map.get(ctx, :module)
    inferred_set = MapSet.new(inferred_fields, &to_string/1)

    cond do
      not is_binary(module) or MapSet.size(inferred_set) == 0 ->
        :error

      exact_registered_field_set?(inferred_set) ->
        :error

      true ->
        # Include test/inline shapes (e.g. Scene3d.scene) alongside compiled aliases.
        candidates =
          Process.get(:elmc_record_alias_shapes, %{})
          |> Map.merge(Process.get(:elmc_inline_record_literal_shapes, %{}))
          |> Enum.filter(fn
            {{^module, _name}, shape} when is_list(shape) and shape != [] ->
              shape_set = MapSet.new(shape, &to_string/1)

              MapSet.subset?(inferred_set, shape_set) and
                not MapSet.equal?(inferred_set, shape_set)

            _ ->
              false
          end)

        case candidates do
          [{key, shape}] ->
            case Enum.find_index(shape, &(to_string(&1) == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  @spec exact_registered_field_set?(map()) :: boolean()

  defp exact_registered_field_set?(field_set) when is_map(field_set) do
    Process.get(:elmc_record_alias_shapes, %{})
    |> Map.merge(Process.get(:elmc_inline_record_literal_shapes, %{}))
    |> Enum.any?(fn {_key, shape} ->
      is_list(shape) and MapSet.equal?(field_set, MapSet.new(shape, &to_string/1))
    end)
  end

  # When ParamFieldInference only saw a subset of an *inline* param type
  # (`{init, view, update}` but only `init`/`view` accessed), use that type's
  # alphabetical indices. Named aliases use same_module_proper_superset instead
  # (Platform.Model keeps declaration order).
  @spec declared_param_type_proper_superset_field_index(String.t(), Types.ir_expr(), Types.ir_expr(), String.t()) :: Types.ir_expr()

  defp declared_param_type_proper_superset_field_index(field_name, inferred_fields, ctx, name)
       when is_binary(field_name) and is_list(inferred_fields) and is_binary(name) do
    env = compile_env(ctx)
    inferred_set = MapSet.new(inferred_fields, &to_string/1)

    with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
         false <- extensible_record_type?(type),
         declared when is_list(declared) and declared != [] <- elm_inline_record_field_names(type),
         declared_set = MapSet.new(declared),
         true <- MapSet.subset?(inferred_set, declared_set),
         true <- not MapSet.equal?(inferred_set, declared_set),
         idx when is_integer(idx) <- Enum.find_index(declared, &(&1 == field_name)) do
      {:inline, idx}
    else
      _ -> :error
    end
  end

  # Anonymous records are stored alphabetically; access-order inference alone is
  # wrong for `scene.lights` vs `scene.entities` when both are inferred.
  @spec alphabetical_inferred_field_index(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp alphabetical_inferred_field_index(field_name, list)
       when is_binary(field_name) and is_list(list) do
    sorted = list |> Enum.map(&to_string/1) |> Enum.sort()

    case Enum.find_index(sorted, &(&1 == field_name)) do
      idx when is_integer(idx) -> {:inline, idx}
      _ -> :error
    end
  end

  @spec shape_key_for_inferred_fields(list() | term(), Types.ir_expr() | term()) :: Types.ir_expr()

  defp shape_key_for_inferred_fields(inferred_fields, ctx) when is_list(inferred_fields) do
    inferred_set = MapSet.new(inferred_fields, &to_string/1)

    shapes =
      Process.get(:elmc_record_alias_shapes, %{})
      |> Map.merge(Process.get(:elmc_inline_record_literal_shapes, %{}))

    candidates =
      shapes
      |> Enum.filter(fn {_key, shape} ->
        is_list(shape) and MapSet.subset?(inferred_set, MapSet.new(shape, &to_string/1))
      end)

    case candidates do
      [] ->
        nil

      [{key, shape}] ->
        {key, shape}

      many ->
        # Prefer an exact field-set match (anonymous scene records, etc.).
        exact =
          Enum.filter(many, fn {_key, shape} ->
            MapSet.equal?(inferred_set, MapSet.new(shape, &to_string/1))
          end)

        case exact do
          [{key, shape}] ->
            {key, shape}

          _ ->
            module = ctx && Map.get(ctx, :module)

            picked =
              case module do
                mod when is_binary(mod) ->
                  case Enum.find(many, fn {{m, _}, _} -> m == mod end) do
                    {key, shape} -> {key, shape}
                    _ -> pick_most_specific_shape_candidate(many, inferred_set)
                  end

                _ ->
                  pick_most_specific_shape_candidate(many, inferred_set)
              end

            case picked do
              {key, shape} when is_list(shape) -> {key, shape}
              key when is_tuple(key) -> {key, Map.get(shapes, key)}
              _ -> nil
            end
        end
    end
  end

  defp shape_key_for_inferred_fields(_, _), do: nil

  @spec pick_most_specific_shape_candidate(list(), Types.ir_expr()) :: Types.ir_expr()

  defp pick_most_specific_shape_candidate(candidates, inferred_set) when is_list(candidates) do
    exact =
      Enum.filter(candidates, fn {_key, shape} ->
        MapSet.equal?(inferred_set, MapSet.new(shape, &to_string/1))
      end)

    case exact do
      [{key, _} | _] ->
        key

      _ ->
        candidates
        |> Enum.min_by(fn {_key, shape} -> length(shape) end)
        |> elem(0)
    end
  end

  @spec normalize_field_names(list()) :: list()

  defp normalize_field_names(fields) when is_list(fields) do
    fields |> Enum.map(&to_string/1) |> Enum.sort()
  end

  @spec resolve_field_type_key_from_shapes(String.t(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp resolve_field_type_key_from_shapes(field_name, ctx, base_expr) when is_binary(field_name) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case container_record_key(base_expr, ctx) do
      key when is_tuple(key) ->
        case Map.get(shapes, key) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> ambiguous_field_type_key(field_name, ctx, shapes, base_expr)
            end

          _ ->
            ambiguous_field_type_key(field_name, ctx, shapes, base_expr)
        end

      _ ->
        ambiguous_field_type_key(field_name, ctx, shapes, base_expr)
    end
  end

  @spec ambiguous_field_type_key(String.t(), Types.ir_expr(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp ambiguous_field_type_key(field_name, ctx, shapes, base_expr) do
    case prefer_inline_shape_field_index(field_name, shapes, ctx, base_expr) do
      {key, idx} when is_integer(idx) ->
        {key, idx}

      _ ->
        ambiguous_field_type_key_from_alias(field_name, ctx, shapes, base_expr)
    end
  end

  @spec prefer_inline_shape_field_index(String.t(), Types.ir_expr(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp prefer_inline_shape_field_index(field_name, shapes, ctx, base_expr)
       when is_binary(field_name) do
    inline_shapes = Process.get(:elmc_inline_record_literal_shapes, %{})

    case container_record_key(base_expr, ctx) do
      key when is_tuple(key) ->
        case Map.get(inline_shapes, key) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> nil
            end

          _ ->
            # Phantom keys (e.g. `{Module, "value"}` from Result.Ok's type-var
            # payload spec) must not suppress the nested-inline heuristic.
            if Map.has_key?(shapes, key) do
              nil
            else
              prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
            end
        end

      _ ->
        if param_var_base?(base_expr, ctx) do
          case inline_field_index_from_base(field_name, ctx, base_expr) do
            {:inline, idx} when is_integer(idx) ->
              {nil, idx}

            {key, idx} when is_integer(idx) ->
              {key, idx}

            :error ->
              prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
          end
        else
          prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
        end
    end
  end

  @spec param_var_base?(map() | term(), Types.ir_expr() | term()) :: boolean()

  defp param_var_base?(%{op: :var, name: name}, ctx) when is_binary(name) do
    params = (ctx && Map.get(ctx, :params)) || []
    inferred = (ctx && Map.get(ctx, :inferred_param_fields)) || %{}
    # Pattern-bound union payloads (TriangularMesh mesh) are locals, not params,
    # but still carry inferred_param_fields from pattern_bind — must use that path.
    name in params or Map.has_key?(inferred, name)
  end

  defp param_var_base?(_, _), do: false

  @spec prefer_inline_shape_when_container_unknown(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
       when is_binary(field_name) and is_map(shapes) and is_map(inline_shapes) do
    inline_candidates =
      inline_shapes
      |> Enum.filter(fn {_, fields} -> field_name in fields end)
      |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)
      |> Enum.filter(fn {_, idx} -> is_integer(idx) end)

    case inline_candidates do
      [] ->
        nil

      candidates ->
        {key, idx} = Enum.min_by(candidates, fn {_, i} -> i end)

        alias_candidates =
          shapes
          |> Enum.filter(fn {_, fields} -> field_name in fields end)
          |> Enum.map(fn {k, fields} -> {k, Enum.find_index(fields, &(&1 == field_name))} end)
          |> Enum.filter(fn {_, i} -> is_integer(i) end)

        case alias_candidates do
          [] ->
            {key, idx}

          alias_many ->
            # Prefer nested inline layouts (Model_pageData.pageData @1) when both the
            # parent alias and an inline payload shape expose the same field name.
            # performUserMsg's `model.pageData` must not use this path — it relies on
            # a Model-typed `model` local (see PatternBind tuple elem typing).
            #
            # Only compare against same-module parent aliases (`Model` vs
            # `Model_pageData`). Unrelated aliases that happen to share a field
            # (RouteBuilder.App.sharedData @1) must not veto the nested payload.
            #
            # Exception: when inline and alias expose the *same* field set in
            # different orders (e.g. fromExtrema `{minX,maxX,…}` declaration
            # order vs Geometry.Types.BoundingBox3d alphabetical payload), the
            # lower inline index is wrong for runtime records — Elm stores
            # BoundingBox fields alphabetically (minX@3, not @0). Prefer the
            # alias/union shape in that case so Scene3d clip depths stay finite.
            inline_fields = Map.get(inline_shapes, key)

            parent_aliases =
              case key do
                {inline_mod, inline_name} when is_binary(inline_mod) and is_binary(inline_name) ->
                  Enum.filter(alias_many, fn {{amod, aname}, _} ->
                    amod == inline_mod and String.starts_with?(inline_name, aname <> "_")
                  end)

                _ ->
                  []
              end

            case parent_aliases do
              [] ->
                # No same-module parent alias (Model → Model_pageData). Keep the
                # nested inline index unless some alias exposes the *same* field
                # set in another order (BoundingBox3d alphabetical vs fromExtrema).
                same_field_set? =
                  is_list(inline_fields) and
                    Enum.any?(alias_many, fn {ak, _} ->
                      case Map.get(shapes, ak) do
                        af when is_list(af) ->
                          MapSet.equal?(
                            MapSet.new(Enum.map(inline_fields, &to_string/1)),
                            MapSet.new(Enum.map(af, &to_string/1))
                          )

                        _ ->
                          false
                      end
                    end)

                if same_field_set?, do: nil, else: {key, idx}

              parent_many ->
                {alias_key, alias_idx} = Enum.max_by(parent_many, fn {_, i} -> i end)

                same_field_set? =
                  is_list(inline_fields) and
                    Enum.any?(parent_many, fn {ak, _} ->
                      case Map.get(shapes, ak) do
                        af when is_list(af) ->
                          MapSet.equal?(
                            MapSet.new(Enum.map(inline_fields, &to_string/1)),
                            MapSet.new(Enum.map(af, &to_string/1))
                          )

                        _ ->
                          false
                      end
                    end)

                cond do
                  same_field_set? ->
                    nil

                  idx < alias_idx ->
                    {key, idx}

                  true ->
                    _ = alias_key
                    nil
                end
            end
        end
    end
  end

  @spec ambiguous_field_type_key_from_alias(String.t(), Types.ir_expr(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp ambiguous_field_type_key_from_alias(field_name, ctx, shapes, base_expr) do
    candidates =
      shapes
      |> Enum.filter(fn {_key, fields} -> field_name in fields end)
      |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)

    case candidates do
      [] ->
        nil

      [{key, idx}] ->
        {key, idx}

      many ->
        case container_record_key(base_expr, ctx) do
          key when is_tuple(key) ->
            case Enum.find(many, fn {candidate, _idx} -> candidate == key end) do
              {key, idx} -> {key, idx}
              _ -> pick_ambiguous_field_type_key(many, ctx, base_expr)
            end

          _ ->
            pick_ambiguous_field_type_key(many, ctx, base_expr)
        end
    end
  end

  @spec pick_ambiguous_field_type_key(list(), Types.ir_expr(), Types.expr()) :: Types.ir_expr()

  defp pick_ambiguous_field_type_key(many, ctx, _base_expr) when is_list(many) do
    module = ctx && Map.get(ctx, :module)
    shapes = all_record_shapes()

    with_exact =
      if is_binary(module) do
        Enum.filter(many, fn {{m, _}, _idx} -> m == module end)
      else
        []
      end

    with_prefix =
      if with_exact == [] and is_binary(module) do
        Enum.filter(many, fn {{m, _}, _idx} ->
          is_binary(m) and
            (String.starts_with?(module, m <> ".") or String.starts_with?(m, module <> "."))
        end)
      else
        with_exact
      end

    # Module-local / prefix hits: prefer the richest shape (Layout over a thin
    # sibling). Untyped / cross-module ambiguity: prefer the smallest shape so
    # Vec2.x is not stolen by a large record that also has an `x` field.
    #
    # Nested axis-aligned box payloads are the exception: BoundingBox2d ⊂
    # BoundingBox3d share minX/maxX/… field names, and the small shape's
    # alphabetical minX@2 is wrong for 3d (minX@3) — zero X span collapses
    # Scene3d near/far. Only apply richness when every candidate is an
    # extrema record (`min`/`max` + `X`/`Y`/`Z`).
    box_extrema_fields? = fn fields ->
      is_list(fields) and fields != [] and
        Enum.all?(fields, fn f ->
          String.match?(to_string(f), ~r/^(min|max)[XYZ]$/)
        end)
    end

    {candidates, prefer_rich?} =
      case with_prefix do
        [] ->
          all_box_extrema? =
            Enum.all?(many, fn {key, _} ->
              box_extrema_fields?.(Map.get(shapes, key))
            end)

          nested_box? =
            if all_box_extrema? do
              rich_len =
                Enum.max(
                  Enum.map(many, fn {key, _} ->
                    length(Map.get(shapes, key) || [])
                  end) ++ [0]
                )

              rich_field_set =
                Enum.find_value(many, fn {k, _} ->
                  fields = Map.get(shapes, k)

                  if is_list(fields) and length(fields) == rich_len do
                    MapSet.new(Enum.map(fields, &to_string/1))
                  end
                end) || MapSet.new()

              Enum.all?(many, fn {key, _} ->
                MapSet.subset?(
                  MapSet.new(Enum.map(Map.get(shapes, key) || [], &to_string/1)),
                  rich_field_set
                )
              end)
            else
              false
            end

          {many, nested_box?}

        preferred ->
          {preferred, true}
      end

    Enum.max_by(candidates, fn {key, idx} ->
      field_count =
        case Map.get(shapes, key) do
          fields when is_list(fields) -> length(fields)
          _ -> 0
        end

      score = if prefer_rich?, do: field_count, else: -field_count
      {score, idx}
    end)
  end

  @spec all_record_shapes() :: Types.ir_expr()

  defp all_record_shapes do
    Process.get(:elmc_record_alias_shapes, %{})
    |> Map.merge(Process.get(:elmc_inline_record_literal_shapes, %{}))
  end

  @spec max_field_index_among_shapes(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp max_field_index_among_shapes(field_name, shapes) when is_binary(field_name) do
    shape_field_index_candidates(field_name, shapes)
    |> case do
      [] -> nil
      candidates -> Enum.max_by(candidates, fn {_key, idx} -> idx end)
    end
  end

  # For `{c | lo : b, hi : b}`, prefer a concrete shape that contains every known
  # row field (Extent), not the max index across unrelated shapes that happen to
  # share one name (Box.lo at index 1 colliding with Extent.hi at index 1).
  #
  # For singleton rows like `{url | path : String}`, *every* shape that has
  # `path` matches. Picking the shortest (Payload/Request with path@0) makes
  # Route.urlToRoute read Url.protocol instead of Url.path — deep links then
  # init as Index/ErrorPage while view rewrites field 0 and reports Wasm
  # (Model mismatch). Prefer an exact field-set match, then min-length for
  # multi-field rows (Extent), else the highest path index (Url/PageUrl @3).
  @spec field_index_among_extensible_shapes(String.t(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp field_index_among_extensible_shapes(field_name, extensible_type, shapes)
       when is_binary(field_name) and is_binary(extensible_type) and is_map(shapes) do
    known =
      extensible_type
      |> TypeSignature.extensible_record_field_names()
      |> Enum.map(&to_string/1)

    matching =
      shapes
      |> Enum.filter(fn {_key, fields} ->
        if is_list(fields) and known != [] do
          field_names = Enum.map(fields, &to_string/1)
          Enum.all?(known, fn name -> name in field_names end)
        else
          false
        end
      end)

    case matching do
      [] ->
        max_field_index_among_shapes(field_name, shapes)

      candidates ->
        {key, fields} = pick_extensible_shape_candidate(candidates, known, field_name)

        case Enum.find_index(Enum.map(fields, &to_string/1), &(&1 == field_name)) do
          idx when is_integer(idx) ->
            {key, idx}

          _ ->
            max_field_index_among_shapes(field_name, shapes)
        end
    end
  end

  @spec pick_extensible_shape_candidate(Types.ir_expr(), integer(), String.t()) :: Types.ir_expr()

  defp pick_extensible_shape_candidate(candidates, known, field_name) do
    known_set = MapSet.new(known)

    exact =
      Enum.filter(candidates, fn {_k, fields} ->
        MapSet.equal?(MapSet.new(Enum.map(fields, &to_string/1)), known_set)
      end)

    case exact do
      [only] ->
        only

      [_ | _] = many ->
        Enum.min_by(many, fn {_k, f} -> length(f) end)

      [] when length(known) == 1 ->
        Enum.max_by(candidates, fn {_k, fields} ->
          fields
          |> Enum.map(&to_string/1)
          |> Enum.find_index(&(&1 == field_name))
          |> case do
            idx when is_integer(idx) -> idx
            _ -> -1
          end
        end)

      [] ->
        Enum.min_by(candidates, fn {_k, f} -> length(f) end)
    end
  end

  @spec min_field_index_among_shapes(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp min_field_index_among_shapes(field_name, shapes) when is_binary(field_name) do
    shape_field_index_candidates(field_name, shapes)
    |> case do
      [] -> nil
      candidates -> Enum.min_by(candidates, fn {_key, idx} -> idx end)
    end
  end

  @spec ambiguous_field_candidates(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp ambiguous_field_candidates(field_name, shapes) when is_binary(field_name) do
    shape_field_index_candidates(field_name, shapes)
  end

  @spec shape_field_index_candidates(String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp shape_field_index_candidates(field_name, shapes) when is_binary(field_name) do
    shapes
    |> Enum.filter(fn {_key, fields} -> field_name in fields end)
    |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)
    |> Enum.filter(fn {_key, idx} -> is_integer(idx) end)
  end

  @spec container_record_key(Types.expr(), Types.ir_expr()) :: Types.ir_expr()

  defp container_record_key(base_expr, ctx) do
    env = compile_env(ctx)

    case CExpr.record_container_type_for_expr(base_expr, env) do
      type when is_binary(type) ->
        record_key_from_type(type, ctx)

      _ ->
        nil
    end
  end

  @spec record_key_from_type(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp record_key_from_type(type, ctx) do
    normalized = Host.normalize_type_name(type)

    if TypeSignature.type_variable?(normalized) do
      nil
    else
      type_name = type_constructor_name(normalized)
      shapes = Process.get(:elmc_record_alias_shapes, %{})

      case CExpr.split_qualified_type_name(type_name) do
        {mod, name} ->
          if Map.has_key?(shapes, {mod, name}),
            do: {mod, name},
            else: shape_key_by_name(shapes, name, ctx)

        _ ->
          shape_key_by_name(shapes, type_name, ctx)
      end
    end
  end

  @spec type_constructor_name(String.t()) :: Types.ir_expr()

  defp type_constructor_name(type) when is_binary(type) do
    case String.split(type, ~r/\s+/, parts: 2) do
      [base, _rest] -> base
      [base] -> base
    end
  end

  @spec shape_key_by_name(Types.ir_expr(), String.t(), Types.ir_expr()) :: Types.ir_expr()

  defp shape_key_by_name(shapes, name, ctx) when is_binary(name) do
    module = ctx && Map.get(ctx, :module)

    matches =
      shapes
      |> Enum.filter(fn {{_mod, record}, _fields} -> record == name end)

    case matches do
      [{key, _}] ->
        key

      many when length(many) > 1 and is_binary(module) ->
        case Enum.find(many, fn {{mod, _}, _} -> mod == module end) do
          {key, _} -> key
          _ -> elem(hd(many), 0)
        end

      [{key, _} | _] ->
        key

      _ ->
        if is_binary(module), do: {module, name}, else: nil
    end
  end

  @spec compile_env(Types.ir_expr()) :: Types.ir_expr()

  defp compile_env(ctx) do
    var_types =
      ctx
      |> param_var_types()
      |> Map.merge(local_param_types(ctx))

    %{
      __module__: (ctx && ctx.module) || "Main",
      __var_types__: var_types,
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  @spec local_param_types(map() | term()) :: Types.ir_expr()

  defp local_param_types(%Context{local_types: types}) when is_map(types), do: types
  defp local_param_types(_), do: %{}

  @spec param_var_types(Types.ir_expr()) :: Types.ir_expr()

  defp param_var_types(ctx) do
    with %Context{decl_map: decl_map, module: module, params: params, function_name: fun} <- ctx,
         fun when is_binary(fun) <- fun,
         decl when is_map(decl) <- Map.get(decl_map || %{}, {module, fun}, %{}),
         type when is_binary(type) <- Map.get(decl, :type),
         arg_types when is_list(arg_types) <- TypeParsing.function_arg_types(type) do
      params
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {name, idx}, acc ->
        case Enum.at(arg_types, idx) do
          arg_type when is_binary(arg_type) -> Map.put(acc, name, arg_type)
          _ -> acc
        end
      end)
    else
      _ -> %{}
    end
  end

  @spec compile_field_expr(Types.expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp compile_field_expr(expr, ctx, b) do
    Expr.compile(expr, Context.for_branch_arm(ctx), b)
  end

  @spec dest_for_update(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp dest_for_update(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end

  @spec partition_update_args(Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()

  defp partition_update_args(b, base_reg, value_reg) do
    base_effects =
      if Builder.borrow_arg?(b, base_reg), do: {[base_reg], []}, else: {[], [base_reg]}

    {base_borrows, _base_consumes} = base_effects
    {base_borrows, [value_reg]}
  end
end
