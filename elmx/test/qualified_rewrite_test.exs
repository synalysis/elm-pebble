defmodule Elmx.QualifiedRewriteTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.QualifiedRewrite

  test "Maybe.withDefault curried form rewrites to lambda" do
    assert {:ok, %{op: :lambda, body: %{op: :runtime_call, function: "elmx_core_maybe_with_default"}}} =
             QualifiedRewrite.rewrite("Maybe.withDefault", [%{op: :int_literal, value: 0}])
  end

  test "Random.int rewrites to generator runtime call" do
    assert {:ok, %{op: :runtime_call, function: "elmx_core_random_generator"}} =
             QualifiedRewrite.rewrite("Random.int", [
               %{op: :int_literal, value: 1},
               %{op: :int_literal, value: 10}
             ])
  end

  test "Basics.compare full arity rewrites to runtime call" do
    a = %{op: :int_literal, value: 1}
    b = %{op: :int_literal, value: 2}

    assert {:ok, %{op: :runtime_call, function: "elmx_basics_compare", args: [^a, ^b]}} =
             QualifiedRewrite.rewrite("Basics.compare", [a, b])
  end

  test "Tuple.first rewrites to tuple_first op" do
    tuple = %{op: :var, name: "t"}

    assert {:ok, %{op: :tuple_first, arg: ^tuple}} =
             QualifiedRewrite.rewrite("Tuple.first", [tuple])
  end

  test "List.repeat is handled by list codegen not qualified rewrite" do
    n = %{op: :int_literal, value: 3}
    v = %{op: :int_literal, value: 0}

    assert :error = QualifiedRewrite.rewrite("List.repeat", [n, v])
  end

  test "Basics.pi rewrites to float literal" do
    assert {:ok, %{op: :float_literal, value: 3.141592653589793}} =
             QualifiedRewrite.rewrite("Basics.pi", [])
  end
end
