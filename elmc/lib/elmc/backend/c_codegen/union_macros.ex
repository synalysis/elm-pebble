defmodule Elmc.Backend.CCodegen.UnionMacros do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type macro_map :: %{optional(String.t()) => String.t()}

  @spec definitions(IR.t(), keyword()) :: {String.t(), macro_map()}
  def definitions(%IR{} = ir, opts \\ []) do
    used = Keyword.get(opts, :used_union_ctors)

    qualified_entries =
      Enum.flat_map(ir.modules, fn mod ->
        mod.unions
        |> Map.values()
        |> Enum.flat_map(fn union ->
          union.tags
          |> Enum.map(fn {name, tag} ->
            qualified = "#{mod.name}.#{name}"
            {qualified, macro_name(qualified), tag}
          end)
        end)
      end)

    unqualified_entries =
      qualified_entries
      |> Enum.group_by(fn {qualified, _macro, _tag} ->
        qualified |> String.split(".") |> List.last()
      end)
      |> Enum.flat_map(fn
        {name, [{_qualified, _macro, tag}]} -> [{name, macro_name(name), tag}]
        {_name, _duplicates} -> []
      end)

    entries =
      (qualified_entries ++ unqualified_entries)
      |> Enum.sort_by(fn {name, _macro, _tag} -> name end)
      |> maybe_filter_used_ctors(used)

    defines =
      entries
      |> Enum.map_join("\n", fn {_name, macro, tag} -> "#define #{macro} #{tag}" end)

    macro_map =
      entries
      |> Map.new(fn {name, macro, _tag} -> {name, macro} end)

    {defines, macro_map}
  end

  defp maybe_filter_used_ctors(entries, %MapSet{} = used) do
    Enum.filter(entries, fn {name, _macro, _tag} -> union_ctor_used?(name, used) end)
  end

  defp maybe_filter_used_ctors(entries, _), do: entries

  defp union_ctor_used?(name, used) do
    short = short_union_ctor_name(name)

    MapSet.member?(used, name) or
      MapSet.member?(used, short) or
      Enum.any?(used, fn entry ->
        entry == short or String.ends_with?(entry, "." <> short)
      end)
  end

  defp short_union_ctor_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  @spec literal_ref(Types.ir_expr(), Types.compile_env() | nil) :: String.t() | nil
  def literal_ref(expr, env \\ nil)

  def literal_ref(%{op: :int_literal, value: value, union_ctor: ctor} = expr, env)
      when is_integer(value) and is_binary(ctor) do
    if ResourceUnion.int_literal_value(expr) == value do
      macros = Process.get(:elmc_union_constructor_macros, %{})

      Map.get(macros, ctor) ||
        qualified_literal_ref(macros, ctor, env)
    end
  end

  def literal_ref(_expr, _env), do: nil

  defp qualified_literal_ref(macros, ctor, env) when is_map(env) and is_binary(ctor) do
    module_name = Map.get(env, :__module__)

    if is_binary(module_name) and not String.contains?(ctor, ".") do
      Map.get(macros, "#{module_name}.#{ctor}")
    end
  end

  defp qualified_literal_ref(_macros, _ctor, _env), do: nil

  defp macro_name(ctor) do
    suffix =
      ctor
      |> Util.safe_c_suffix()
      |> String.upcase()

    "ELMC_UNION_#{suffix}"
  end
end
