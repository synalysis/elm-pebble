defmodule ElmEx.Frontend.Pretty.Expr do
  @moduledoc false

  alias ElmEx.Frontend.Pretty.{Doc, Literal, Pattern}

  @type opts :: keyword()
  @type binding() ::
          {:name, String.t(), map()}
          | {:tuple, [String.t()], map()}
          | {:pattern, map(), map()}

  @spec format(map(), opts()) :: Doc.t()
  def format(expr, opts \\ [])

  def format(%{op: :int_literal, text: text}, _opts) when is_binary(text), do: Doc.text(text)

  def format(%{op: :int_literal, value: value}, _opts), do: Doc.text(Integer.to_string(value))

  def format(%{op: :float_literal, value: value}, _opts), do: Doc.text(float_to_string(value))

  def format(%{op: :string_literal, value: value}, _opts), do: Doc.text(Literal.string_literal(value))

  def format(%{op: :char_literal, value: value}, _opts), do: Doc.text(Literal.char_literal(value))

  @operator_vars ["__add__", "__sub__", "__mul__", "__fdiv__", "__idiv__", "__pow__"]

  def format(%{op: :var, name: name}, _opts) when name in @operator_vars do
    Doc.parens(Doc.text(infix_op(name)))
  end

  def format(%{op: :var, name: name}, _opts), do: Doc.text(name)

  def format(%{op: :constructor_ref, target: target}, _opts), do: Doc.text(target)

  def format(%{op: :qualified_ref, target: target}, _opts), do: Doc.text(target)

  def format(%{op: :cmd_none}, _opts), do: Doc.text("Cmd.none")

  def format(%{op: :tuple_first_expr, arg: arg}, opts),
    do: format_call("Tuple.first", [arg], opts)

  def format(%{op: :tuple_second_expr, arg: arg}, opts),
    do: format_call("Tuple.second", [arg], opts)

  def format(%{op: :string_length_expr, arg: arg}, opts),
    do: format_call("String.length", [arg], opts)

  def format(%{op: :char_from_code_expr, arg: arg}, opts),
    do: format_call("Char.fromCode", [arg], opts)

  def format(%{op: :unsupported, source: source}, _opts), do: Doc.text(String.trim(source))

  def format(%{op: :add_const, var: var, value: value}, opts) do
    Doc.concat([format(%{op: :var, name: var}, opts), Doc.text(" + #{value}")])
  end

  def format(%{op: :add_vars, left: left, right: right}, _opts) do
    Doc.concat([Doc.text(left), Doc.text(" + "), Doc.text(right)])
  end

  def format(%{op: :sub_const, var: var, value: value}, opts) do
    Doc.concat([format(%{op: :var, name: var}, opts), Doc.text(" - #{value}")])
  end

  def format(%{op: :sub_vars, left: left, right: right}, _opts) do
    Doc.concat([Doc.text(left), Doc.text(" - "), Doc.text(right)])
  end

  def format(%{op: :tuple2, left: left, right: right}, opts) do
    format_tuple_elements(flatten_tuple2(left, right), opts)
  end

  def format(%{op: :list_literal, items: []}, _opts), do: Doc.text("[]")

  def format(%{op: :list_literal, items: items}, opts) do
    if compact_list_items?(items) do
      item_docs = Enum.map(items, &format_list_item(&1, opts))
      Doc.concat([Doc.text("["), Doc.join(item_docs, Doc.text(", ")), Doc.text("]")])
    else
      format_multiline_list(items, opts)
    end
  end

  def format(%{op: :call, name: "|.", args: [left, right]}, opts) do
    format_infix_expr(left, "|.", right, opts, :pipe_dot)
  end

  def format(%{op: :call, name: "|=", args: [left, right]}, opts) do
    format_infix_expr(left, "|=", right, opts, :pipe_eq)
  end

  def format(%{op: :call, name: "__append__", args: [left, right]}, opts) do
    format_infix_expr(left, "++", right, opts, :append)
  end

  def format(%{op: :call, name: "not", args: [%{op: :compare, kind: :eq, left: left, right: right}]}, opts) do
    format_infix_expr(left, "/=", right, opts, :compare)
  end

  def format(%{op: :compare, left: left, right: right, kind: kind}, opts) do
    format_infix_expr(left, compare_op(kind), right, opts, :compare)
  end

  def format(%{op: :call, name: name, args: [left, right]}, opts)
      when name in ["__add__", "__sub__", "__mul__", "__fdiv__", "__idiv__", "__pow__"] do
    format_infix_expr(left, infix_op(name), right, opts, infix_kind(name))
  end

  def format(%{op: :call, name: name, args: [arg]}, opts)
      when name in @operator_vars do
    format_partial_infix(name, arg, opts)
  end

  def format(%{op: :call, name: name, args: args}, opts) do
    format_call(name, args, opts)
  end

  def format(%{op: :qualified_call, target: "List.cons", args: [head, tail]}, opts) do
    format_infix_expr(head, "::", tail, opts, :cons)
  end

  def format(%{op: :qualified_call, target: target, args: args}, opts) do
    format_call(target, args, opts)
  end

  def format(%{op: :constructor_call, target: target, args: args}, opts) do
    format_call(target, args, opts)
  end

  def format(%{op: :field_access, arg: arg, field: field}, opts) do
    Doc.concat([format_subject(arg, opts), Doc.text("."), Doc.text(field)])
  end

  def format(%{op: :field_call, arg: arg, field: field, args: args}, opts) do
    Doc.concat([
      format_field_receiver(arg, opts),
      Doc.text("."),
      format_call(field, args, opts)
    ])
  end

  def format(%{op: :compose_left, f: f, g: g}, opts) do
    format_compose(f, " << ", g, opts)
  end

  def format(%{op: :compose_right, f: f, g: g}, opts) do
    format_compose(f, " >> ", g, opts)
  end

  def format(%{op: :apply_left, fn_expr: fn_expr, arg: arg}, opts) do
    Doc.group(
      Doc.concat([
        format(fn_expr, opts),
        if multiline_body?(arg) or multiline_arg?(fn_expr) do
          Doc.nest(1, Doc.concat([Doc.break(), Doc.text("<| "), format(arg, opts)]))
        else
          Doc.concat([Doc.text(" <| "), format(arg, opts)])
        end
      ])
    )
  end

  def format(%{op: :bool_or, left: left, right: right}, opts) do
    case resugar_inclusive_compare_or(left, right) do
      {:ok, op, l, r} ->
        format_infix_expr(l, op, r, opts, :compare)

      :error ->
        format_infix_expr(left, "||", right, opts, :bool_or)
    end
  end

  def format(%{op: :bool_and, left: left, right: right}, opts) do
    format_infix_expr(left, "&&", right, opts, :bool_and)
  end

  def format(%{op: :lambda} = expr, opts) do
    case unwrap_lambda_case_chain(expr) do
      {before_args, pattern, body} ->
        {after_args, inner_body} = peel_simple_lambda_args(body)
        format_pattern_lambda(before_args, pattern, after_args, inner_body, opts)

      :error ->
        case unwrap_curried_lambda(expr) do
          {args, body} when args != [] ->
            format_plain_lambda(%{op: :lambda, args: args, body: body}, opts)

          _ ->
            format_plain_lambda(expr, opts)
        end
    end
  end

  def format(%{op: :let_in, name: "caseSubject", value_expr: value, in_expr: %{op: :case, subject: "caseSubject"} = case_expr}, opts) do
    format(Map.put(case_expr, :subject, value), opts)
  end

  def format(%{op: :let_bindings, layout: :inline_first, bindings: [first | rest], in_expr: body}, opts)
      when rest != [] do
    Doc.concat([
      Doc.text("let "),
      format_binding_entry(first, opts),
      format_inline_first_siblings(rest, opts),
      Doc.break(),
      Doc.text("in"),
      format_let_body(body, opts)
    ])
  end

  def format(%{op: :let_bindings, layout: :inline_first, bindings: bindings, in_expr: body}, opts) do
    format(%{op: :let_bindings, bindings: bindings, in_expr: body}, opts)
  end

  def format(%{op: :let_bindings, bindings: [single], in_expr: body}, opts) do
    if compact_single_let?(single, body) do
      Doc.group(
        Doc.concat([
          Doc.text("let "),
          format_single_binding_inline(single, opts),
          Doc.text(" in "),
          format(body, opts)
        ])
      )
    else
      format_block_let_bindings([single], body, opts)
    end
  end

  def format(%{op: :let_bindings, bindings: bindings, in_expr: body}, opts) do
    format_block_let_bindings(bindings, body, opts)
  end

  def format(%{op: :let_in} = expr, opts) do
    {bindings, body} = collect_lets(expr)

    format(
      %{
        op: :let_bindings,
        bindings: Enum.map(bindings, &collected_binding_entry/1),
        in_expr: body
      },
      opts
    )
  end

  def format(%{op: :if} = expr, opts) do
    {cond, then_expr, else_expr} = if_parts(expr)
    format_if_expr(cond, then_expr, else_expr, opts)
  end

  def format(%{op: :case, subject: subject, branches: branches}, opts) do
    opts = Keyword.update(opts, :case_depth, 0, &(&1 + 1))

    Doc.concat([
      Doc.text("case "),
      format_subject(subject, opts),
      Doc.text(" of"),
      Doc.nest(1,
        Doc.concat([
          Doc.break(),
          Doc.concat(
            Enum.intersperse(Enum.map(branches, &format_branch(&1, opts)), Doc.break())
          )
        ])
      )
    ])
  end

  def format(%{op: :record_literal, fields: []}, _opts), do: Doc.text("{}")

  def format(%{op: :record_literal, fields: fields}, opts) do
    if multiline_record?(fields) do
      Doc.concat([
        Doc.text("{"),
        Doc.nest(
          1,
          Doc.concat([
            Doc.break(),
            format_multiline_record_fields(fields, opts)
          ])
        ),
        Doc.break(),
        Doc.text("}")
      ])
    else
      format_inline_record(fields, opts)
    end
  end

  def format(%{op: :record_update, base: base, fields: fields}, opts) do
    format_record_update(base, fields, opts)
  end

  def format(%{op: :pipe_chain, base: base, steps: steps}, opts) do
    Doc.group(
      Doc.concat([
        format(base, opts),
        Doc.concat(
          Enum.map(steps, fn step ->
            Doc.concat([Doc.break(), Doc.text("|> "), format(step, opts)])
          end)
        )
      ])
    )
  end

  def format(expr, _opts) do
    Doc.text(inspect(expr, limit: :infinity, printable_limit: 120))
  end

  @spec format_block_let_bindings([map()], map(), opts()) :: Doc.t()
  defp format_block_let_bindings(bindings, body, opts) do
    Doc.concat([
      Doc.text("let"),
      Doc.nest(1,
        Doc.concat([
          Doc.break(),
          Doc.concat(
            Enum.intersperse(Enum.map(bindings, &format_binding_entry(&1, opts)), Doc.break())
          )
        ])
      ),
      Doc.break(),
      Doc.text("in"),
      format_let_body(body, opts)
    ])
  end

  @spec compact_single_let?(map(), map()) :: boolean()
  defp compact_single_let?(%{kind: :name, name: name, value: value}, %{op: :var, name: var_name})
       when name == var_name do
    case value do
      %{op: :qualified_call, args: args} when length(args) > 1 -> false
      %{op: :call, args: args} when length(args) > 1 -> false
      other -> compact_let_body?(other)
    end
  end

  defp compact_single_let?(%{kind: kind, value: value}, body) when kind in [:name, :discard] do
    case unwrap_curried_lambda(value) do
      {args, _} when args != [] -> false
      _ -> inline_branch_body?(body) and inline_branch_body?(value)
    end
  end

  defp compact_single_let?(_, _), do: false

  @spec format_single_binding_inline(map(), opts()) :: Doc.t()
  defp format_single_binding_inline(%{kind: :name, name: name, value: value}, opts) do
    Doc.concat([Doc.text(name), Doc.text(" = "), format(value, opts)])
  end

  defp format_single_binding_inline(%{kind: :discard, value: value}, opts) do
    Doc.concat([Doc.text("_ = "), format(value, opts)])
  end

  @spec format_plain_lambda(map(), opts()) :: Doc.t()
  defp format_plain_lambda(%{args: args, body: body}, opts) do
    header =
      Doc.text("\\" <> Enum.join(Enum.map(args, &format_lambda_arg/1), " ") <> " ->")

    if multiline_body?(body) do
      Doc.concat([
        header,
        Doc.nest(1, Doc.concat([Doc.break(), format(body, opts)]))
      ])
    else
      Doc.group(Doc.concat([header, Doc.text(" "), format(body, opts)]))
    end
  end

  @spec format_pattern_lambda([String.t()], map(), [String.t()], map(), opts()) :: Doc.t()
  defp format_pattern_lambda(before_args, pattern, after_args, body, opts) do
    header =
      Doc.concat([
        Doc.text("\\"),
        format_lambda_pattern_header(before_args, pattern, after_args)
      ])

    if multiline_body?(body) do
      Doc.concat([
        header,
        Doc.nest(1, Doc.concat([Doc.break(), format(body, opts)]))
      ])
    else
      Doc.group(Doc.concat([header, Doc.text(" "), format(body, opts)]))
    end
  end

  @spec format_lambda_pattern_header([String.t()], map(), [String.t()]) :: Doc.t()
  defp format_lambda_pattern_header(before_args, pattern, after_args) do
    Doc.join(
      Enum.map(before_args, &Doc.text/1) ++
        [Doc.parens(Pattern.format(pattern))] ++
        Enum.map(after_args, &Doc.text/1) ++
        [Doc.text("->")],
      Doc.text(" ")
    )
  end

  @spec format_binding_entry(map(), opts()) :: Doc.t()
  defp format_binding_entry(%{kind: :name, name: name, value: value}, opts),
    do: format_binding({:name, name, value}, opts)

  defp format_binding_entry(%{kind: :discard, value: value}, opts),
    do: format_binding({:name, "_", value}, opts)

  defp format_binding_entry(%{kind: kind, names: names, value: value}, opts)
       when kind in [:tuple2, :tuple3] do
    format_binding({:tuple, names, value}, opts)
  end

  defp format_binding_entry(%{kind: :pattern, pattern: pattern, value: value}, opts),
    do: format_binding({:pattern, pattern, value}, opts)

  @spec collected_binding_entry(binding()) :: map()
  defp collected_binding_entry({:name, name, value}), do: %{kind: :name, name: name, value: value}

  defp collected_binding_entry({:tuple, names, value}) when length(names) == 2 do
    %{kind: :tuple2, names: names, value: value}
  end

  defp collected_binding_entry({:tuple, names, value}) when length(names) == 3 do
    %{kind: :tuple3, names: names, value: value}
  end

  defp collected_binding_entry({:pattern, pattern, value}),
    do: %{kind: :pattern, pattern: pattern, value: value}

  @spec format_binding(binding() | {atom(), term()}, opts()) :: Doc.t()
  defp format_binding({:tuple, names, value}, opts) do
    Doc.concat([
      Doc.concat([Doc.parens(Doc.text(Enum.join(names, ", "))), Doc.text(" =")]),
      format_binding_rhs(value, opts)
    ])
  end

  defp format_binding({:pattern, pattern, value}, opts) do
    Doc.concat([
      pattern_binding_doc(pattern),
      Doc.text(" ="),
      format_binding_rhs(value, opts)
    ])
  end

  defp format_binding({:name, name, value}, opts) do
    case unwrap_curried_lambda(value) do
      {args, body} when args != [] ->
        Doc.concat([
          Doc.text(name <> " " <> Enum.join(args, " ") <> " ="),
          format_binding_rhs(body, opts)
        ])

      _ ->
        Doc.concat([
          Doc.text(name),
          Doc.text(" ="),
          format_binding_rhs(value, opts)
        ])
    end
  end

  defp format_binding_rhs(body, opts) do
    if multiline_body?(body) do
      Doc.nest(1, Doc.concat([Doc.break(), format(body, opts)]))
    else
      Doc.concat([Doc.text(" "), format(body, opts)])
    end
  end

  defp format_infix_expr(left, op, right, opts, kind) do
    left_doc = format_infix_operand(left, opts, kind, :left)
    right_doc = format_infix_operand(right, opts, kind, :right)

    if multiline_body?(right) or multiline_arg?(left) do
      Doc.group(
        Doc.concat([
          left_doc,
          Doc.break(),
          Doc.text(op <> " "),
          right_doc
        ])
      )
    else
      Doc.group(Doc.concat([left_doc, Doc.text(" " <> op <> " "), right_doc]))
    end
  end

  defp format_infix_operand(expr, opts, kind, side) do
    if infix_operand_needs_parens?(expr, kind, side) do
      Doc.parens(format(expr, opts))
    else
      format(expr, opts)
    end
  end

  defp infix_operand_needs_parens?(%{op: op}, :cons, :right)
       when op in [:case, :if, :let_bindings, :let_in, :lambda],
       do: true

  defp infix_operand_needs_parens?(%{op: :bool_or}, :bool_and, :right), do: true

  defp infix_operand_needs_parens?(%{op: :bool_and}, :bool_or, :left), do: true

  defp infix_operand_needs_parens?(%{op: :call, name: "__append__"}, :append, :left), do: true

  defp infix_operand_needs_parens?(%{op: :qualified_call, target: "List.cons"}, :append, :left),
    do: true

  defp infix_operand_needs_parens?(%{op: :call, name: "__append__"}, :cons, :left), do: true

  defp infix_operand_needs_parens?(%{op: :qualified_call, target: "List.cons"}, :cons, :right),
    do: true

  defp infix_operand_needs_parens?(expr, kind, side) do
    case infix_expr_kind(expr) do
      {:ok, inner_kind} -> precedence_parens?(inner_kind, kind, side)
      :error -> false
    end
  end

  @spec infix_expr_kind(map()) :: {:ok, atom()} | :error
  defp infix_expr_kind(%{op: :add_vars}), do: {:ok, :add}
  defp infix_expr_kind(%{op: :add_const}), do: {:ok, :add}
  defp infix_expr_kind(%{op: :sub_const}), do: {:ok, :sub}
  defp infix_expr_kind(%{op: :sub_vars}), do: {:ok, :sub}

  defp infix_expr_kind(%{op: :call, name: name}) when name in ["__add__", "__sub__", "__mul__", "__fdiv__", "__idiv__", "__pow__"],
    do: {:ok, infix_kind(name)}

  defp infix_expr_kind(%{op: :compare}), do: {:ok, :compare}
  defp infix_expr_kind(%{op: :bool_and}), do: {:ok, :bool_and}
  defp infix_expr_kind(%{op: :bool_or}), do: {:ok, :bool_or}
  defp infix_expr_kind(%{op: :call, name: "__append__"}), do: {:ok, :append}
  defp infix_expr_kind(%{op: :qualified_call, target: "List.cons"}), do: {:ok, :cons}
  defp infix_expr_kind(_), do: :error

  @spec precedence_parens?(atom(), atom(), :left | :right) :: boolean()
  defp precedence_parens?(inner_kind, outer_kind, side) do
    {inner_prec, inner_assoc} = infix_prec_assoc(inner_kind)
    {outer_prec, outer_assoc} = infix_prec_assoc(outer_kind)

    cond do
      inner_prec < outer_prec -> true
      inner_prec > outer_prec -> false
      inner_assoc == :nonassoc or outer_assoc == :nonassoc -> true
      inner_assoc == :left and side == :right -> true
      inner_assoc == :right and side == :left -> true
      true -> false
    end
  end

  @spec infix_prec_assoc(atom()) :: {non_neg_integer(), :left | :right | :nonassoc}
  defp infix_prec_assoc(:cons), do: {100, :right}
  defp infix_prec_assoc(:append), do: {110, :left}
  defp infix_prec_assoc(:bool_or), do: {120, :left}
  defp infix_prec_assoc(:bool_and), do: {130, :left}
  defp infix_prec_assoc(:compare), do: {140, :nonassoc}
  defp infix_prec_assoc(:add), do: {150, :left}
  defp infix_prec_assoc(:sub), do: {150, :left}
  defp infix_prec_assoc(:mul), do: {160, :left}
  defp infix_prec_assoc(:fdiv), do: {160, :left}
  defp infix_prec_assoc(:idiv), do: {160, :left}
  defp infix_prec_assoc(:pow), do: {170, :right}
  defp infix_prec_assoc(:pipe_dot), do: {200, :left}
  defp infix_prec_assoc(:pipe_eq), do: {200, :left}

  @spec infix_kind(String.t()) :: atom()
  defp infix_kind("__add__"), do: :add
  defp infix_kind("__sub__"), do: :sub
  defp infix_kind("__mul__"), do: :mul
  defp infix_kind("__fdiv__"), do: :fdiv
  defp infix_kind("__idiv__"), do: :idiv
  defp infix_kind("__pow__"), do: :pow

  @spec compact_list_items?([map()]) :: boolean()
  defp compact_list_items?(items), do: Enum.all?(items, &compact_list_item?/1)

  @spec compact_list_item?(map()) :: boolean()
  defp compact_list_item?(%{op: op})
       when op in [
              :var,
              :int_literal,
              :float_literal,
              :string_literal,
              :char_literal,
              :constructor_ref,
              :qualified_ref
            ],
       do: true

  defp compact_list_item?(%{op: :list_literal, items: items}), do: compact_list_items?(items)
  defp compact_list_item?(%{op: :call, name: _name, args: args}) when is_list(args),
    do: length(args) <= 2 and Enum.all?(args, &compact_list_item?/1)

  defp compact_list_item?(%{op: :qualified_call, args: args}) when is_list(args),
    do: length(args) <= 2 and Enum.all?(args, &compact_list_item?/1)

  defp compact_list_item?(_), do: false

  defp format_inline_first_siblings(rest, opts) do
    Doc.nest(
      4,
      Doc.concat([
        Doc.break(),
        Doc.concat(
          Enum.intersperse(Enum.map(rest, &format_binding_entry(&1, opts)), Doc.break())
        )
      ])
    )
  end

  defp format_let_body(body, opts) do
    if multiline_body?(body) or not compact_let_body?(body) do
      Doc.nest(1, Doc.concat([Doc.break(), format(body, opts)]))
    else
      Doc.concat([Doc.text(" "), format(body, opts)])
    end
  end

  defp compact_let_body?(%{op: :var}), do: true

  defp compact_let_body?(%{op: op})
       when op in [:int_literal, :float_literal, :string_literal, :char_literal, :constructor_ref],
       do: true

  defp compact_let_body?(%{op: :call, args: args}) when is_list(args) and length(args) <= 2, do: true
  defp compact_let_body?(%{op: :qualified_call, args: args}) when is_list(args) and length(args) <= 2,
    do: true

  defp compact_let_body?(_), do: false

  defp format_compose(left, op, right, opts) do
    left_doc = format_subject(left, opts)
    right_doc = format_subject(right, opts)

    if multiline_body?(right) or multiline_arg?(left) do
      Doc.group(Doc.concat([left_doc, Doc.break(), Doc.text(op <> " "), right_doc]))
    else
      Doc.group(Doc.concat([left_doc, Doc.text(op), right_doc]))
    end
  end

  @spec format_condition(map(), opts()) :: Doc.t()
  defp format_condition(expr, opts) do
    case desugar_inclusive_compare(expr) do
      {:ok, op, left, right} ->
        Doc.concat([format(left, opts), Doc.text(" #{op} "), format(right, opts)])

      :error ->
        format(expr, opts)
    end
  end

  @spec format_if_expr(map(), map(), map(), opts()) :: Doc.t()
  defp format_if_expr(cond, then_expr, else_expr, opts) do
    if inline_if_chain?(then_expr, else_expr) do
      Doc.group(
        Doc.concat([
          Doc.text("if "),
          format_condition(cond, opts),
          Doc.text(" then "),
          format(then_expr, opts),
          Doc.text(" "),
          format_else_inline(else_expr, opts)
        ])
      )
    else
      Doc.concat([
        Doc.text("if "),
        format_condition(cond, opts),
        Doc.text(" then"),
        Doc.nest(1, Doc.concat([Doc.break(), format(then_expr, opts)])),
        Doc.break(),
        format_else_expr(else_expr, opts)
      ])
    end
  end

  @spec format_else_inline(map(), opts()) :: Doc.t()
  defp format_else_inline(%{op: :if} = expr, opts) do
    {cond, then_expr, else_expr} = if_parts(expr)

    Doc.concat([
      Doc.text("else if "),
      format_condition(cond, opts),
      Doc.text(" then "),
      format(then_expr, opts),
      Doc.text(" "),
      format_else_inline(else_expr, opts)
    ])
  end

  defp format_else_inline(expr, opts) do
    Doc.concat([Doc.text("else "), format(expr, opts)])
  end

  @spec inline_if_chain?(map(), map()) :: boolean()
  defp inline_if_chain?(then_expr, else_expr) do
    inline_branch_body?(then_expr) and inline_else_chain?(else_expr)
  end

  @spec inline_else_chain?(map()) :: boolean()
  defp inline_else_chain?(%{op: :if} = expr) do
    {_cond, then_expr, else_expr} = if_parts(expr)
    inline_branch_body?(then_expr) and inline_else_chain?(else_expr)
  end

  defp inline_else_chain?(expr), do: inline_branch_body?(expr)

  @spec format_else_expr(map(), opts()) :: Doc.t()
  defp format_else_expr(%{op: :if} = expr, opts) do
    {cond, then_expr, else_expr} = if_parts(expr)

    if inline_if_chain?(then_expr, else_expr) do
      format_else_inline(expr, opts)
    else
      Doc.concat([
        Doc.text("else if "),
        format_condition(cond, opts),
        Doc.text(" then"),
        Doc.nest(1, Doc.concat([Doc.break(), format(then_expr, opts)])),
        Doc.break(),
        format_else_expr(else_expr, opts)
      ])
    end
  end

  defp format_else_expr(expr, opts) do
    Doc.concat([
      Doc.text("else"),
      Doc.nest(1, Doc.concat([Doc.break(), format(expr, opts)]))
    ])
  end

  @spec format_branch(map(), opts()) :: Doc.t()
  defp format_branch(%{pattern: pattern, expr: expr}, opts) do
    pattern_doc = Pattern.format(pattern)
    expr_doc = format(expr, opts)

    if inline_case_branch?(pattern, expr, opts) do
      Doc.group(Doc.concat([pattern_doc, Doc.text(" -> "), expr_doc]))
    else
      Doc.concat([
        pattern_doc,
        Doc.text(" ->"),
        Doc.nest(1, Doc.concat([Doc.break(), expr_doc]))
      ])
    end
  end

  @spec inline_case_branch?(map(), map(), opts()) :: boolean()
  defp inline_case_branch?(_pattern, expr, opts) do
    Keyword.get(opts, :case_depth, 0) == 1 and inline_branch_body?(expr) and
      not case_like_body?(expr) and not let_like_body?(expr)
  end

  @spec let_like_body?(map()) :: boolean()
  defp let_like_body?(%{op: op}) when op in [:let_bindings, :let_in], do: true
  defp let_like_body?(_), do: false

  @spec case_like_body?(map()) :: boolean()
  defp case_like_body?(%{op: :case}), do: true

  defp case_like_body?(%{op: :let_bindings, in_expr: body}), do: case_like_body?(body)
  defp case_like_body?(%{op: :let_in, in_expr: body}), do: case_like_body?(body)
  defp case_like_body?(_), do: false

  @spec inline_branch_body?(map()) :: boolean()
  defp inline_branch_body?(expr) do
    not multiline_body?(expr) and not multiline_arg?(expr)
  end

  @spec format_inline_record([map()], opts()) :: Doc.t()
  defp format_inline_record(fields, opts) do
    field_docs = Enum.map(fields, &format_inline_record_field(&1, opts))

    Doc.group(
      Doc.concat([
        Doc.text("{"),
        Doc.join(field_docs, Doc.text(", ")),
        Doc.text("}")
      ])
    )
  end

  @spec format_inline_record_field(map(), opts()) :: Doc.t()
  defp format_inline_record_field(%{name: name, expr: expr}, opts) do
    Doc.concat([Doc.text(name), Doc.text(" = "), format(expr, opts)])
  end

  @spec format_record_field(map(), opts()) :: Doc.t()
  defp format_record_field(%{name: name, expr: expr}, opts) do
    Doc.concat([
      Doc.text(name),
      Doc.text(" ="),
      format_record_field_rhs(expr, opts)
    ])
  end

  defp format_record_field_rhs(expr, opts) do
    if multiline_body?(expr) or multiline_arg?(expr) do
      Doc.nest(1, Doc.concat([Doc.break(), format(expr, opts)]))
    else
      Doc.concat([Doc.text(" "), format(expr, opts)])
    end
  end

  @spec multiline_record?([map()]) :: boolean()
  defp multiline_record?(fields) do
    not compact_record_fields?(fields)
  end

  @spec compact_record_fields?([map()]) :: boolean()
  defp compact_record_fields?(fields) do
    length(fields) <= 4 and
      Enum.all?(fields, fn %{expr: expr} -> compact_list_item?(expr) end)
  end

  @spec format_multiline_record_fields([map()], opts()) :: Doc.t()
  defp format_multiline_record_fields(fields, opts) do
    fields
    |> Enum.with_index()
    |> Enum.map(fn {field, index} ->
      prefix =
        if index == 0 do
          Doc.text("")
        else
          Doc.concat([Doc.text(","), Doc.break()])
        end

      Doc.concat([prefix, format_record_field(field, opts)])
    end)
    |> then(&Doc.concat/1)
  end

  @spec format_record_update(map(), [map()], opts()) :: Doc.t()
  defp format_record_update(base, fields, opts) do
    field_docs = Enum.map(fields, &format_record_field(&1, opts))

    multiline? =
      multiline_body?(base) or
        Enum.any?(fields, fn %{expr: expr} -> multiline_body?(expr) end) or length(fields) > 2

    if multiline? do
      Doc.concat([
        Doc.text("{ "),
        format(base, opts),
        Doc.nest(
          1,
          Doc.concat([
            Doc.break(),
            Doc.text("| "),
            Doc.concat(Enum.intersperse(field_docs, Doc.concat([Doc.text(","), Doc.break()])))
          ])
        ),
        Doc.break(),
        Doc.text("}")
      ])
    else
      Doc.concat([
        Doc.text("{"),
        format(base, opts),
        Doc.text(" | "),
        Doc.concat(Enum.intersperse(field_docs, Doc.text(", "))),
        Doc.text("}")
      ])
    end
  end

  @spec format_call(String.t(), [map()], opts()) :: Doc.t()
  defp format_call(name, args, opts) do
    cond do
      args == [] ->
        Doc.text(name)

      Enum.any?(args, &multiline_arg?/1) ->
        {inline_args, multiline_args} = Enum.split_while(args, &(not multiline_arg?(&1)))

        Doc.concat([
          Doc.text(name),
          format_inline_call_args(inline_args, opts),
          Doc.nest(
            1,
            Doc.concat(
              Enum.map(multiline_args, fn arg ->
                Doc.concat([Doc.break(), format_multiline_call_argument(arg, opts)])
              end)
            )
          )
        ])

      true ->
        Doc.concat([
          Doc.text(name),
          Doc.text(" "),
          Doc.join(
            args
            |> Enum.with_index()
            |> Enum.map(fn {arg, idx} -> format_call_arg(arg, opts, idx, length(args) - 1) end),
            Doc.text(" ")
          )
        ])
    end
  end

  @spec format_inline_call_args([map()], opts()) :: Doc.t()
  defp format_inline_call_args([], _opts), do: Doc.text("")

  defp format_inline_call_args(args, opts) do
    Doc.concat([
      Doc.text(" "),
      Doc.join(Enum.map(args, &format_call_argument(&1, opts)), Doc.text(" "))
    ])
  end

  @spec format_call_arg(map(), opts(), non_neg_integer(), non_neg_integer()) :: Doc.t()
  defp format_call_arg(arg, opts, _index, _last_index) do
    format_call_argument(arg, opts)
  end

  @spec format_call_argument(map(), opts()) :: Doc.t()
  defp format_call_argument(arg, opts) do
    doc = format(arg, opts)

    if call_argument_needs_parens?(arg) do
      Doc.parens(doc)
    else
      doc
    end
  end

  @spec format_multiline_call_argument(map(), opts()) :: Doc.t()
  defp format_multiline_call_argument(%{op: :record_literal} = arg, opts), do: format(arg, opts)

  defp format_multiline_call_argument(arg, opts) do
    if multiline_arg?(arg) do
      Doc.parens(format(arg, opts))
    else
      format_call_argument(arg, opts)
    end
  end

  @spec call_argument_needs_parens?(map()) :: boolean()
  defp call_argument_needs_parens?(%{op: :call, name: name, args: [_]})
       when name in @operator_vars,
       do: true

  defp call_argument_needs_parens?(%{op: :apply_left}), do: true

  defp call_argument_needs_parens?(%{op: :pipe_chain}), do: true

  defp call_argument_needs_parens?(%{op: op})
       when op in [:char_from_code_expr, :tuple_first_expr, :tuple_second_expr, :string_length_expr],
       do: true

  defp call_argument_needs_parens?(arg) do
    cond do
      nested_call_expr?(arg) ->
        true

      match?({:ok, _}, infix_expr_kind(arg)) ->
        true

      match?(%{op: :lambda}, arg) ->
        true

      true ->
        false
    end
  end

  @spec format_lambda_arg(String.t()) :: String.t()
  defp format_lambda_arg("ignoredArg"), do: "_"

  defp format_lambda_arg("ignoredArg" <> suffix) when suffix != "" do
    if String.match?(suffix, ~r/^\d+$/), do: "_", else: "ignoredArg" <> suffix
  end

  defp format_lambda_arg(name), do: name

  @spec nested_call_expr?(map()) :: boolean()
  defp nested_call_expr?(%{op: op}) when op in [:call, :qualified_call, :constructor_call, :field_call], do: true
  defp nested_call_expr?(_), do: false

  @spec format_multiline_list([map()], opts()) :: Doc.t()
  defp format_multiline_list(items, opts) do
    Doc.concat([
      Doc.text("["),
      Doc.concat(
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          prefix =
            if index == 0 do
              Doc.concat([Doc.text(" "), format_list_item(item, opts)])
            else
              Doc.concat([Doc.break(), Doc.text(", "), format_list_item(item, opts)])
            end

          prefix
        end)
      ),
      Doc.break(),
      Doc.text("]")
    ])
  end

  @spec format_list_item(map(), opts()) :: Doc.t()
  defp format_list_item(item, opts) do
    doc = format(item, opts)

    if list_item_needs_parens?(item) do
      Doc.parens(doc)
    else
      doc
    end
  end

  @spec list_item_needs_parens?(map()) :: boolean()
  defp list_item_needs_parens?(item) do
    case item do
      %{op: op, args: args} when op in [:call, :qualified_call, :constructor_call, :field_call] and args != [] ->
        true

      _ ->
        call_argument_needs_parens?(item)
    end
  end

  @spec format_field_receiver(map() | String.t(), opts()) :: Doc.t()
  defp format_field_receiver(subject, opts) do
    doc = format_subject(subject, opts)

    if field_receiver_needs_parens?(subject) do
      Doc.parens(doc)
    else
      doc
    end
  end

  @spec field_receiver_needs_parens?(map() | String.t()) :: boolean()
  defp field_receiver_needs_parens?(%{op: op}) when op in [:field_call, :field_access, :apply_left], do: true
  defp field_receiver_needs_parens?(_), do: false

  @spec format_subject(map() | String.t(), opts()) :: Doc.t()
  defp format_subject(subject, _opts) when is_binary(subject), do: Doc.text(subject)
  defp format_subject(subject, opts), do: format(subject, opts)

  @spec collect_lets(map()) :: {[binding()], map()}
  defp collect_lets(%{op: :let_in, name: name, value_expr: value, in_expr: rest}) do
    case collapse_synthetic_let(name, value, rest) do
      {:pattern, pattern, collapsed_rest} ->
        {rest_bindings, body} = collect_lets(collapsed_rest)
        {[{:pattern, pattern, value} | rest_bindings], body}

      {:tuple, names, collapsed_rest} ->
        {rest_bindings, body} = collect_lets(collapsed_rest)
        {[{:tuple, names, value} | rest_bindings], body}

      :error ->
        {rest_bindings, body} = collect_lets(rest)
        {[{:name, name, value} | rest_bindings], body}
    end
  end

  defp collect_lets(body), do: {[], body}

  @spec collapse_synthetic_let(String.t(), map(), map()) ::
          {:pattern, map(), map()} | {:tuple, [String.t()], map()} | :error
  defp collapse_synthetic_let("__patternBind_" <> _ = tmp, _value, %{
         op: :case,
         subject: %{op: :var, name: subject},
         branches: [%{pattern: pattern, expr: body}]
       })
       when subject == tmp do
    {:pattern, pattern, body}
  end

  defp collapse_synthetic_let("__tupleBind_" <> suffix, _value, rest) do
    names = String.split(suffix, "_")

    case match_tuple_projection_lets(names, rest) do
      {:ok, body} -> {:tuple, names, body}
      :error -> :error
    end
  end

  defp collapse_synthetic_let(_name, _value, _rest), do: :error

  @spec match_tuple_projection_lets([String.t()], map()) :: {:ok, map()} | :error
  defp match_tuple_projection_lets(names, rest) do
    total = length(names)
    tmp = "__tupleBind_" <> Enum.join(names, "_")
    walk_tuple_projection(names, tmp, rest, 0, total)
  end

  defp walk_tuple_projection([], _tmp, body, _index, _total), do: {:ok, body}

  defp walk_tuple_projection([name | names], tmp, %{op: :let_in, name: let_name, value_expr: proj, in_expr: rest}, index, total) do
    if let_name == name and projection_expr?(proj, tmp, index, total) do
      walk_tuple_projection(names, tmp, rest, index + 1, total)
    else
      :error
    end
  end

  defp walk_tuple_projection(_names, _tmp, _rest, _index, _total), do: :error

  @spec projection_expr?(map(), String.t(), non_neg_integer(), pos_integer()) :: boolean()
  defp projection_expr?(expr, tmp, index, total) do
    expr == expected_projection(tmp, index, total)
  end

  @spec expected_projection(String.t(), non_neg_integer(), pos_integer()) :: map()
  defp expected_projection(tmp, 0, _total), do: tuple_call("Tuple.first", tmp_var(tmp))

  defp expected_projection(tmp, index, total) when index == total - 1 do
    nested_tuple_second(tmp, index)
  end

  defp expected_projection(tmp, index, _total) do
    tuple_call("Tuple.first", nested_tuple_second(tmp, index))
  end

  defp nested_tuple_second(tmp, 1), do: tuple_call("Tuple.second", tmp_var(tmp))
  defp nested_tuple_second(tmp, n) when n > 1, do: tuple_call("Tuple.second", nested_tuple_second(tmp, n - 1))

  defp tuple_call(target, arg), do: %{op: :qualified_call, target: target, args: [arg]}
  defp tmp_var(name), do: %{op: :var, name: name}

  @spec unwrap_lambda_case_chain(map()) :: {[String.t()], map(), map()} | :error
  defp unwrap_lambda_case_chain(%{
         op: :lambda,
         args: [arg],
         body: %{
           op: :case,
           subject: %{op: :var, name: subject},
           branches: [%{pattern: pattern, expr: body}]
         }
       })
       when subject == arg do
    {[], pattern, body}
  end

  defp unwrap_lambda_case_chain(%{op: :lambda, args: [arg], body: body}) do
    case unwrap_lambda_case_chain(body) do
      {args, pattern, inner} -> {[arg | args], pattern, inner}
      :error -> :error
    end
  end

  defp unwrap_lambda_case_chain(_), do: :error

  @spec unwrap_curried_lambda(map()) :: {[String.t()], map()} | :error
  defp unwrap_curried_lambda(%{op: :lambda, args: [arg], body: body}) when is_binary(arg) do
    case unwrap_curried_lambda(body) do
      {rest, inner} -> {[arg | rest], inner}
      :error -> {[arg], body}
    end
  end

  defp unwrap_curried_lambda(_), do: :error

  @spec peel_simple_lambda_args(map()) :: {[String.t()], map()}
  defp peel_simple_lambda_args(%{op: :lambda, args: [arg], body: body}) when is_binary(arg) do
    {rest, inner} = peel_simple_lambda_args(body)
    {[arg | rest], inner}
  end

  defp peel_simple_lambda_args(body), do: {[], body}

  @spec pattern_binding_doc(map()) :: Doc.t()
  defp pattern_binding_doc(pattern) do
    if binding_pattern_needs_parens?(pattern) do
      Doc.parens(Pattern.format(pattern))
    else
      Pattern.format(pattern)
    end
  end

  @spec binding_pattern_needs_parens?(map()) :: boolean()
  defp binding_pattern_needs_parens?(%{kind: :constructor, bind: bind}) when is_binary(bind), do: true
  defp binding_pattern_needs_parens?(%{kind: :constructor, arg_pattern: arg}) when not is_nil(arg), do: true
  defp binding_pattern_needs_parens?(_), do: false

  @spec desugar_inclusive_compare(map()) :: {:ok, String.t(), map(), map()} | :error
  defp desugar_inclusive_compare(%{
         op: :if,
         cond: %{op: :compare, kind: :lt, left: left, right: right},
         then_expr: %{op: :constructor_ref, target: "True"},
         else_expr: %{op: :compare, kind: :eq, left: left, right: right}
       }) do
    {:ok, "<=", left, right}
  end

  defp desugar_inclusive_compare(%{
         op: :if,
         cond: %{op: :compare, kind: :gt, left: left, right: right},
         then_expr: %{op: :constructor_ref, target: "True"},
         else_expr: %{op: :compare, kind: :eq, left: left, right: right}
       }) do
    {:ok, ">=", left, right}
  end

  defp desugar_inclusive_compare(_), do: :error

  @spec resugar_inclusive_compare_or(map(), map()) :: {:ok, String.t(), map(), map()} | :error
  defp resugar_inclusive_compare_or(
         %{op: :compare, kind: :gt, left: left, right: right},
         %{op: :compare, kind: :eq, left: left, right: right}
       ) do
    {:ok, ">=", left, right}
  end

  defp resugar_inclusive_compare_or(
         %{op: :compare, kind: :lt, left: left, right: right},
         %{op: :compare, kind: :eq, left: left, right: right}
       ) do
    {:ok, "<=", left, right}
  end

  defp resugar_inclusive_compare_or(_, _), do: :error

  @spec flatten_tuple2(map(), map()) :: [map()]
  defp flatten_tuple2(left, right) do
    [left | tuple2_tail(right)]
  end

  defp tuple2_tail(%{op: :tuple2, left: left, right: right}), do: [left | tuple2_tail(right)]
  defp tuple2_tail(other), do: [other]

  @spec format_tuple_elements([map()], opts()) :: Doc.t()
  defp format_tuple_elements([], _opts), do: Doc.text("()")

  defp format_tuple_elements([single], opts) do
    Doc.parens(format(single, opts))
  end

  defp format_tuple_elements(elements, opts) do
    if compact_tuple_elements?(elements) do
      Doc.parens(Doc.join(Enum.map(elements, &format(&1, opts)), Doc.text(", ")))
    else
      format_multiline_tuple(elements, opts)
    end
  end

  defp format_multiline_tuple(elements, opts) do
    [first | rest] = elements

    Doc.concat([
      Doc.text("( "),
      format(first, opts),
      Doc.concat(
        Enum.map(rest, fn item ->
          Doc.concat([Doc.break(), Doc.text(", "), format(item, opts)])
        end)
      ),
      Doc.break(),
      Doc.text(")")
    ])
  end

  defp compact_tuple_elements?(elements), do: Enum.all?(elements, &compact_list_item?/1)

  @spec multiline_body?(map()) :: boolean()
  defp multiline_body?(%{op: op})
       when op in [:let_in, :let_bindings, :case, :if, :apply_left, :compose_left, :compose_right],
       do: true

  defp multiline_body?(%{op: :lambda, body: body}), do: multiline_body?(body)

  defp multiline_body?(%{op: op}) when op in [:pipe_chain, :record_update], do: true

  defp multiline_body?(_), do: false

  @spec multiline_arg?(map()) :: boolean()
  defp multiline_arg?(%{op: :record_literal, fields: fields}), do: multiline_record?(fields)
  defp multiline_arg?(%{op: :lambda, body: body}), do: multiline_body?(body)
  defp multiline_arg?(%{op: :case}), do: true
  defp multiline_arg?(%{op: :let_in}), do: true
  defp multiline_arg?(_), do: false

  @spec if_parts(map()) :: {map(), map(), map()}
  defp if_parts(expr) do
    {
      Map.fetch!(expr, :cond),
      Map.get(expr, :then_expr) || Map.get(expr, :then),
      Map.get(expr, :else_expr) || Map.get(expr, :else)
    }
  end

  @spec compare_op(atom()) :: String.t()
  defp compare_op(:eq), do: "=="
  defp compare_op(:neq), do: "/="
  defp compare_op(:gt), do: ">"
  defp compare_op(:gte), do: ">="
  defp compare_op(:lt), do: "<"
  defp compare_op(:lte), do: "<="

  @spec format_partial_infix(String.t(), map(), opts()) :: Doc.t()
  defp format_partial_infix(name, arg, opts) do
    Doc.concat([
      Doc.parens(Doc.text(infix_op(name))),
      Doc.text(" "),
      format(arg, opts)
    ])
  end

  defp infix_op("__add__"), do: "+"
  defp infix_op("__sub__"), do: "-"
  defp infix_op("__mul__"), do: "*"
  defp infix_op("__fdiv__"), do: "/"
  defp infix_op("__idiv__"), do: "//"
  defp infix_op("__pow__"), do: "^"

  defp float_to_string(value) when is_float(value), do: Float.to_string(value)
  defp float_to_string(value) when is_integer(value), do: Integer.to_string(value) <> ".0"
end
