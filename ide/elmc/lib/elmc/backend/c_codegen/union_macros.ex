defmodule Elmc.Backend.CCodegen.UnionMacros do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.ProdMode
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

  @spec debug_ctor_name_fn(IR.t(), keyword()) :: String.t()
  def debug_ctor_name_fn(%IR{} = ir, opts \\ []) do
    if ProdMode.enabled?() or prod_from_opts?(opts) do
      debug_ctor_name_stub()
    else
      debug_ctor_name_fn_impl(ir, opts)
    end
  end

  defp debug_ctor_name_stub do
    """
    const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
      (void)tag;
      return NULL;
    }
    """
  end

  defp debug_ctor_name_fn_impl(%IR{} = ir, opts) do
    used = Keyword.get(opts, :used_union_ctors)
    entry_module = Keyword.get(opts, :entry_module)

    entries =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.unions
        |> Map.values()
        |> Enum.flat_map(fn union ->
          tags = union.tags || %{}
          single_ctor? = map_size(tags) == 1

          Enum.map(tags, fn {name, tag} ->
            %{
              name: short_union_ctor_name(name),
              tag: tag,
              module: mod.name,
              single_ctor?: single_ctor?
            }
          end)
        end)
      end)
      |> maybe_filter_debug_entry_maps(used)

    unique_by_tag =
      entries
      |> Enum.group_by(& &1.tag)
      |> Enum.flat_map(fn {tag, group} ->
        case pick_debug_ctor_name(group, entry_module) do
          name when is_binary(name) -> [{tag, name}]
          _ -> []
        end
      end)
      |> Enum.sort_by(fn {tag, _name} -> tag end)

    cases =
      unique_by_tag
      |> Enum.map_join("\n", fn {tag, name} ->
        "    case #{tag}: return \"#{escape_c_string(name)}\";"
      end)

    """
    const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
      switch (tag) {
    #{cases}
        default: return NULL;
      }
    }
    """
  end

  # Core packages reuse small tag integers for unrelated single-ctor wrappers
  # (Cmd/Sub/Value/…). Prefer constructors from non-stdlib modules so app types
  # like ActionConfig win Debug.toString over those opaque wrappers.
  @stdlib_modules MapSet.new(~w(
    Array Basics Bitwise Bytes Char Dict Debug Elm.JsArray Elm.Kernel.Basics
    Elm.Kernel.Bitwise Elm.Kernel.Char Elm.Kernel.Debug Elm.Kernel.Json
    Elm.Kernel.List Elm.Kernel.Parser Elm.Kernel.Platform Elm.Kernel.Process
    Elm.Kernel.Scheduler Elm.Kernel.String Elm.Kernel.Utils Json.Decode
    Json.Encode List Maybe Platform Platform.Cmd Platform.Sub Process Result
    Set String Task Time Tuple VirtualDom
  ))

  defp pick_debug_ctor_name([%{name: name}], _entry_module), do: name

  defp pick_debug_ctor_name(group, entry_module) when is_list(group) do
    singles = Enum.filter(group, & &1.single_ctor?)

    entry_singles =
      if is_binary(entry_module) do
        Enum.filter(singles, &(&1.module == entry_module))
      else
        []
      end

    app_singles =
      Enum.filter(singles, fn %{module: mod} ->
        not MapSet.member?(@stdlib_modules, mod)
      end)

    entry_ctors =
      if is_binary(entry_module) do
        Enum.filter(group, &(&1.module == entry_module))
      else
        []
      end

    # Multi-ctor app unions (e.g. Opcode.Char) share small tag ints with stdlib
    # (Order.GT, Json.Decode.OneOf). Prefer a unique non-stdlib / entry ctor so
    # Debug.toString prints `Char 'a'` instead of `(3,'a')`.
    app_ctors =
      Enum.filter(group, fn %{module: mod} ->
        not MapSet.member?(@stdlib_modules, mod)
      end)

    cond do
      match?([%{name: _}], entry_singles) -> hd(entry_singles).name
      match?([%{name: _}], app_singles) -> hd(app_singles).name
      match?([%{name: _}], singles) -> hd(singles).name
      match?([%{name: _}], entry_ctors) -> hd(entry_ctors).name
      match?([%{name: _}], app_ctors) -> hd(app_ctors).name
      true -> nil
    end
  end

  defp maybe_filter_debug_entry_maps(entries, %MapSet{} = used) do
    Enum.filter(entries, fn %{name: name} ->
      MapSet.member?(used, name) or
        Enum.any?(used, fn entry ->
          entry == name or String.ends_with?(entry, "." <> name)
        end)
    end)
  end

  defp maybe_filter_debug_entry_maps(entries, _), do: entries

  defp escape_c_string(name) when is_binary(name) do
    name |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
  end

  defp prod_from_opts?(opts) when is_list(opts) do
    case Keyword.get(opts, :prod) do
      true -> true
      false -> false
      _ -> ProdMode.enabled?()
    end
  end
end
