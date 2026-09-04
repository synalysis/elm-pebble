defmodule ElmEx.Typesys.Parser do
  @moduledoc """
  Recursive-descent parser for Elm 0.19 type annotations and alias RHS strings.
  """

  alias ElmEx.Typesys.Type

  @type parse_error :: {:error, String.t()}

  @spec parse(String.t()) :: {:ok, Type.t()} | parse_error()
  def parse(source) when is_binary(source) do
    source = String.trim(source)

    if source == "" do
      {:error, "empty type"}
    else
      case parse_fun(source) do
        {:ok, type, rest} ->
          if String.trim(rest) == "" do
            {:ok, elm_extensible_record_identity(type)}
          else
            {:error, "trailing type syntax: #{String.trim(rest)}"}
          end

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  Constructor payloads are a sequence of *atomic* types (`String Int Int`,
  `(List Int) Int`). Juxtaposition is not type application here.
  """
  @spec parse_ctor_args(String.t()) :: {:ok, [Type.t()]} | parse_error()
  def parse_ctor_args(source) when is_binary(source) do
    parse_ctor_arg_list(String.trim(source), [])
  end

  defp parse_ctor_arg_list("", acc), do: {:ok, Enum.reverse(acc)}

  defp parse_ctor_arg_list(source, acc) do
    case parse_atom(source) do
      {:ok, type, rest} ->
        parse_ctor_arg_list(String.trim_leading(rest), [type | acc])

      {:error, _} = err ->
        err
    end
  end

  @spec parse!(String.t()) :: Type.t()
  def parse!(source) do
    case parse(source) do
      {:ok, type} -> type
      {:error, reason} -> raise ArgumentError, "type parse failed: #{reason}"
    end
  end

  defp parse_fun(source) do
    with {:ok, left, rest} <- parse_app(source) do
      rest = String.trim_leading(rest)

      if String.starts_with?(rest, "->") do
        rest = String.trim_leading(String.slice(rest, 2..-1//1))

        with {:ok, right, rest2} <- parse_fun(rest) do
          {:ok, Type.fun(left, right), rest2}
        end
      else
        {:ok, left, rest}
      end
    end
  end

  defp parse_app(source) do
    with {:ok, first, rest} <- parse_atom(source) do
      parse_app_args(first, rest)
    end
  end

  defp parse_app_args(acc, source) do
    rest = String.trim_leading(source)

    cond do
      rest == "" ->
        {:ok, acc, rest}

      String.starts_with?(rest, "->") ->
        {:ok, acc, rest}

      String.starts_with?(rest, ",") or String.starts_with?(rest, ")") or
          String.starts_with?(rest, "}") or String.starts_with?(rest, "|") ->
        {:ok, acc, rest}

      true ->
        case parse_atom(rest) do
          {:ok, arg, rest2} ->
            parse_app_args(apply_named(acc, arg), rest2)

          {:error, _} ->
            {:ok, acc, rest}
        end
    end
  end

  defp apply_named({:named, name, args}, arg), do: {:named, name, args ++ [arg]}
  defp apply_named(other, arg), do: {:named, Type.to_string(other), [arg]}

  defp parse_atom(source) do
    source = String.trim_leading(source)

    cond do
      source == "" ->
        {:error, "expected type"}

      String.starts_with?(source, "()") ->
        {:ok, :unit, String.slice(source, 2..-1//1)}

      String.starts_with?(source, "(") ->
        parse_paren(String.slice(source, 1..-1//1))

      String.starts_with?(source, "{") ->
        parse_record(String.slice(source, 1..-1//1))

      true ->
        parse_name(source)
    end
  end

  defp parse_paren(source) do
    source = String.trim_leading(source)

    with {:ok, first, rest} <- parse_fun(source) do
      rest = String.trim_leading(rest)

      cond do
        String.starts_with?(rest, ")") ->
          {:ok, first, String.slice(rest, 1..-1//1)}

        String.starts_with?(rest, ",") ->
          parse_tuple_elems([first], String.slice(rest, 1..-1//1))

        true ->
          {:error, "expected ',' or ')' in type"}
      end
    end
  end

  defp parse_tuple_elems(acc, source) do
    source = String.trim_leading(source)

    with {:ok, elem, rest} <- parse_fun(source) do
      acc = acc ++ [elem]
      rest = String.trim_leading(rest)

      cond do
        String.starts_with?(rest, ",") ->
          parse_tuple_elems(acc, String.slice(rest, 1..-1//1))

        String.starts_with?(rest, ")") ->
          if length(acc) > 3 do
            {:error, "tuples can only have two or three items"}
          else
            {:ok, Type.tuple(acc), String.slice(rest, 1..-1//1)}
          end

        true ->
          {:error, "expected ',' or ')' in tuple type"}
      end
    end
  end

  defp parse_record(source) do
    source = String.trim_leading(source)

    cond do
      String.starts_with?(source, "}") ->
        {:ok, Type.record(%{}), String.slice(source, 1..-1//1)}

      true ->
        case take_ident(source) do
          {:ok, name, rest} ->
            rest = String.trim_leading(rest)

            cond do
              String.starts_with?(rest, "|") ->
                ext = ext_from_name(name)
                parse_record_fields(%{}, ext, String.trim_leading(String.slice(rest, 1..-1//1)))

              String.starts_with?(rest, ":") ->
                parse_record_field_value(%{}, nil, name, String.trim_leading(String.slice(rest, 1..-1//1)))

              true ->
                {:error, "expected ':' or '|' in record type"}
            end

          :error ->
            {:error, "expected record field"}
        end
    end
  end

  defp ext_from_name(name) do
    if ident_var?(name), do: Type.var(var_id_from_name(name)), else: Type.named(name)
  end

  defp parse_record_field_value(fields, ext, name, source) do
    with {:ok, type, rest} <- parse_fun(source) do
      fields = Map.put(fields, name, type)
      rest = String.trim_leading(rest)

      cond do
        String.starts_with?(rest, ",") ->
          parse_record_fields(fields, ext, String.trim_leading(String.slice(rest, 1..-1//1)))

        String.starts_with?(rest, "}") ->
          {:ok, Type.record(fields, ext), String.slice(rest, 1..-1//1)}

        true ->
          {:error, "expected ',' or '}' in record type"}
      end
    end
  end

  defp parse_record_fields(fields, ext, source) do
    source = String.trim_leading(source)

    cond do
      String.starts_with?(source, "}") ->
        {:ok, Type.record(fields, ext), String.slice(source, 1..-1//1)}

      true ->
        case take_ident(source) do
          {:ok, name, rest} ->
            rest = String.trim_leading(rest)

            if String.starts_with?(rest, ":") do
              parse_record_field_value(
                fields,
                ext,
                name,
                String.trim_leading(String.slice(rest, 1..-1//1))
              )
            else
              {:error, "expected ':' after record field"}
            end

          :error ->
            {:error, "expected record field name"}
        end
    end
  end

  defp parse_name(source) do
    case take_qid(source) do
      {:ok, name, rest} ->
        {:ok, atom_type(name), rest}

      :error ->
        {:error, "expected type name"}
    end
  end

  defp atom_type(name) do
    cond do
      name in ["number"] -> Type.constrained(:number, var_id_from_name(name))
      name in ["comparable"] -> Type.constrained(:comparable, var_id_from_name(name))
      name in ["appendable"] -> Type.constrained(:appendable, var_id_from_name(name))
      name in ["compappend"] -> Type.constrained(:compappend, var_id_from_name(name))
      ident_var?(name) -> Type.var(var_id_from_name(name))
      true -> Type.named(qualify_builtin(name))
    end
  end

  @spec canonicalize_name(String.t()) :: String.t()
  def canonicalize_name(name) when is_binary(name), do: qualify_builtin(name)

  defp qualify_builtin(name) do
    case name do
      "Cmd" -> "Cmd"
      "Sub" -> "Sub"
      "Time.Posix" -> "Posix"
      "Time.Zone" -> "Zone"
      "Time.Month" -> "Month"
      "Time.Weekday" -> "Weekday"
      "Random.Generator" -> "Generator"
      "Random.Seed" -> "Seed"
      "Json.Decode.Decoder" -> "Decoder"
      "Json.Decode.Error" -> "Json.Decode.Error"
      "Json.Encode.Value" -> "Value"
      "Json.Decode.Value" -> "Value"
      "Json.Value" -> "Value"
      "Process.Id" -> "Process.Id"
      "Basics.Float" -> "Float"
      "Basics.Int" -> "Int"
      "Basics.Bool" -> "Bool"
      "Basics.Order" -> "Order"
      "Basics.Never" -> "Never"
      "Basics.String" -> "String"
      "Basics.Char" -> "Char"
      other -> other
    end
  end

  defp take_qid(source) do
    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*)/, source) do
      [full, name] -> {:ok, name, String.slice(source, byte_size(full)..-1//1)}
      _ -> :error
    end
  end

  defp take_ident(source) do
    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_']*)/, source) do
      [full, name] -> {:ok, name, String.slice(source, byte_size(full)..-1//1)}
      _ -> :error
    end
  end

  # Elm `{ a | x : Int } -> a` uses `a` as the whole record type, not the row.
  defp elm_extensible_record_identity(type) do
    subst_extensible_vars(type, collect_extensible_records(type, %{}))
  end

  defp collect_extensible_records({:record, fields, {:var, id} = ext} = rec, acc) do
    acc = Map.put(acc, id, rec)

    Enum.reduce(fields, acc, fn {_k, v}, acc ->
      collect_extensible_records(v, acc)
    end)
    |> then(&collect_extensible_records(ext, &1))
  end

  defp collect_extensible_records({:record, fields, ext}, acc) do
    acc =
      Enum.reduce(fields, acc, fn {_k, v}, acc ->
        collect_extensible_records(v, acc)
      end)

    if ext, do: collect_extensible_records(ext, acc), else: acc
  end

  defp collect_extensible_records({:fun, a, b}, acc) do
    acc = collect_extensible_records(a, acc)
    collect_extensible_records(b, acc)
  end

  defp collect_extensible_records({:tuple, elems}, acc) do
    Enum.reduce(elems, acc, &collect_extensible_records/2)
  end

  defp collect_extensible_records({:named, _n, args}, acc) do
    Enum.reduce(args, acc, &collect_extensible_records/2)
  end

  defp collect_extensible_records(_, acc), do: acc

  defp subst_extensible_vars({:record, fields, ext}, mapping) do
    {:record, Map.new(fields, fn {k, v} -> {k, subst_extensible_vars(v, mapping)} end), ext}
  end

  defp subst_extensible_vars({:fun, a, b}, mapping) do
    {:fun, subst_extensible_vars(a, mapping), subst_extensible_vars(b, mapping)}
  end

  defp subst_extensible_vars({:tuple, elems}, mapping) do
    {:tuple, Enum.map(elems, &subst_extensible_vars(&1, mapping))}
  end

  defp subst_extensible_vars({:named, name, args}, mapping) do
    {:named, name, Enum.map(args, &subst_extensible_vars(&1, mapping))}
  end

  defp subst_extensible_vars({:var, id} = var, mapping), do: Map.get(mapping, id, var)

  defp subst_extensible_vars(other, _mapping), do: other

  defp ident_var?(name), do: String.match?(name, ~r/^[a-z]/)

  # Stable ids for annotation type variables so `a -> a` shares one var.
  defp var_id_from_name(name) do
    :erlang.phash2(name, 1_000_000) + 10_000
  end
end
