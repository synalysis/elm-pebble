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
    safe_module = module_name |> String.replace(".", "_") |> safe_c_suffix()
    safe_function = function_name |> String.replace(".", "_") |> safe_c_suffix()
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

  @spec escape_c_string(String.t()) :: String.t()
  def escape_c_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace("\0", "\\0")
  end

  @spec string_literal_c_expr(String.t()) :: String.t()
  def string_literal_c_expr(value) when is_binary(value) do
    escaped = escape_c_string(value)

    if String.contains?(value, <<0>>) do
      "elmc_new_string_len_take(\"#{escaped}\", #{byte_size(value)})"
    else
      "elmc_new_string_take(\"#{escaped}\")"
    end
  end

  @spec parse_compile_time_int_ref(String.t()) :: integer() | nil
  def parse_compile_time_int_ref(ref) when is_binary(ref) do
    ref
    |> String.split("/*", parts: 2)
    |> List.first()
    |> String.trim()
    |> case do
      "" ->
        nil

      digits ->
        case Integer.parse(digits) do
          {value, ""} -> value
          _ -> nil
        end
    end
  end

  def parse_compile_time_int_ref(_ref), do: nil

  @spec escape_c_comment(String.t()) :: String.t()
  def escape_c_comment(value) do
    value
    |> to_string()
    |> String.replace("*/", "* /")
    |> String.replace("\n", " ")
    |> String.replace("\r", " ")
  end

  @spec safe_c_suffix(atom() | String.t() | integer() | float()) :: String.t()
  def safe_c_suffix(value) when is_binary(value) do
    String.replace(value, ~r/[^A-Za-z0-9_]/, "_")
  end

  def safe_c_suffix(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> safe_c_suffix()
  end

  def safe_c_suffix(_value), do: "value"

  @spec temp_var(non_neg_integer(), String.t() | nil) :: String.t()
  def temp_var(counter, label \\ nil)

  def temp_var(counter, label) when is_binary(label) and label != "" do
    "tmp_#{counter}_#{safe_c_suffix(label)}"
  end

  def temp_var(counter, _label), do: "tmp_#{counter}"

  @spec boxed_temp_var?(String.t()) :: boolean()
  def boxed_temp_var?(var) when is_binary(var),
    do: Regex.match?(~r/^tmp_\d+(_[a-zA-Z_][a-zA-Z0-9_]*)?$/, var)

  def boxed_temp_var?(_var), do: false

  @spec direct_command_macro(String.t(), String.t()) :: String.t()
  def direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
  end

  @spec local_function_call?(Types.ir_expr(), String.t(), String.t()) :: boolean()
  def local_function_call?(%{op: :call, name: call_name}, _module_name, function_name) do
    call_name == function_name
  end

  def local_function_call?(%{op: :qualified_call, target: target}, module_name, function_name) do
    case split_qualified_function_target(target) do
      {^module_name, ^function_name} -> true
      _ -> false
    end
  end

  def local_function_call?(_, _, _), do: false

  @spec self_recursive_call_in_expr?(Types.ir_expr(), String.t(), String.t()) :: boolean()
  def self_recursive_call_in_expr?(expr, module_name, function_name) when is_map(expr) do
    local_function_call?(expr, module_name, function_name) or
      expr
      |> Map.values()
      |> Enum.any?(&self_recursive_call_in_expr?(&1, module_name, function_name))
  end

  def self_recursive_call_in_expr?(exprs, module_name, function_name) when is_list(exprs) do
    Enum.any?(exprs, &self_recursive_call_in_expr?(&1, module_name, function_name))
  end

  def self_recursive_call_in_expr?(_, _, _), do: false
end
