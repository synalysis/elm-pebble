defmodule Elmc.Backend.CCodegen.Util do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec split_qualified_function_target(String.t()) :: Types.qualified_function_target()
  def split_qualified_function_target(target) when is_binary(target) do
    case String.split(target, ".") do
      [_single] ->
        nil

      parts ->
        {name_parts, [function_name]} = Enum.split(parts, -1)
        {Enum.join(name_parts, "."), function_name}
    end
  end

  @spec module_fn_name(String.t(), String.t()) :: String.t()
  def module_fn_name(module_name, function_name) do
    safe_module = module_name |> String.replace(".", "_")
    safe_function = function_name |> String.replace(".", "_")
    "elmc_fn_#{safe_module}_#{safe_function}"
  end

  @spec qualified_to_c_name(String.t()) :: String.t()
  def qualified_to_c_name(target) when is_binary(target) do
    parts = String.split(target, ".")

    case parts do
      [single] ->
        "elmc_fn_Main_#{single}"

      _ ->
        module_parts = Enum.slice(parts, 0..-2//1)
        func = List.last(parts)
        module_name = Enum.join(module_parts, "_")
        "elmc_fn_#{module_name}_#{func}"
    end
  end

  @spec indent(String.t(), non_neg_integer()) :: String.t()
  def indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.trim(line) == "", do: line, else: pad <> line
    end)
  end

  @spec escape_c_string(String.t()) :: String.t()
  def escape_c_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  @spec escape_c_comment(String.t()) :: String.t()
  def escape_c_comment(value) do
    value
    |> to_string()
    |> String.replace("*/", "* /")
    |> String.replace("\n", " ")
    |> String.replace("\r", " ")
  end

  @spec safe_c_suffix(term()) :: String.t()
  def safe_c_suffix(value) when is_binary(value) do
    String.replace(value, ~r/[^A-Za-z0-9_]/, "_")
  end

  def safe_c_suffix(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> safe_c_suffix()
  end

  def safe_c_suffix(_value), do: "value"

  @spec direct_command_macro(String.t(), String.t()) :: String.t()
  def direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
  end
end
