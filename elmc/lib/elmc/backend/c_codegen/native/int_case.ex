defmodule Elmc.Backend.CCodegen.Native.IntCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.ImmortalStringLiteral
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Types

  @min_string_lut_branches 3
  @spec branches?(Types.int_case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    {int_values, wildcard_indexes} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({[], []}, fn {branch, index}, {ints, wildcards} ->
        case branch.pattern do
          %{kind: :int, value: value} when is_integer(value) ->
            {:cont, {[value | ints], wildcards}}

          %{kind: :wildcard} ->
            {:cont, {ints, [index | wildcards]}}

          _ ->
            {:halt, {:invalid, :invalid}}
        end
      end)

    case {int_values, wildcard_indexes} do
      {:invalid, :invalid} ->
        false

      {ints, wildcards} ->
        unique_ints? = length(ints) == length(Enum.uniq(ints))
        wildcard_last? = wildcards == [] or wildcards == [length(branches) - 1]
        unique_ints? and wildcard_last?
    end
  end

  def branches?(_branches), do: false

  @spec subject_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def subject_expr?(subject_expr, env) do
    case subject_expr do
      %{op: :var, name: name} when is_binary(name) or is_atom(name) ->
        is_binary(EnvBindings.native_int_binding(env, name))

      _ ->
        NativeInt.expr?(subject_expr, env)
    end
  end

  @spec compile(Types.ir_expr(), Types.int_case_branches(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(subject_expr, branches, env, counter),
    do: compile(subject_expr, branches, env, counter, :boxed)

  @spec compile_scalar(
          Types.ir_expr(),
          Types.int_case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.native_scalar_compile_result()
  def compile_scalar(subject_expr, branches, env, counter) do
    compile(subject_expr, branches, env, counter, :native_int)
  end

  defp compile(subject_expr, branches, env, counter, :boxed) do
    cond do
      string_lookup_table_eligible?(branches) ->
        compile_string_lookup_table(subject_expr, branches, env, counter)

      boxed_lookup_table_eligible?(branches, env) ->
        compile_boxed_lookup_table(subject_expr, branches, env, counter)

      true ->
        compile_boxed_switch(subject_expr, branches, env, counter)
    end
  end

  defp compile(subject_expr, branches, env, counter, :native_int) do
    case_expr = %{op: :case, subject: subject_expr, branches: branches}

    case ConstantInt.literal_value(case_expr, env) do
      {:ok, value} ->
        {"", Integer.to_string(value), counter}

      :error ->
        if lookup_table_eligible?(branches) do
          compile_lookup_table(subject_expr, branches, env, counter)
        else
          compile_scalar_switch(subject_expr, branches, env, counter)
        end
    end
  end

  defp compile_boxed_switch(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    {out, next, declare_out?} = CaseCompile.result_out_binding(env, counter)
    exhaustive? = has_default?(branches)
    initial_value = if exhaustive?, do: nil, else: "elmc_int_zero()"
    rc_catch? = RcRuntimeEmit.rc_allocator_emit_mode?(env)

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        FunctionCallCompile.reset_call_args_cache!()

        branch_env =
          env
          |> RecordCompile.fresh_subexpr_cache()
          |> Map.put(:__into_out__, out)
          |> Map.put(:__rc_catch__, false)

        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, branch_env, c)

        label = case_label(branch.pattern)
        release_previous =
          if exhaustive? or RcRuntimeEmit.function_out_ref?(out),
            do: "",
            else: "elmc_release(#{RcRuntimeEmit.value_expr(out)});"

        snippet = """
        #{label}:
        #{CSource.indent(expr_code, 4)}
        #{CSource.indent(release_previous, 4)}
        #{CSource.indent(assignment_code, 4)}
            break;
        """

        {acc <> snippet, c2}
      end)

    result_decl =
      cond do
        declare_out? -> CaseCompile.result_out_decl(out, true)
        rc_catch? and initial_value == nil -> ""
        rc_catch? -> "#{out} = #{initial_value};"
        true -> boxed_result_decl(out, initial_value)
      end

    post_switch = if rc_catch?, do: "  CHECK_RC(Rc);", else: ""

    code = """
    #{subject_code}
      #{result_decl}
      switch (#{subject_ref}) {
      #{branch_code}
      }
    #{post_switch}
    """

    {code, out, final_counter}
  end

  defp format_lut_initializer(values) when is_list(values) do
    flat = Enum.join(values, ", ")

    if length(values) <= 4 and String.length(flat) <= 72 do
      {:inline, flat}
    else
      body =
        values
        |> Enum.map(&"    #{&1}")
        |> Enum.intersperse(",\n")
        |> IO.iodata_to_binary()

      {:multiline, body}
    end
  end

  defp lut_array_decl(lut, size, {:inline, values}) do
    "static const elmc_int_t #{lut}[#{size}] = { #{values} };"
  end

  defp lut_array_decl(lut, size, {:multiline, values}) do
    """
    static const elmc_int_t #{lut}[#{size}] = {
    #{values}
    };
    """
    |> String.trim_trailing()
  end

  defp compile_string_lookup_table(subject_expr, branches, env, counter) do
    {entries, size, has_wildcard?} = string_lut_entries(branches)
    case_expr = %{op: :case, subject: subject_expr, branches: branches}
    {out, _out_next, declare_out?} = CaseCompile.result_out_binding(env, counter)

    case ConstantInt.literal_value(case_expr, env) do
      {:ok, subject_value} ->
        index = string_lut_index_value(subject_value, size, has_wildcard?)
        literal = Enum.at(entries, index)
        lit_name = "native_str_immortal_#{counter + 1}"
        decl = ImmortalStringLiteral.static_decl(lit_name, literal)
        assign = ImmortalStringLiteral.assign_ref(env, out, "&#{lit_name}")

        code =
          """
          #{decl}
          #{if(declare_out?, do: CaseCompile.result_out_decl(out, true) <> "\n  ", else: "")}#{assign}
          """
          |> String.trim_trailing()

        {code, out, counter + 1}

      :error ->
        {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
        next = counter + 1
        lut = "native_str_immortal_lut_#{next}"
        index = string_lut_index(subject_ref, size, has_wildcard?)
        assign = ImmortalStringLiteral.assign_ref(env, out, "&#{lut}[#{index}]")

        code = """
        #{subject_code}
          #{ImmortalStringLiteral.array_decl(lut, entries)}
          #{if(declare_out?, do: CaseCompile.result_out_decl(out, true) <> "\n  ", else: "")}#{assign}
        """

        {code, out, next}
    end
  end

  defp compile_boxed_lookup_table(subject_expr, branches, env, counter) do
    {literal_entries, size, int_count, has_wildcard?} = lookup_table_boxed_entries(branches)
    {out, out_counter, declare_out?} = CaseCompile.result_out_binding(env, counter)

    refs =
      Enum.map(literal_entries, fn expr ->
        {:ok, ref} = lookup_table_branch_ref(expr, env)
        ref
      end)

    case_expr = %{op: :case, subject: subject_expr, branches: branches}
    out_decl_prefix = if declare_out?, do: CaseCompile.result_out_decl(out, true) <> "\n  ", else: ""

    case ConstantInt.literal_value(case_expr, env) do
      {:ok, subject_value} ->
        index = bounded_lookup_index_value(subject_value, int_count, has_wildcard?)
        ref = Enum.at(refs, index)
        next = max(out_counter, counter + 1)

        code = """
          #{out_decl_prefix}#{RcRuntimeEmit.assign_into(RcRuntimeEmit.rc_catch_env(env), out, "elmc_new_int", ref)}
        """

        {code, out, next}

      :error ->
        {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
        next = max(out_counter, counter) + 1
        lut = "native_lut_#{next}"
        scratch = "native_case_#{next}"
        values = format_lut_initializer(refs)
        index = bounded_lookup_index(subject_ref, int_count, has_wildcard?)

        code = """
        #{subject_code}
          #{lut_array_decl(lut, size, values)}
          elmc_int_t #{scratch} = #{lut}[#{index}];
          #{out_decl_prefix}#{RcRuntimeEmit.assign_into(RcRuntimeEmit.rc_catch_env(env), out, "elmc_new_int", scratch)}
        """

        {code, out, next}
    end
  end

  defp compile_scalar_switch(subject_expr, branches, env, counter) do
    cond do
      identity_subject_branches?(subject_expr, branches) ->
        compile_scalar_identity_switch(subject_expr, branches, env, counter)

      true ->
        compile_scalar_switch_branches(subject_expr, branches, env, counter)
    end
  end

  defp compile_scalar_switch_branches(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "native_case_#{next}"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        FunctionCallCompile.reset_call_args_cache!()

        branch_env = RecordCompile.fresh_subexpr_cache(env)

        {expr_code, assignment_code, c2} =
          scalar_branch_assignment(branch.expr, out, branch_env, c)

        snippet = """
        #{case_label(branch.pattern)}:
        #{CSource.indent(expr_code, 4)}
        #{CSource.indent(assignment_code, 4)}
            break;
        """

        {acc <> snippet, c2}
      end)

    code = """
    #{subject_code}
      #{scalar_result_decl(out)}
      switch (#{subject_ref}) {
      #{branch_code}
      }
    """

    {code, out, final_counter}
  end

  defp compile_scalar_identity_switch(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "native_case_#{next}"

    %{expr: else_expr} = Enum.find(branches, &match?(%{pattern: %{kind: :wildcard}}, &1))
    {else_code, else_ref, counter} = NativeInt.compile_expr(else_expr, env, counter)

    case_labels =
      branches
      |> Enum.filter(&match?(%{pattern: %{kind: :int, value: _}}, &1))
      |> Enum.map_join("\n", fn %{pattern: %{kind: :int, value: value}} ->
        "    case #{value}:"
      end)

    code = """
    #{subject_code}
      #{else_code}
      #{scalar_result_decl(out)}
      switch (#{subject_ref}) {
    #{case_labels}
        #{out} = #{subject_ref};
        break;
      default:
        #{out} = #{else_ref};
        break;
      }
    """

    {code, out, counter}
  end

  defp identity_subject_branches?(subject_expr, branches) do
    int_branches = Enum.filter(branches, &match?(%{pattern: %{kind: :int, value: _}}, &1))
    wildcard = Enum.find(branches, &match?(%{pattern: %{kind: :wildcard}}, &1))

    length(int_branches) >= 2 and
      Enum.all?(int_branches, fn %{expr: expr} ->
        subjects_equivalent?(expr, subject_expr)
      end) and
      match?(%{expr: %{op: :int_literal, value: _}}, wildcard)
  end

  defp subjects_equivalent?(
         %{op: :var, name: left},
         %{op: :var, name: right}
       ) do
    EnvBindings.binding_key(left) == EnvBindings.binding_key(right)
  end

  defp subjects_equivalent?(left, right), do: left == right

  defp compile_lookup_table(subject_expr, branches, env, counter) do
    {entries, size} = lookup_table_entries(branches)

  case ConstantInt.literal_value(subject_expr, env) do
      {:ok, subject_value} ->
        {"", Integer.to_string(lookup_table_value(entries, size, subject_value)), counter}

      :error ->
        {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)

        case Integer.parse(subject_ref) do
          {subject_value, ""} ->
            value = lookup_table_value(entries, size, subject_value)

            if subject_code == "" do
              {"", Integer.to_string(value), counter}
            else
              next = counter + 1
              out = "native_case_#{next}"

              code = """
              #{subject_code}
                elmc_int_t #{out} = #{value};
              """

              {code, out, next}
            end

          :error ->
            next = counter + 1
            lut = "native_lut_#{next}"
            out = "native_case_#{next}"
            values = format_lut_initializer(entries)
            index = lookup_table_index(subject_ref, size)

            code = """
            #{subject_code}
              #{lut_array_decl(lut, size, values)}
              elmc_int_t #{out} = #{lut}[#{index}];
            """

            {code, out, next}
        end
    end
  end

  defp lookup_table_value(entries, size, subject_value) when size > 0 do
    index = rem(subject_value, size)
    index = if index < 0, do: index + size, else: index
    Enum.at(entries, index)
  end

  defp lookup_table_eligible?(branches) do
    native_lookup_table_eligible?(branches)
  end

  defp native_lookup_table_eligible?(branches) do
    branches?(branches) and
      Enum.all?(branches, fn %{expr: expr} -> match?(%{op: :int_literal, value: _}, expr) end)
  end

  defp string_lookup_table_eligible?(branches) do
    explicit_int_branches =
      branches
      |> Enum.count(fn
        %{pattern: %{kind: :int, value: _}, expr: %{op: :string_literal, value: value}}
        when is_binary(value) ->
          not String.contains?(value, <<0>>)

        _ ->
          false
      end)

    branches?(branches) and explicit_int_branches >= @min_string_lut_branches and
      Enum.all?(branches, fn %{expr: expr} -> string_literal_branch?(expr) end)
  end

  defp string_literal_branch?(%{op: :string_literal, value: value}) when is_binary(value),
    do: not String.contains?(value, <<0>>)

  defp string_literal_branch?(_expr), do: false

  defp string_lut_entries(branches) do
    default_string =
      branches
      |> Enum.find_value(fn
        %{pattern: %{kind: :wildcard}, expr: %{op: :string_literal, value: value}} -> value
        _ -> nil
      end) || ""

    int_string_map =
      branches
      |> Enum.flat_map(fn
        %{pattern: %{kind: :int, value: key}, expr: %{op: :string_literal, value: value}} ->
          [{key, value}]

        _ ->
          []
      end)
      |> Map.new()

    max_key = int_string_map |> Map.keys() |> Enum.max(fn -> -1 end)

    has_wildcard? =
      Enum.any?(branches, fn %{pattern: pattern} -> match?(%{kind: :wildcard}, pattern) end)

    size =
      cond do
        max_key < 0 and has_wildcard? -> 1
        has_wildcard? -> max_key + 2
        true -> max_key + 1
      end

    entries =
      for index <- 0..(size - 1) do
        Map.get(int_string_map, index, default_string)
      end

    {entries, size, has_wildcard?}
  end

  defp string_lut_index(_subject_ref, 1, _has_wildcard?), do: "0"

  defp string_lut_index(subject_ref, size, true) when size > 1 do
    wildcard_index = size - 1
    "((#{subject_ref}) >= 0 && (#{subject_ref}) < #{wildcard_index}) ? (#{subject_ref}) : #{wildcard_index}"
  end

  defp string_lut_index(subject_ref, size, false) when size > 1 do
    "((#{subject_ref}) >= 0 && (#{subject_ref}) < #{size}) ? (#{subject_ref}) : 0"
  end

  defp string_lut_index_value(_subject_value, 1, _has_wildcard?), do: 0

  defp string_lut_index_value(subject_value, size, true) when size > 1 do
    wildcard_index = size - 1

    if subject_value >= 0 and subject_value < wildcard_index,
      do: subject_value,
      else: wildcard_index
  end

  defp string_lut_index_value(subject_value, size, false) when size > 1 do
    if subject_value >= 0 and subject_value < size, do: subject_value, else: 0
  end

  defp boxed_lookup_table_eligible?(branches, env) do
    branches?(branches) and dense_continuous_keys?(branches) and
      Enum.all?(branches, fn %{expr: expr} ->
        match?({:ok, _}, lookup_table_branch_ref(expr, env))
      end)
  end

  defp lookup_table_branch_ref(expr, env) do
    case normalize_lookup_branch_expr(expr) do
      %{op: :int_literal} = lit ->
        {:ok, IntLiteralRef.ref(lit, env)}

      %{op: :c_int_expr, value: value} when is_binary(value) ->
        {:ok, value}

      _ ->
        :error
    end
  end

  defp normalize_lookup_branch_expr(%{op: :qualified_call, target: target} = expr) do
    args = Map.get(expr, :args, [])

    case Host.special_value_from_target(Host.normalize_special_target(target), args) do
      nil -> expr
      rewritten -> normalize_lookup_branch_expr(rewritten)
    end
  end

  defp normalize_lookup_branch_expr(%{op: :call, name: name, args: args}) when is_binary(name) do
    case Host.special_value_from_target(name, args || []) do
      nil -> %{op: :call, name: name, args: args}
      rewritten -> normalize_lookup_branch_expr(rewritten)
    end
  end

  defp normalize_lookup_branch_expr(expr), do: expr

  defp dense_continuous_keys?(branches) do
    keys =
      branches
      |> Enum.flat_map(fn
        %{pattern: %{kind: :int, value: value}} when is_integer(value) -> [value]
        _ -> []
      end)
      |> Enum.sort()

    keys == Enum.to_list(0..(length(keys) - 1))
  end

  defp lookup_table_boxed_entries(branches) do
    default_expr =
      branches
      |> Enum.find_value(fn branch ->
        case branch do
          %{pattern: %{kind: :wildcard}, expr: expr} -> expr
          _ -> nil
        end
      end)

    int_expr_map =
      branches
      |> Enum.flat_map(fn branch ->
        case branch do
          %{pattern: %{kind: :int, value: key}, expr: expr} -> [{key, expr}]
          _ -> []
        end
      end)
      |> Map.new()

    int_keys = int_expr_map |> Map.keys() |> Enum.sort()
    int_count = length(int_keys)

    has_wildcard? =
      Enum.any?(branches, fn %{pattern: pattern} -> match?(%{kind: :wildcard}, pattern) end)

    max_key = Enum.max(int_keys, fn -> -1 end)

    size =
      cond do
        max_key < 0 and has_wildcard? -> 1
        has_wildcard? -> max_key + 2
        true -> max_key + 1
      end

    entries =
      for index <- 0..(size - 1) do
        Map.get(int_expr_map, index, default_expr)
      end

    {entries, size, int_count, has_wildcard?}
  end

  defp bounded_lookup_index(subject_ref, int_count, has_wildcard?) when has_wildcard? do
    "((#{subject_ref}) >= 0 && (#{subject_ref}) < #{int_count}) ? (#{subject_ref}) : #{int_count}"
  end

  defp bounded_lookup_index(subject_ref, _int_count, false), do: subject_ref

  defp bounded_lookup_index_value(subject_value, int_count, has_wildcard?) when has_wildcard? do
    if subject_value >= 0 and subject_value < int_count, do: subject_value, else: int_count
  end

  defp bounded_lookup_index_value(subject_value, _int_count, false), do: subject_value

  defp lookup_table_entries(branches) do
    default =
      branches
      |> Enum.find_value(fn branch ->
        case branch do
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: value}} ->
            value

          _ ->
            nil
        end
      end)

    int_map =
      branches
      |> Enum.flat_map(fn branch ->
        case branch do
          %{pattern: %{kind: :int, value: key}, expr: %{op: :int_literal, value: value}} ->
            [{key, value}]

          _ ->
            []
        end
      end)
      |> Map.new()

    max_key =
      int_map
      |> Map.keys()
      |> Enum.max(fn -> -1 end)

    has_wildcard? =
      Enum.any?(branches, fn %{pattern: pattern} -> match?(%{kind: :wildcard}, pattern) end)

    size =
      cond do
        max_key < 0 and has_wildcard? -> 1
        has_wildcard? -> max_key + 2
        true -> max_key + 1
      end

    entries = for index <- 0..(size - 1), do: Map.get(int_map, index, default)
    {entries, size}
  end

  defp lookup_table_index(_subject_ref, 1), do: "0"

  defp lookup_table_index(subject_ref, size) do
    "((#{subject_ref}) % #{size} + #{size}) % #{size}"
  end

  defp scalar_branch_assignment(%{op: :int_literal, value: value}, out, _env, counter)
       when is_integer(value) do
    {"", "#{out} = #{value};", counter}
  end

  defp scalar_branch_assignment(expr, out, env, counter) do
    {expr_code, ref, counter} = NativeInt.compile_expr(expr, env, counter)

  assignment =
      if expr_code == "" do
        "#{out} = #{ref};"
      else
        """
        #{String.trim_trailing(expr_code)}
          #{out} = #{ref};
        """
      end

    {"", assignment, counter}
  end

  @spec has_default?(Types.int_case_branches()) :: boolean()
  defp has_default?(branches) do
    Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end)
  end

  @spec boxed_result_decl(String.t(), String.t() | nil) :: String.t()
  defp boxed_result_decl(out, nil), do: "ElmcValue *#{out};"

  defp boxed_result_decl(out, initial_value),
    do: "ElmcValue *#{out} = #{initial_value};"

  @spec scalar_result_decl(String.t()) :: String.t()
  defp scalar_result_decl(out), do: "elmc_int_t #{out};"

  @spec case_label(Types.int_case_pattern()) :: String.t()
  defp case_label(%{kind: :wildcard}), do: "default"

  defp case_label(%{kind: :int, value: value}) when is_integer(value),
    do: "case #{value}"
end
