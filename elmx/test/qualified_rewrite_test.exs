defmodule Elmx.QualifiedRewriteTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.QualifiedRewrite

  test "Pkg mangled targets normalize to Elm module names" do
    assert {:ok, %{op: :runtime_call, function: "elmx_time_now", args: []}} =
             QualifiedRewrite.rewrite("Pkg.app.Time.now", [])
  end

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

  test "Random.normalizeSeed rewrites to runtime call" do
    value = %{op: :int_literal, value: 42}

    assert {:ok, %{op: :runtime_call, function: "elmx_core_random_normalize_seed", args: [^value]}} =
             QualifiedRewrite.rewrite("Random.normalizeSeed", [value])
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

  test "Basics.log and String.fromNumber rewrite to runtime calls" do
    x = %{op: :var, name: "n"}

    assert {:ok, %{op: :runtime_call, function: "elmc_basics_log", args: [^x]}} =
             QualifiedRewrite.rewrite("Basics.log", [x])

    assert {:ok, %{op: :runtime_call, function: "elmc_basics_log", args: [^x]}} =
             QualifiedRewrite.rewrite("Elm.Kernel.Basics.log", [x])

    assert {:ok, %{op: :runtime_call, function: "elmc_string_from_number", args: [^x]}} =
             QualifiedRewrite.rewrite("String.fromNumber", [x])

    assert {:ok, %{op: :runtime_call, function: "elmc_string_from_number", args: [^x]}} =
             QualifiedRewrite.rewrite("Elm.Kernel.String.fromNumber", [x])
  end

  test "List toArray/fromArray and Platform.command are identity" do
    xs = %{op: :var, name: "xs"}

    assert {:ok, ^xs} = QualifiedRewrite.rewrite("List.toArray", [xs])
    assert {:ok, ^xs} = QualifiedRewrite.rewrite("List.fromArray", [xs])
    assert {:ok, ^xs} = QualifiedRewrite.rewrite("Elm.Kernel.Platform.command", [xs])
    assert {:ok, ^xs} = QualifiedRewrite.rewrite("Platform.command", [xs])

    assert {:ok, %{op: :lambda, args: ["__cmd"], body: %{op: :var, name: "__cmd"}}} =
             QualifiedRewrite.rewrite("Elm.Kernel.Platform.command", [])
  end

  test "JsArray ops rewrite to list-backed runtime helpers" do
    arr = %{op: :var, name: "arr"}
    fun = %{op: :var, name: "f"}
    acc = %{op: :var, name: "acc"}
    idx = %{op: :int_literal, value: 0}

    assert {:ok, %{op: :list_literal, items: []}} =
             QualifiedRewrite.rewrite("JsArray.empty", [])

    assert {:ok, %{op: :runtime_call, function: "elmc_array_foldl", args: [^fun, ^acc, ^arr]}} =
             QualifiedRewrite.rewrite("JsArray.foldl", [fun, acc, arr])

    assert {:ok, %{op: :runtime_call, function: "elmc_array_foldl"}} =
             QualifiedRewrite.rewrite("Elm.JsArray.foldl", [fun, acc, arr])

    assert {:ok, %{op: :runtime_call, function: "elmc_array_foldl"}} =
             QualifiedRewrite.rewrite("Elm.Kernel.JsArray.foldl", [fun, acc, arr])

    assert {:ok, %{op: :runtime_call, function: "elmc_js_array_unsafe_get", args: [^idx, ^arr]}} =
             QualifiedRewrite.rewrite("Elm.JsArray.unsafeGet", [idx, arr])

    assert {:ok, %{op: :runtime_call, function: "elmc_js_array_initialize_from_list"}} =
             QualifiedRewrite.rewrite("JsArray.initializeFromList", [
               %{op: :int_literal, value: 32},
               arr
             ])

    assert {:ok, %{op: :runtime_call, function: "elmc_js_array_append_n"}} =
             QualifiedRewrite.rewrite("JsArray.appendN", [
               %{op: :int_literal, value: 32},
               arr,
               arr
             ])

    assert {:ok, %{op: :runtime_call, function: "elmc_array_length", args: [^arr]}} =
             QualifiedRewrite.rewrite("JsArray.length", [arr])

    assert {:ok, %{op: :lambda, body: %{op: :runtime_call, function: "elmc_array_foldl"}}} =
             QualifiedRewrite.rewrite("Elm.JsArray.foldl", [])
  end
end
