defmodule Elmc.Backend.C.StubFunctions do
  @moduledoc false

  @fn_name_pattern "elmc_fn_[A-Za-z0-9_]+"
  @return_type_pattern "(?:RC|ElmcValue\\s*\\*|elmc_int_t|bool)"

  @type stub_info :: %{
          name: String.t(),
          abi: :rc | :value | :argv,
          arity: non_neg_integer()
        }

  @doc """
  Scan generated C chunks for referenced `elmc_fn_*` callees that lack a definition.

  `impl_chunks` should contain emitted function/lambda bodies; `decl_chunks` may
  contain forward prototypes already present in the translation unit.
  """
  @spec missing_callee_stubs([String.t() | iodata()], [String.t() | iodata()]) :: %{
          prototypes: String.t(),
          definitions: String.t()
        }
  def missing_callee_stubs(impl_chunks, decl_chunks \\ []) when is_list(impl_chunks) do
    impl_source = impl_chunks |> IO.iodata_to_binary()
    decl_source = decl_chunks |> IO.iodata_to_binary()

    defined = collect_defined_names(impl_source)
    declared = collect_declared_prototypes(impl_source <> decl_source)
    declared_sigs = collect_declared_signatures(impl_source <> decl_source)
    call_map = collect_call_sites(impl_source)

    stubs =
      call_map
      |> Map.keys()
      |> Enum.filter(&kernel_fn_stub?/1)
      |> Enum.reject(&MapSet.member?(defined, &1))
      |> Enum.reject(&(Map.get(declared_sigs, &1, %{})[:abi] == :native))
      |> Enum.map(fn name ->
        call_map
        |> Map.fetch!(name)
        |> merge_declared_signature(Map.get(declared_sigs, name))
      end)
      |> Enum.sort_by(& &1.name)

    %{
      prototypes: emit_prototypes(stubs, declared),
      definitions: emit_definitions(stubs, declared)
    }
  end

  defp collect_declared_prototypes(source) when is_binary(source) do
    proto_re =
      ~r/(?:^|\n)\s*(?:static\s+)?#{@return_type_pattern}\s*(#{@fn_name_pattern})\s*\([^;{]*\)\s*;/m

    proto_re
    |> Regex.scan(source)
    |> Enum.map(fn [_, name] -> name end)
    |> MapSet.new()
  end

  defp collect_declared_signatures(source) when is_binary(source) do
    proto_re =
      ~r/(?:^|\n)\s*(?:static\s+)?(#{@return_type_pattern})\s*(#{@fn_name_pattern})\s*\(([^;{]*)\)\s*;/m

    proto_re
    |> Regex.scan(source)
    |> Enum.map(fn [_, ret, name, params] ->
      {name, declared_signature(ret, params)}
    end)
    |> Map.new()
  end

  defp declared_signature(ret, params) do
    abi =
      case ret do
        "RC" -> :rc
        "elmc_int_t" -> :native
        "bool" -> :native
        _ -> :value
      end

    %{abi: abi, arity: declared_arity(abi, params)}
  end

  defp declared_arity(:native, _), do: 0

  defp declared_arity(:rc, params) do
    params
    |> split_call_args()
    |> case do
      [] -> 0
      [_out | rest] -> length(rest)
    end
  end

  defp declared_arity(:value, params) do
    params = String.trim(params)

    if params == "void" or params == "" do
      0
    else
      params |> split_call_args() |> length()
    end
  end

  defp kernel_fn_stub?(<<"elmc_fn_Elm_Kernel_", _::binary>>), do: true
  defp kernel_fn_stub?(_), do: false

  defp merge_declared_signature(call_info, nil), do: call_info

  defp merge_declared_signature(call_info, %{abi: :native}), do: call_info

  defp merge_declared_signature(call_info, declared) do
    %{
      call_info
      | abi: pick_abi(call_info.abi, declared.abi),
        arity: max(call_info.arity, declared.arity)
    }
  end

  defp collect_defined_names(source) when is_binary(source) do
    def_re =
      ~r/(?:^|\n)\s*(?:static\s+)?#{@return_type_pattern}\s*(#{@fn_name_pattern})\s*\(/m

    def_re
    |> Regex.scan(source)
    |> Enum.map(fn [_, name] -> name end)
    |> MapSet.new()
  end

  defp collect_call_sites(source) when is_binary(source) do
    call_re = ~r/(#{@fn_name_pattern})\s*\(/

    Regex.scan(call_re, source, return: :index)
    |> Enum.reduce(%{}, fn
      [{match_start, match_len}, {name_start, name_len}], acc ->
        name = String.slice(source, name_start, name_len)
        open_paren = match_start + match_len - 1
        {args_str, close_paren} = read_paren_args(source, open_paren)

        if prototype_declaration?(source, name_start, close_paren) do
          acc
        else
          info =
            acc
            |> Map.get(name, %{name: name, abi: :value, arity: 0})
            |> merge_call_site(source, name_start, args_str)

          Map.put(acc, name, info)
        end

      [{match_start, match_len}], acc ->
        full = String.slice(source, match_start, match_len)
        name = full |> String.trim_trailing("(") |> String.trim()
        open_paren = match_start + byte_size(full) - 1
        {args_str, close_paren} = read_paren_args(source, open_paren)

        if prototype_declaration?(source, name_start_for_name(source, name, match_start), close_paren) do
          acc
        else
          info =
            acc
            |> Map.get(name, %{name: name, abi: :value, arity: 0})
            |> merge_call_site(source, name_start_for_name(source, name, match_start), args_str)

          Map.put(acc, name, info)
        end

      _, acc ->
        acc
    end)
  end

  defp prototype_declaration?(source, name_start, close_paren) when is_integer(close_paren) do
    after_close =
      source
      |> String.slice(close_paren + 1, 32)
      |> String.trim_leading()

    # Must early-return: a bare `if …, do: false` does not exit the function.
    if not String.starts_with?(after_close, ";") do
      false
    else
      source
      |> line_prefix_at(name_start)
      |> String.trim()
      |> then(fn line_prefix ->
        Regex.match?(~r/^(?:static\s+)?(?:RC|ElmcValue\s*\*|elmc_int_t|bool)$/u, line_prefix)
      end)
    end
  end

  defp name_start_for_name(source, name, fallback) do
    case :binary.match(source, name) do
      {pos, _} -> pos
      :nomatch -> fallback
    end
  end

  defp merge_call_site(existing, source, name_start, args_str) do
    abi = infer_abi(source, name_start, args_str)
    arity = infer_arity(abi, args_str)

    %{
      name: existing.name,
      abi: pick_abi(existing.abi, abi),
      arity: max(existing.arity, arity)
    }
  end

  defp pick_abi(:argv, _), do: :argv
  defp pick_abi(_, :argv), do: :argv
  defp pick_abi(:rc, _), do: :rc
  defp pick_abi(_, :rc), do: :rc
  defp pick_abi(:value, _), do: :value
  defp pick_abi(_, :value), do: :value

  defp infer_abi(source, name_start, args_str) do
    line_prefix = line_prefix_at(source, name_start)

    cond do
      argv_call?(args_str) ->
        :argv

      String.contains?(line_prefix, "Rc = ") or String.contains?(line_prefix, "RC __call_rc = ") ->
        :rc

      true ->
        :value
    end
  end

  # O(line length): walk back to the previous newline. Avoid slicing+splitting the
  # whole file prefix on every call site (quadratic on large generated C).
  defp line_prefix_at(source, pos) when is_integer(pos) and pos >= 0 do
    size = byte_size(source)
    pos = min(pos, size)
    line_start = line_start_before(source, pos - 1)
    binary_part(source, line_start, pos - line_start)
  end

  defp line_start_before(_source, idx) when idx < 0, do: 0

  defp line_start_before(source, idx) do
    if :binary.at(source, idx) == ?\n do
      idx + 1
    else
      line_start_before(source, idx - 1)
    end
  end

  defp argv_call?(args_str) do
    case split_call_args(args_str) do
      [_args, argc] ->
        String.match?(String.trim(argc), ~r/^(?:argc|\d+)$/)

      _ ->
        false
    end
  end

  defp infer_arity(:argv, _args_str), do: 0

  defp infer_arity(:rc, args_str) do
    args_str
    |> split_call_args()
    |> case do
      [] -> 0
      [_out | rest] -> length(rest)
    end
  end

  defp infer_arity(:value, args_str) do
    args_str |> split_call_args() |> length()
  end

  defp read_paren_args(source, open_paren) when is_integer(open_paren) do
    case binary_part(source, open_paren, 1) do
      "(" ->
        rest_start = open_paren + 1
        <<_::binary-size(^rest_start), rest::binary>> = source
        {content_len, close_in_rest} = scan_paren_content(rest, 1, 0, 0)
        {binary_part(rest, 0, content_len), rest_start + close_in_rest}

      _ ->
        {"", open_paren}
    end
  end

  defp scan_paren_content(<<>>, _depth, content_len, close_pos),
    do: {content_len, close_pos}

  defp scan_paren_content(<<?(, rest::binary>>, depth, content_len, pos) do
    scan_paren_content(rest, depth + 1, content_len + 1, pos + 1)
  end

  defp scan_paren_content(<<?), _rest::binary>>, 1, content_len, pos) do
    {content_len, pos}
  end

  defp scan_paren_content(<<?), rest::binary>>, depth, content_len, pos) when depth > 1 do
    scan_paren_content(rest, depth - 1, content_len + 1, pos + 1)
  end

  defp scan_paren_content(<<_char, rest::binary>>, depth, content_len, pos) do
    scan_paren_content(rest, depth, content_len + 1, pos + 1)
  end

  defp split_call_args(args_str) when args_str in ["", nil], do: []

  defp split_call_args(args_str) when is_binary(args_str) do
    args_str
    |> String.to_charlist()
    |> split_args_charlist(0, [], [], 0)
    |> Enum.reverse()
    |> Enum.map(&IO.iodata_to_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_args_charlist([], _depth, cur, acc, _paren) do
    case Enum.reverse(cur) do
      [] -> Enum.reverse(acc)
      arg -> Enum.reverse([arg | acc])
    end
  end

  defp split_args_charlist([?( | rest], depth, cur, acc, _paren),
    do: split_args_charlist(rest, depth + 1, [?( | cur], acc, 0)

  defp split_args_charlist([?) | rest], depth, cur, acc, _paren) when depth > 0,
    do: split_args_charlist(rest, depth - 1, [?) | cur], acc, 0)

  defp split_args_charlist([?, | rest], 0, cur, acc, _paren),
    do: split_args_charlist(rest, 0, [], [Enum.reverse(cur) | acc], 0)

  defp split_args_charlist([h | rest], depth, cur, acc, _paren),
    do: split_args_charlist(rest, depth, [h | cur], acc, 0)

  defp emit_prototypes(stubs, declared) when is_list(stubs) do
    stubs
    |> Enum.reject(&MapSet.member?(declared, &1.name))
    |> Enum.map(&prototype/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp emit_definitions(stubs, declared) when is_list(stubs) do
    stubs
    |> Enum.map(&definition(&1, declared))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # Prototypes and definitions must share linkage. Prefer `static` for stubs we own;
  # if a non-static forward decl already exists, omit `static` on the definition only.
  defp prototype(%{name: name, abi: :rc, arity: arity}) do
    params = rc_param_list(arity)
    "static RC #{name}(#{params});"
  end

  defp prototype(%{name: name, abi: :argv}) do
    "static ElmcValue *#{name}(ElmcValue ** const args, const int argc);"
  end

  defp prototype(%{name: name, abi: :value, arity: 0}) do
    "static ElmcValue *#{name}(void);"
  end

  defp prototype(%{name: name, abi: :value, arity: arity}) do
    params = value_param_list(arity)
    "static ElmcValue *#{name}(#{params});"
  end

  defp definition(%{name: name, abi: :rc, arity: arity}, declared) do
    params = rc_param_list(arity)
    voids = rc_void_list(arity)
    storage = storage_prefix(name, declared)

    """
    #{storage}RC #{name}(#{params}) {
    #{voids}  return RC_ERR_UNSUPPORTED;
    }
    """
    |> String.trim()
  end

  defp definition(%{name: name, abi: :argv}, declared) do
    storage = storage_prefix(name, declared)

    """
    #{storage}ElmcValue *#{name}(ElmcValue ** const args, const int argc) {
      (void)args;
      (void)argc;
      return NULL;
    }
    """
    |> String.trim()
  end

  defp definition(%{name: name, abi: :value, arity: 0}, declared) do
    storage = storage_prefix(name, declared)

    """
    #{storage}ElmcValue *#{name}(void) {
      return NULL;
    }
    """
    |> String.trim()
  end

  defp definition(%{name: name, abi: :value, arity: arity}, declared) do
    params = value_param_list(arity)
    voids = value_void_list(arity)
    storage = storage_prefix(name, declared)

    """
    #{storage}ElmcValue *#{name}(#{params}) {
    #{voids}  return NULL;
    }
    """
    |> String.trim()
  end

  defp storage_prefix(name, declared) do
    # Pre-existing non-static prototype → non-static definition. Otherwise static
    # (matches the static prototypes we emit for new stubs).
    if MapSet.member?(declared, name), do: "", else: "static "
  end

  defp rc_param_list(arity) do
    elm =
      Enum.map(0..(arity - 1)//1, fn i -> "ElmcValue *arg#{i}" end)
      |> Enum.join(", ")

    if elm == "" do
      "ElmcValue **out"
    else
      "ElmcValue **out, " <> elm
    end
  end

  defp value_param_list(arity) do
    Enum.map(0..(arity - 1)//1, fn i -> "ElmcValue *arg#{i}" end) |> Enum.join(", ")
  end

  defp rc_void_list(arity) do
    lines = ["  (void)out;"] ++ Enum.map(0..(arity - 1)//1, fn i -> "  (void)arg#{i};" end)
    Enum.join(lines, "\n") <> "\n"
  end

  defp value_void_list(arity) do
    Enum.map(0..(arity - 1)//1, fn i -> "  (void)arg#{i};" end)
    |> Enum.join("\n")
    |> case do
      "" -> ""
      body -> body <> "\n"
    end
  end
end
