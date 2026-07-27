defmodule Elmc.TestSupport.BytecodeDisasm do
  @moduledoc false

  alias Elmc.Backend.Bytecode.Opcodes

  @spec walk(binary(), non_neg_integer(), non_neg_integer()) :: :ok
  def walk(code, ip \\ 0, limit \\ 200) do
    walk_loop(code, ip, limit, 0)
  end

  defp walk_loop(_code, ip, _limit, _n) when ip < 0, do: :ok

  defp walk_loop(code, ip, limit, n) when n < limit and ip < byte_size(code) do
    <<op::8, dest::16, rest::binary>> = binary_part(code, ip, byte_size(code) - ip)
    name = Opcodes.name(op) || :unknown

    case insn_size(name, rest) do
      {:ret, size} ->
        IO.puts("@#{ip} #{name} dest=#{dest} +#{size} RET")
        :ok

      {:ok, size, info} ->
        IO.puts("@#{ip} #{name} dest=#{dest} +#{size} #{info}")
        walk_loop(code, ip + 3 + size, limit, n + 1)

      {:error, reason} ->
        IO.puts("@#{ip} #{name} dest=#{dest} ERROR #{reason}")
        :error
    end
  end

  defp walk_loop(_, _, _, _), do: :ok

  defp insn_size(:const_int, _rest), do: {:ok, 4, ""}

  defp insn_size(:load_param, _rest), do: {:ok, 2, ""}
  defp insn_size(:load_local, _rest), do: {:ok, 2, ""}

  defp insn_size(:const_immortal_string, <<size::16, _rest::binary>>) do
    {:ok, 2 + size, "len=#{size}"}
  end

  defp insn_size(:const_immortal_string, _rest), do: {:error, "const_immortal_string truncated"}

  defp insn_size(:const_static_list, <<kind::8, count::16, _rest::binary>>) do
    size =
      3 +
        case kind do
          0 -> count * 4
          1 -> count * 8
          2 -> count * 8
          k when k in [3, 4] -> count * 2
          _ -> 0
        end

    {:ok, size, "kind=#{kind} count=#{count}"}
  end

  defp insn_size(:const_static_list, _rest), do: {:error, "const_static_list truncated"}

  defp insn_size(:int_arith, <<kind::8, _::binary>>) do
    size = if kind in [0, 1], do: 5, else: 4
    {:ok, size, "kind=#{kind}"}
  end

  defp insn_size(:call_runtime, <<_id::16, lit::8, rest::binary>>) do
    lit_extra = if lit == 1, do: 4, else: 0

    case rest do
      <<args_size::16, _args::binary-size(args_size), _::binary>> ->
        {:ok, 2 + 1 + 2 + args_size + lit_extra, "args=#{args_size}"}

      _ ->
        {:error, "call_runtime truncated"}
    end
  end

  defp insn_size(:call_fn, <<_idx::16, args_size::16, rest::binary>>) do
    if byte_size(rest) >= args_size do
      {:ok, 2 + args_size, "args=#{args_size}"}
    else
      {:error, "call_fn truncated"}
    end
  end

  defp insn_size(:compare, _rest), do: {:ok, 5, ""}
  defp insn_size(:phi, _rest), do: {:ok, 6, ""}
  defp insn_size(:test_maybe_nothing, _rest), do: {:ok, 2, ""}

  defp insn_size(:switch_ctor_tag, <<_::16, _::16, arms_size::16, rest::binary>>) do
    if byte_size(rest) >= arms_size do
      {:ok, 4 + arms_size, "arms=#{arms_size}"}
    else
      {:error, "switch_ctor_tag truncated"}
    end
  end

  defp insn_size(:tuple_proj, _rest), do: {:ok, 3, ""}
  defp insn_size(:record_get, _rest), do: {:ok, 4, ""}
  defp insn_size(:record_update, _rest), do: {:ok, 6, ""}
  defp insn_size(:release, _rest), do: {:ok, 2, ""}
  defp insn_size(:catch_begin, _rest), do: {:ok, 0, ""}
  defp insn_size(:catch_end, _rest), do: {:ok, 0, ""}
  defp insn_size(:publish, _rest), do: {:ok, 2, ""}
  defp insn_size(:ret, _rest), do: {:ret, 0}
  defp insn_size(:br, _rest), do: {:ok, 2, "br"}

  defp insn_size(:switch_tag, <<_default::16, arms_size::16, rest::binary>>) do
    if byte_size(rest) >= arms_size do
      {:ok, 4 + arms_size, "arms=#{arms_size}"}
    else
      {:error, "switch_tag truncated"}
    end
  end

  defp insn_size(:br_if, _rest), do: {:ok, 4, "br_if"}
  defp insn_size(name, _rest), do: {:ok, 0, "unknown=#{name}"}
end
