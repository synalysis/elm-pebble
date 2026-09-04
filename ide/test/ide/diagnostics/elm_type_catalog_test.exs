defmodule Ide.Diagnostics.ElmTypeCatalogTest do
  use ExUnit.Case, async: true

  alias Ide.Diagnostics.ElmTypeCatalog
  alias Ide.Compiler.Diagnostics

  test "maps typesys codes to Elm-style titles" do
    assert ElmTypeCatalog.title("type_mismatch") == "TYPE MISMATCH"
    assert ElmTypeCatalog.title("unbound_value") == "NAMING ERROR"
    assert ElmTypeCatalog.title("missing_patterns") == "MISSING PATTERNS"
    assert ElmTypeCatalog.title("function_call_arity") == "TOO MANY ARGS"
    assert ElmTypeCatalog.title("too_few_args") == "TOO FEW ARGS"
    assert ElmTypeCatalog.title("too_many_args") == "TOO MANY ARGS"
    assert ElmTypeCatalog.title("value_cycle") == "CYCLIC DEFINITION"
    assert ElmTypeCatalog.title("bad_tuple") == "BAD TUPLE"
    assert ElmTypeCatalog.title("bad_exposing") == "BAD EXPORT"
    assert ElmTypeCatalog.title("unreachable_pattern") == "UNUSED PATTERN"
  end

  test "normalize prefixes typesys diagnostics with catalog titles" do
    diag =
      Diagnostics.normalize_diagnostic(%{
        "severity" => "error",
        "source" => "elm_ex/typesys",
        "code" => "type_mismatch",
        "message" => "Cannot unify Int with String",
        "file" => "src/Main.elm",
        "line" => 4,
        "column" => nil
      })

    assert diag.source == "elm_ex/typesys"
    assert String.starts_with?(diag.message, "TYPE MISMATCH")
    assert String.contains?(diag.message, "Cannot unify Int with String")
  end
end
