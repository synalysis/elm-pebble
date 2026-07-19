defmodule ElmEx.Frontend.Pretty.ModuleFixtureRoundTripTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Pretty

  @fixtures [
    {"cons pattern", "cons_pattern_project/src/ConsPattern.elm"},
    {"lambda forms", "lambda_forms_project/src/LambdaForms.elm"},
    {"boolean precedence", "boolean_precedence_project/src/BooleanPrecedence.elm"},
    {"boolean chain", "boolean_chain_project/src/BooleanChain.elm"},
    {"list pattern", "list_pattern_project/src/ListPattern.elm"},
    {"record pattern", "record_pattern_project/src/RecordPattern.elm"},
    {"constructor pattern", "constructor_pattern_project/src/ConstructorPattern.elm"},
    {"case subject", "case_subject_project/src/CaseSubject.elm"},
    {"as pattern", "as_pattern_project/src/AsPattern.elm"},
    {"bool case", "bool_case_project/src/BoolCase.elm"},
    {"if boolean cond", "if_boolean_cond_project/src/IfBooleanCond.elm"},
    {"operator forms", "operator_forms_project/src/OperatorForms.elm"},
    {"arithmetic chain", "arithmetic_chain_project/src/ArithmeticChain.elm"},
    {"extended compare", "extended_compare_project/src/ExtendedCompare.elm"},
    {"syntax edge", "syntax_edge_project/src/SyntaxEdge.elm"},
    {"header variants", "header_variants_project/src/HeaderVariants.elm"},
    {"record alias ctor", "record_alias_ctor_project/src/Main.elm"},
    {"qualified constructors", "qualified_constructor_project/src/Main.elm"},
    {"wasm web events", "wasm_web_events_project/src/Main.elm"},
    {"wasm port incoming", "wasm_port_incoming_project/src/Main.elm"},
    {"rc track char", "rc_track_char_project/src/RcTrackCharProbe.elm"},
    {"rc track grid int", "rc_track_grid_int_project/src/RcTrackGridIntProbe.elm"},
    {"ts derived patterns", "ts_derived_patterns_project/src/TsDerivedPatterns.elm"},
    {"wasm backend task http bytes", "wasm_web_backend_task_http_bytes_project/src/Main.elm"},
    {"wasm backend task http post", "wasm_web_backend_task_http_post_project/src/Main.elm"}
  ]

  for {name, rel_path} <- @fixtures do
    @tag :module_fixture_round_trip
    test "round_trip_module_ast? for #{name} elmc fixture" do
      path = unquote(Path.expand("../../../elmc/test/fixtures/#{rel_path}", __DIR__))
      source = File.read!(path)

      assert Pretty.round_trip_module_ast?(path, source),
             "module AST round-trip failed for #{path}"
    end
  end
end
