defmodule Elmc.Test.CCodegenExtract do
  @moduledoc false

  @return_type "(?:RC|ElmcValue\\s*\\*+\\s*|elmc_int_t|const char\\s*\\*|void|int|bool)"
  @next_fn ~r/\n(?:static )?(?:RC|ElmcValue\s*\*+\s*|elmc_int_t|const char\s*\*|void|int|bool)\s*elmc_fn_/

  @doc "Return `body` up to (but not including) the next generated function definition."
  @spec before_next_fn(String.t()) :: String.t()
  def before_next_fn(body) when is_binary(body) do
    case Regex.split(@next_fn, body, parts: 2) do
      [head, _] -> head
      [head] -> head
    end
  end

  @doc "Extract the braced body of `name` or `name_native` when a dual-ABI wrapper exists."
  @spec fn_impl_body(String.t(), String.t()) :: String.t()
  def fn_impl_body(source, name) when is_binary(source) and is_binary(name) do
    native_name = if String.ends_with?(name, "_native"), do: name, else: name <> "_native"
    native_body = fn_body(source, native_name)

    if native_body != "" do
      native_body
    else
      fn_body(source, name)
    end
  end

  @doc "Extract the braced body of a generated `elmc_fn_*` definition."
  @spec fn_body(String.t(), String.t()) :: String.t()
  def fn_body(source, name) when is_binary(source) and is_binary(name) do
    pattern =
      Regex.compile!(
        "(?:static\\s+)?#{@return_type}\\s*#{Regex.escape(name)}\\s*\\((?:const\\s+)?[^;{]*\\)\\s*\\{"
      )

    matches =
      source
      |> then(&Regex.scan(pattern, &1, return: :index))
      |> Enum.map(fn
        [{start, len}] -> {start, len}
        {start, len} -> {start, len}
      end)

    case List.last(matches) do
      {start, len} ->
        open_idx = start + len - 1

        case find_matching_brace(source, open_idx) do
          {:ok, end_idx} -> binary_part(source, open_idx + 1, end_idx - open_idx - 1)
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp find_matching_brace(source, open_idx) do
    do_find_matching_brace(source, open_idx + 1, byte_size(source), 1)
  end

  defp do_find_matching_brace(_source, idx, size, _depth) when idx >= size,
    do: {:error, :unbalanced}

  defp do_find_matching_brace(source, idx, size, depth) do
    case :binary.at(source, idx) do
      ?{ ->
        do_find_matching_brace(source, idx + 1, size, depth + 1)

      ?} when depth == 1 ->
        {:ok, idx}

      ?} when depth > 1 ->
        do_find_matching_brace(source, idx + 1, size, depth - 1)

      _ ->
        do_find_matching_brace(source, idx + 1, size, depth)
    end
  end
end
