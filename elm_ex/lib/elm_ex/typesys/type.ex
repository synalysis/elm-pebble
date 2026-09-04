defmodule ElmEx.Typesys.Type do
  @moduledoc """
  Elm 0.19 monotypes used by canonicalize, inference, and IR elaboration.
  """

  @type var_id :: integer()
  @type constraint :: :number | :comparable | :appendable | :compappend

  @type t ::
          {:var, var_id()}
          | {:named, String.t(), [t()]}
          | {:fun, t(), t()}
          | {:tuple, [t()]}
          | {:record, %{String.t() => t()}, t() | nil}
          | {:constrained, constraint(), var_id()}
          | :unit

  @type subst :: %{var_id() => t()}

  @spec var(var_id()) :: t()
  def var(id) when is_integer(id), do: {:var, id}

  @spec named(String.t(), [t()]) :: t()
  def named(name, args \\ []) when is_binary(name) and is_list(args), do: {:named, name, args}

  @spec fun(t(), t()) :: t()
  def fun(from, to), do: {:fun, from, to}

  @spec funs([t()], t()) :: t()
  def funs([], ret), do: ret

  def funs([arg | rest], ret), do: {:fun, arg, funs(rest, ret)}

  @spec tuple([t()]) :: t()
  def tuple([only]), do: only
  def tuple(elems) when is_list(elems), do: {:tuple, elems}

  @spec record(%{String.t() => t()}, t() | nil) :: t()
  def record(fields, ext \\ nil) when is_map(fields), do: {:record, fields, ext}

  @spec constrained(constraint(), var_id()) :: t()
  def constrained(kind, id) when kind in [:number, :comparable, :appendable, :compappend] do
    {:constrained, kind, id}
  end

  @spec int() :: t()
  def int, do: named("Int")

  @spec float() :: t()
  def float, do: named("Float")

  @spec bool() :: t()
  def bool, do: named("Bool")

  @spec string() :: t()
  def string, do: named("String")

  @spec char() :: t()
  def char, do: named("Char")

  @spec list(t()) :: t()
  def list(elem), do: named("List", [elem])

  @spec maybe(t()) :: t()
  def maybe(elem), do: named("Maybe", [elem])

  @spec result(t(), t()) :: t()
  def result(err, ok), do: named("Result", [err, ok])

  @spec cmd(t()) :: t()
  def cmd(msg), do: named("Cmd", [msg])

  @spec sub(t()) :: t()
  def sub(msg), do: named("Sub", [msg])

  @spec never() :: t()
  def never, do: named("Never")

  @spec subst_apply(subst(), t()) :: t()
  def subst_apply(_subst, :unit), do: :unit

  def subst_apply(subst, {:var, id}) do
    case Map.get(subst, id) do
      nil ->
        {:var, id}

      {:var, ^id} ->
        {:var, id}

      other ->
        # Drop `id` while chasing so `{a | …}` / identity bindings cannot loop
        # when `other` still mentions `id` (extensible-record ports/aliases).
        subst_apply(Map.delete(subst, id), other)
    end
  end

  def subst_apply(subst, {:constrained, kind, id}) do
    case Map.get(subst, id) do
      nil ->
        {:constrained, kind, id}

      {:var, ^id} ->
        {:constrained, kind, id}

      {:constrained, _k, ^id} = same ->
        same

      other ->
        subst_apply(Map.delete(subst, id), other)
    end
  end

  def subst_apply(subst, {:named, name, args}), do: {:named, name, Enum.map(args, &subst_apply(subst, &1))}
  def subst_apply(subst, {:fun, a, b}), do: {:fun, subst_apply(subst, a), subst_apply(subst, b)}
  def subst_apply(subst, {:tuple, elems}), do: {:tuple, Enum.map(elems, &subst_apply(subst, &1))}

  def subst_apply(subst, {:record, fields, ext}) do
    {:record, Map.new(fields, fn {k, v} -> {k, subst_apply(subst, v)} end),
     if(ext, do: subst_apply(subst, ext), else: nil)}
  end

  @spec constraints(t()) :: %{var_id() => constraint()}
  def constraints(type), do: do_constraints(type, %{})

  defp do_constraints(:unit, acc), do: acc
  defp do_constraints({:var, _id}, acc), do: acc
  defp do_constraints({:constrained, kind, id}, acc), do: Map.put(acc, id, kind)
  defp do_constraints({:named, _name, args}, acc), do: Enum.reduce(args, acc, &do_constraints/2)
  defp do_constraints({:fun, a, b}, acc), do: do_constraints(b, do_constraints(a, acc))
  defp do_constraints({:tuple, elems}, acc), do: Enum.reduce(elems, acc, &do_constraints/2)

  defp do_constraints({:record, fields, ext}, acc) do
    acc = Enum.reduce(fields, acc, fn {_k, v}, a -> do_constraints(v, a) end)
    if ext, do: do_constraints(ext, acc), else: acc
  end

  @spec free_vars(t()) :: MapSet.t(var_id())
  def free_vars(type), do: type |> do_free_vars(MapSet.new()) 

  defp do_free_vars(:unit, acc), do: acc
  defp do_free_vars({:var, id}, acc), do: MapSet.put(acc, id)
  defp do_free_vars({:constrained, _kind, id}, acc), do: MapSet.put(acc, id)
  defp do_free_vars({:named, _name, args}, acc), do: Enum.reduce(args, acc, &do_free_vars/2)
  defp do_free_vars({:fun, a, b}, acc), do: do_free_vars(b, do_free_vars(a, acc))
  defp do_free_vars({:tuple, elems}, acc), do: Enum.reduce(elems, acc, &do_free_vars/2)

  defp do_free_vars({:record, fields, ext}, acc) do
    acc = Enum.reduce(fields, acc, fn {_k, v}, a -> do_free_vars(v, a) end)
    if ext, do: do_free_vars(ext, acc), else: acc
  end

  @spec occurs?(var_id(), t()) :: boolean()
  def occurs?(id, type), do: MapSet.member?(free_vars(type), id)

  @spec arity(t()) :: non_neg_integer()
  def arity({:fun, _a, b}), do: 1 + arity(b)
  def arity(_), do: 0

  @spec params_and_return(t()) :: {[t()], t()}
  def params_and_return(type), do: params_and_return(type, [])

  defp params_and_return({:fun, a, b}, acc), do: params_and_return(b, [a | acc])
  defp params_and_return(ret, acc), do: {Enum.reverse(acc), ret}

  @spec to_string(t()) :: String.t()
  def to_string(type), do: format(type, :top)

  defp format(:unit, _), do: "()"
  defp format({:var, id}, _), do: "t#{id}"
  defp format({:constrained, kind, id}, _), do: "#{kind}@#{id}"
  defp format({:named, name, []}, _), do: name

  defp format({:named, name, args}, _) do
    name <> " " <> Enum.map_join(args, " ", &format_app/1)
  end

  defp format({:fun, a, b}, :top), do: format_fun_left(a) <> " -> " <> format(b, :top)
  defp format({:fun, a, b}, _), do: "(" <> format({:fun, a, b}, :top) <> ")"
  defp format({:tuple, elems}, _), do: "(" <> Enum.map_join(elems, ", ", &format(&1, :top)) <> ")"

  defp format({:record, fields, ext}, _) do
    field_src =
      fields
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn {k, v} -> "#{k} : #{format(v, :top)}" end)

    case ext do
      nil -> "{" <> field_src <> "}"
      {:var, id} -> "{ t#{id} | #{field_src} }"
      other -> "{ #{format(other, :top)} | #{field_src} }"
    end
  end

  defp format_fun_left({:fun, _, _} = fun), do: "(" <> format(fun, :top) <> ")"
  defp format_fun_left(other), do: format(other, :top)

  defp format_app({:fun, _, _} = fun), do: "(" <> format(fun, :top) <> ")"
  defp format_app({:named, _, [_ | _]} = named), do: "(" <> format(named, :top) <> ")"
  defp format_app(other), do: format(other, :top)

  @spec list_int?(t()) :: boolean()
  def list_int?({:named, "List", [elem]}), do: primitive_kind(elem) == :int
  def list_int?(_), do: false

  @spec list_float?(t()) :: boolean()
  def list_float?({:named, "List", [elem]}), do: primitive_kind(elem) == :float
  def list_float?(_), do: false

  @spec primitive_kind(t()) :: :int | :float | :bool | :char | nil
  def primitive_kind({:named, name, []}) when is_binary(name) do
    case short_named(name) do
      "Int" -> :int
      "Float" -> :float
      "Bool" -> :bool
      "Char" -> :char
      _ -> nil
    end
  end

  def primitive_kind(_), do: nil

  defp short_named("Basics." <> rest), do: rest
  defp short_named(name), do: name

  @spec maybe_payload(t()) :: t() | nil
  def maybe_payload({:named, "Maybe", [elem]}), do: elem
  def maybe_payload(_), do: nil

  @spec native_field?(t()) :: boolean()
  def native_field?(type), do: primitive_kind(type) != nil
end
