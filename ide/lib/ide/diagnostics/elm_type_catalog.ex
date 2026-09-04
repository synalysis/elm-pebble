defmodule Ide.Diagnostics.ElmTypeCatalog do
  @moduledoc """
  Titles for `elm_ex/typesys` diagnostics. Wording can lag official Elm prose;
  rejection codes are the contract.
  """

  @titles %{
    "type_mismatch" => "TYPE MISMATCH",
    "unbound_value" => "NAMING ERROR",
    "missing_patterns" => "MISSING PATTERNS",
    "unreachable_pattern" => "UNUSED PATTERN",
    "duplicate_declaration" => "NAMING ERROR",
    "duplicate_type" => "NAMING ERROR",
    "duplicate_pattern" => "NAMING ERROR",
    "bad_exposing" => "BAD EXPORT",
    "module_name_mismatch" => "MODULE NAME MISMATCH",
    "recursive_alias" => "RECURSIVE ALIAS",
    "unexpected_ports" => "UNEXPECTED PORTS",
    "package_ports" => "PACKAGES CANNOT HAVE PORTS",
    "port_problem" => "PORT PROBLEM",
    "function_call_arity" => "TOO MANY ARGS",
    "too_many_args" => "TOO MANY ARGS",
    "too_few_args" => "TOO FEW ARGS",
    "value_cycle" => "CYCLIC DEFINITION",
    "bad_tuple" => "BAD TUPLE",
    "unsupported_expr" => "TYPE PROBLEM",
    "ambiguous_import" => "NAMING ERROR"
  }

  @spec title(String.t() | nil) :: String.t()
  def title(code) when is_binary(code), do: Map.get(@titles, code, "TYPE PROBLEM")
  def title(_), do: "TYPE PROBLEM"

  @spec decorate_message(map()) :: String.t()
  def decorate_message(diag) when is_map(diag) do
    code = Map.get(diag, "code", Map.get(diag, :code))
    message = Map.get(diag, "message", Map.get(diag, :message)) || ""
    title(code) <> "\n\n" <> message
  end
end
