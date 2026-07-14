defmodule Elmc.Backend.Wasm.Types do
  @moduledoc false

  @type wat :: iodata()

  @spec sexpr(String.t() | atom(), wat()) :: binary()
  def sexpr(name, body \\ []) do
    name = to_string(name)
    flatten_iodata(["(", name, " ", body, ")"]) |> IO.iodata_to_binary()
  end

  @spec sexpr_open(String.t() | atom(), wat()) :: binary()
  def sexpr_open(name, body \\ []) do
    name = to_string(name)
    flatten_iodata(["(", name, " ", body]) |> IO.iodata_to_binary()
  end

  defp flatten_iodata(list) when is_list(list), do: Enum.flat_map(list, &flatten_iodata/1)
  defp flatten_iodata(bin) when is_binary(bin), do: [bin]
  defp flatten_iodata(int) when is_integer(int), do: [Integer.to_string(int)]
  defp flatten_iodata(atom) when is_atom(atom), do: [Atom.to_string(atom)]
  defp flatten_iodata(float) when is_float(float), do: [:erlang.float_to_binary(float, decimals: 6)]
  defp flatten_iodata(other), do: [inspect(other)]

  @spec line(wat()) :: binary()
  def line(parts) do
    [parts, "\n"] |> IO.iodata_to_binary()
  end

  @spec i32_load_offset(non_neg_integer()) :: binary()
  def i32_load_offset(offset) when is_integer(offset) do
    sexpr("i32.load", [" offset=#{offset}", " ", sexpr("i32.const", [0])])
  end

  @spec indent(binary() | iodata(), non_neg_integer()) :: binary()
  def indent(body, level \\ 1) do
    pad = String.duplicate("  ", level)

    body
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("\n", &"#{pad}#{&1}")
  end

  @spec ident(String.t()) :: String.t()
  def ident(name) when is_binary(name) do
    "$" <> sanitize(name)
  end

  @spec fn_ident(String.t(), String.t()) :: String.t()
  def fn_ident(module, name) do
    ident("elmc_fn_#{module}_#{name}")
  end

  @spec closure_ident(String.t(), String.t(), non_neg_integer()) :: String.t()
  def closure_ident(module, parent_name, idx) when is_integer(idx) do
    ident("elmc_fn_#{module}_#{parent_name}_closure_#{idx}")
  end

  @spec import_ident(String.t()) :: String.t()
  def import_ident(import_name) when is_binary(import_name) do
    suffix =
      case String.split(import_name, ".", parts: 2) do
        ["runtime", rest] -> rest
        [_mod, rest] -> rest
        [single] -> single
      end

    ident("runtime_" <> String.replace(suffix, ".", "_"))
  end

  @spec reg_local(non_neg_integer()) :: String.t()
  def reg_local(reg), do: ident("reg#{reg}")

  @spec sanitize(String.t()) :: String.t()
  defp sanitize(name) do
    name
    |> String.replace(".", "_")
    |> String.replace(~r/[^A-Za-z0-9_]/, "_")
  end
end
