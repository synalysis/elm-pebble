defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Char do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.String, as: StringValue

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("fromcode", [code]) when is_integer(code), do: {:ok, StringValue.char_from_code(code)}
  def eval("tocode", [char]), do: {:ok, StringValue.char_to_code(char)}

  def eval("isupper", [char]),
    do: {:ok, StringValue.char_predicate(char, &StringValue.char_upper?/1)}

  def eval("islower", [char]),
    do: {:ok, StringValue.char_predicate(char, &StringValue.char_lower?/1)}

  def eval("isalpha", [char]),
    do: {:ok, StringValue.char_predicate(char, &StringValue.char_alpha?/1)}

  def eval("isalphanum", [char]),
    do: {:ok, StringValue.char_predicate(char, &StringValue.char_alphanum?/1)}

  def eval("isdigit", [char]),
    do: {:ok, StringValue.char_predicate(char, &StringValue.char_digit?/1)}

  def eval("isoctdigit", [char]),
    do: {:ok, StringValue.char_predicate(char, &StringValue.char_octal_digit?/1)}

  def eval(_function_name, _values), do: :no_builtin
end
