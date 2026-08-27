defmodule Elmc.Backend.C.Ast.Lint do
  @moduledoc """
  Structural RC ABI checks on `C.Ast.RcFn` and generated C text.
  """

  alias Elmc.Backend.C.Ast.RcFn

  @type issue :: {:error, atom(), keyword()}

  @spec run(RcFn.t()) :: :ok | {:error, [issue()]}
  def run(%RcFn{} = rc_fn) do
    issues =
      []
      |> check_single_return(rc_fn)
      |> check_catch_wrap(rc_fn)
      |> check_raw_rc_shape(rc_fn)

    case issues do
      [] -> :ok
      found -> {:error, Enum.reverse(found)}
    end
  end

  @spec run!(RcFn.t()) :: :ok
  def run!(%RcFn{} = rc_fn) do
    case run(rc_fn) do
      :ok ->
        :ok

      {:error, issues} ->
        raise "C.Ast.Lint failed: #{inspect(issues)}"
    end
  end

  @spec run_source(String.t()) :: :ok | {:error, [issue()]}
  def run_source(source) when is_binary(source) do
    issues =
      rc_fn_bodies(source)
      |> Enum.flat_map(&lint_rc_body/1)

    case issues do
      [] -> :ok
      found -> {:error, found}
    end
  end

  @spec run_source!(String.t()) :: :ok
  def run_source!(source) when is_binary(source) do
    case run_source(source) do
      :ok ->
        :ok

      {:error, issues} ->
        raise "generated C RC-shape lint failed: #{inspect(issues, pretty: true)}"
    end
  end

  defp check_single_return(issues, %RcFn{rc?: false}), do: issues

  defp check_single_return(issues, %RcFn{stmts: stmts}) do
    returns = Enum.count(stmts, &(&1 == {:return_rc}))

    if returns == 1 do
      issues
    else
      [{:error, :rc_return_count, [count: returns]} | issues]
    end
  end

  defp check_catch_wrap(issues, %RcFn{needs_catch: false}), do: issues

  defp check_catch_wrap(issues, %RcFn{stmts: stmts}) do
    has_begin? = {:catch_begin} in stmts
    has_end? = {:catch_end} in stmts

    if has_begin? and has_end? do
      issues
    else
      [{:error, :missing_catch_wrap, []} | issues]
    end
  end

  defp check_raw_rc_shape(issues, %RcFn{rc?: false}), do: issues

  defp check_raw_rc_shape(issues, %RcFn{stmts: stmts}) do
    raw =
      stmts
      |> Enum.filter(&match?({:raw, _}, &1))
      |> Enum.map_join("\n", fn {:raw, t} -> t end)

    issues
    |> reject_take(raw)
    |> reject_early_return(raw)
  end

  defp lint_rc_body({name, body}) do
    []
    |> then(fn issues ->
      returns = Regex.scan(~r/\breturn\s+Rc\s*;/, body) |> length()

      if returns == 1 do
        issues
      else
        [{:error, :rc_return_count, [fn: name, count: returns]} | issues]
      end
    end)
    |> reject_take(body, name)
    |> reject_early_return(body, name)
    |> then(fn issues ->
      if String.contains?(body, "CHECK_RC(") and not String.contains?(body, "CATCH_BEGIN") do
        [{:error, :check_rc_outside_catch, [fn: name]} | issues]
      else
        issues
      end
    end)
  end

  defp reject_take(issues, text, name \\ nil) do
    if Regex.match?(~r/\b(?:elmc_new_\w+_take|elmc_\w+_take_value)\s*\(/, text) do
      [{:error, :rc_take_shim, [fn: name]} | issues]
    else
      issues
    end
  end

  defp reject_early_return(issues, text, name \\ nil) do
    if Regex.match?(~r/\breturn\s+RC_ERR_/, text) do
      [{:error, :early_rc_err_return, [fn: name]} | issues]
    else
      issues
    end
  end

  @spec rc_fn_bodies(String.t()) :: [{String.t(), String.t()}]
  def rc_fn_bodies(source) when is_binary(source) do
    ~r/(?:static\s+)?RC\s+(elmc_fn_[A-Za-z0-9_]+)\s*\([^;{]*\)\s*\{/
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn
      [{start, len} | _] ->
        name =
          source
          |> binary_part(start, len)
          |> then(fn frag ->
            case Regex.run(~r/elmc_fn_[A-Za-z0-9_]+/, frag) do
              [n] -> n
              _ -> "unknown"
            end
          end)

        open = start + len
        close = matching_brace(source, open)
        body = binary_part(source, open, max(close - open, 0))
        {name, body}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp matching_brace(source, open_idx) do
    size = byte_size(source)
    find_close(source, open_idx, size, 1)
  end

  defp find_close(_source, idx, size, _depth) when idx >= size, do: size

  defp find_close(source, idx, size, depth) do
    case :binary.at(source, idx) do
      ?{ -> find_close(source, idx + 1, size, depth + 1)
      ?} when depth == 1 -> idx
      ?} -> find_close(source, idx + 1, size, depth - 1)
      _ -> find_close(source, idx + 1, size, depth)
    end
  end
end
