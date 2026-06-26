defmodule Elmc.Backend.CCodegen.Native.IntCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Types
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
    if boxed_lookup_table_eligible?(branches, env) do
      compile_boxed_lookup_table(subject_expr, branches, env, counter)
    else
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
    next = counter + 1
    out = "tmp_#{next}"
    exhaustive? = has_default?(branches)
    initial_value = if exhaustive?, do: nil, else: "elmc_int_zero()"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        branch_env = RecordCompile.fresh_subexpr_cache(env)

        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, branch_env, c)

        label = case_label(branch.pattern)
        release_previous = if exhaustive?, do: "", else: "elmc_release(#{out});"

        snippet = """
        #{label}:
        #{CSource.indent(expr_code, 4)}
        #{CSource.indent(release_previous, 4)}
        #{CSource.indent(assignment_code, 4)}
            break;
        """

        {acc <> snippet, c2}
      end)

    code = """
    #{subject_code}
      #{boxed_result_decl(out, initial_value)}
      switch (#{subject_ref}) {
      #{branch_code}
      }
    """

    {code, out, final_counter}
  end

  defp compile_boxed_lookup_table(subject_expr, branches, env, counter) do
    {literal_entries, size, int_count, has_wildcard?} = lookup_table_boxed_entries(branches)
    refs =
      Enum.map(literal_entries, fn expr ->
        {:ok, ref} = lookup_table_branch_ref(expr, env)
        ref
      end)
    case_expr = %{op: :case, subject: subject_expr, branches: branches}

    case ConstantInt.literal_value(case_expr, env) do
      {:ok, subject_value} ->
        index = bounded_lookup_index_value(subject_value, int_count, has_wildcard?)
        ref = Enum.at(refs, index)
        next = counter + 1
        out = "tmp_#{next}"

        code =
          """
            ElmcValue *#{out} = NULL;
            #{RcRuntimeEmit.assign_into(env, out, "elmc_new_int", ref)}
          """

        {code, out, next}

      :error ->
        {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
        next = counter + 1
        lut = "native_lut_#{next}"
        scratch = "native_case_#{next}"
        out = "tmp_#{next}"
        values = Enum.join(refs, ", ")
        index = bounded_lookup_index(subject_ref, int_count, has_wildcard?)

        code = """
        #{subject_code}
          static const elmc_int_t #{lut}[#{size}] = { #{values} };
          elmc_int_t #{scratch} = #{lut}[#{index}];
          ElmcValue *#{out} = NULL;
          #{RcRuntimeEmit.assign_into(env, out, "elmc_new_int", scratch)}
        """

        {code, out, next}
    end
  end

  defp compile_scalar_switch(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "native_case_#{next}"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
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
            values = Enum.join(entries, ", ")
            index = lookup_table_index(subject_ref, size)

            code = """
            #{subject_code}
              const elmc_int_t #{lut}[#{size}] = { #{values} };
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
