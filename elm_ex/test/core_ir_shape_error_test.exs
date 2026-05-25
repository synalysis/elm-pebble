defmodule ElmEx.CoreIRShapeErrorTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR.Validate

  test "validate_shape returns typed shape errors for invalid envelope" do
    assert {:error, errors} = Validate.validate_shape(%{"modules" => []})

    assert [%{code: code, message: message, path: path} = first | _] = errors
    assert is_binary(code)
    assert is_binary(message)
    assert is_list(path)
    assert is_binary(first.code)
    assert is_binary(first.message)
    assert is_list(first.path)
  end
end
