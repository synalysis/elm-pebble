defmodule Elmx.QualifiedCodegenTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib.QualifiedCodegen

  test "list_hof full and partial shapes use Core paths" do
    assert {:ok, code} = QualifiedCodegen.list_hof("map", "f", "xs")
    assert code == "#{CodegenRefs.core()}.map(f, xs)"

    assert {:ok, partial} = QualifiedCodegen.list_hof("filter", "p", nil)
    assert partial =~ "fn elmx_list ->"
    assert partial =~ ".filter(p, elmx_list)"
  end

  test "list_fold supports three partialities" do
    core = CodegenRefs.core()

    assert {:ok, full} = QualifiedCodegen.list_fold("foldl", "f", "0", "xs")
    assert full == "#{core}.foldl(f, 0, xs)"

    assert {:ok, acc_only} = QualifiedCodegen.list_fold("foldl", "f", "0", nil)
    assert acc_only =~ "fn elmx_list ->"
    assert acc_only =~ ".foldl(f, 0, elmx_list)"

    assert {:ok, fun_only} = QualifiedCodegen.list_fold("foldr", "f", nil, nil)
    assert fun_only =~ "fn elmx_acc, elmx_list ->"
  end

  test "collection_call lowers Dict/Set/Array ops" do
    mod = CodegenRefs.core_collections()

    assert {:ok, code} = QualifiedCodegen.collection_call(mod, "dict", "union", "a, b")
    assert code == "#{mod}.dict_union(a, b)"
  end

  test "with_container supports dict and list container-last APIs" do
    col = CodegenRefs.core_collections()
    core = CodegenRefs.core()

    assert {:ok, get} = QualifiedCodegen.with_container(col, "dict_get", ["k"], "d")
    assert get == "#{col}.dict_get(k, d)"

    assert {:ok, partial} = QualifiedCodegen.with_container(col, "dict_insert", ["k", "v"], nil)
    assert partial =~ "fn elmx_dict ->"
    assert partial =~ "dict_insert(k, v, elmx_dict)"

    assert {:ok, member} =
             QualifiedCodegen.with_container(core, "member", ["x"], nil, container_param: "elmx_list")

    assert member =~ ".member(x, elmx_list)"
  end

  test "unary_call supports String unary helpers" do
    mod = CodegenRefs.core_strings()

    assert {:ok, full} = QualifiedCodegen.unary_call(mod, "lines", "s")
    assert full == "#{mod}.lines(s)"

    assert {:ok, partial} = QualifiedCodegen.unary_call(mod, "reverse", nil)
    assert partial =~ "fn elmx_str ->"
    assert partial =~ ".reverse(elmx_str)"
  end

  test "list_hof accepts Core.Strings module for String.map shape" do
    mod = CodegenRefs.core_strings()

    assert {:ok, code} =
             QualifiedCodegen.list_hof("map", "f", "text", module: Elmx.Runtime.Core.Strings,
               list_param: "elmx_text"
             )

    assert code == "#{mod}.map(f, text)"
  end

  test "module_call lowers runtime module n-ary calls" do
    math = CodegenRefs.core_math()
    bitwise = CodegenRefs.core_bitwise()

    assert {:ok, code} = QualifiedCodegen.module_call(math, "pow", ["2", "x"])
    assert code == "#{math}.pow(2, x)"

    assert {:ok, bw} = QualifiedCodegen.module_call(bitwise, "and_", ["a", "b"])
    assert bw == "#{bitwise}.and_(a, b)"
  end

  test "combinator_last supports Result partial application" do
    mr = CodegenRefs.maybe_result()

    assert {:ok, full} = QualifiedCodegen.combinator_last(mr, "result_and_then", ["f"], "r")
    assert full == "#{mr}.result_and_then(f, r)"

    assert {:ok, partial} = QualifiedCodegen.combinator_last(mr, "result_map_error", ["f"], nil)
    assert partial =~ "fn result ->"
  end
end
