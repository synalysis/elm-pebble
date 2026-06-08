defmodule Elmc.Backend.CCodegen.Native.IntCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstantInt
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
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
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"
    exhaustive? = has_default?(branches)
    initial_value = if exhaustive?, do: nil, else: "elmc_int_zero()"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, env, c)

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

  defp compile_scalar_switch(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "native_case_#{next}"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        {expr_code, assignment_code, c2} =
          scalar_branch_assignment(branch.expr, out, env, c)

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
    branches?(branches) and
      Enum.all?(branches, fn %{expr: expr} -> match?(%{op: :int_literal, value: _}, expr) end)
  end

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
