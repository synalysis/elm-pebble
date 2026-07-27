defmodule ElmEx.DiagnosticFormatterTest do
  use ExUnit.Case

  alias ElmEx.DiagnosticFormatter

  test "formats missing elm.json nicely" do
    output =
      DiagnosticFormatter.format_error(%{
        kind: :config_error,
        reason: :missing_elm_json,
        path: "/tmp/demo/elm.json"
      })

    assert output =~ "MISSING elm.json"
    assert output =~ "/tmp/demo/elm.json"
    assert output =~ "elm init"
  end

  test "formats parse errors with file and line" do
    output =
      DiagnosticFormatter.format_error(%{
        kind: :parse_error,
        path: "src/Main.elm",
        line: 12,
        reason: :missing_module_header
      })

    assert output =~ "PARSE ERROR"
    assert output =~ "src/Main.elm:12"
    assert output =~ "missing_module_header"
  end

  test "formats elm compile-errors payloads" do
    output =
      DiagnosticFormatter.format_error(%{
        kind: :elm_check_failed,
        diagnostics: [
          %{
            "type" => "compile-errors",
            "errors" => [
              %{
                "path" => "src/Main.elm",
                "problems" => [
                  %{
                    "title" => "TYPE MISMATCH",
                    "region" => %{"start" => %{"line" => 7, "column" => 3}},
                    "message" => ["Expected Int but got String."]
                  }
                ]
              }
            ]
          }
        ],
        raw: ""
      })

    assert output =~ "TYPE MISMATCH"
    assert output =~ "src/Main.elm:7:3"
    assert output =~ "Expected Int but got String."
  end

  test "formats lowerer warnings from bridge diagnostics" do
    output =
      DiagnosticFormatter.format_warnings([
        %{
          "type" => "lowerer-warning",
          "source" => "lowerer/pattern",
          "code" => "constructor_payload_arity",
          "module" => "Main",
          "function" => "update",
          "line" => 42,
          "constructor" => "Msg",
          "expected_kind" => "single",
          "has_arg_pattern" => false,
          "message" => "Constructor Msg expects a payload pattern",
          "severity" => "warning"
        }
      ])

    assert output =~ "LOWERER WARNING"
    assert output =~ "Main.update:42"
    assert output =~ "Structured:"
    assert output =~ "Code: constructor_payload_arity"
    assert output =~ "Constructor: Msg"
    assert output =~ "Expected Kind: single"
    assert output =~ "Has Arg Pattern: false"
    assert output =~ "payload pattern"
  end

  test "formats lowerer warnings from raw ir diagnostics" do
    output =
      DiagnosticFormatter.format_warnings([
        %{
          source: "lowerer/pattern",
          code: "constructor_payload_arity",
          module: "Main",
          function: "update",
          line: 8,
          constructor: "Maybe",
          expected_kind: :none,
          has_arg_pattern: true,
          message: "Constructor Msg has mismatch",
          severity: "warning"
        }
      ])

    assert output =~ "LOWERER WARNING"
    assert output =~ "Main.update:8"
    assert output =~ "Code: constructor_payload_arity"
    assert output =~ "Expected Kind: none"
    assert output =~ "Has Arg Pattern: true"
    assert output =~ "mismatch"
  end
end
