defmodule ElmEx.Typesys.ParserTest do
  use ExUnit.Case, async: true

  alias ElmEx.Typesys.{Parser, Type}

  test "parses primitives and arrows" do
    assert {:ok, {:fun, {:named, "Int", []}, {:named, "Bool", []}}} = Parser.parse("Int -> Bool")
  end

  test "parses list application and tuples" do
    assert {:ok, {:named, "List", [{:named, "Int", []}]}} = Parser.parse("List Int")
    assert {:ok, {:tuple, [{:named, "Int", []}, {:named, "String", []}]}} = Parser.parse("(Int, String)")
  end

  test "parses records and extensible rows" do
    assert {:ok, {:record, fields, nil}} = Parser.parse("{ x : Int, y : Float }")
    assert fields["x"] == Type.int()
    assert {:ok, {:record, %{"x" => _}, ext}} = Parser.parse("{ a | x : Int }")
    assert ext != nil
  end

  test "extensible record variable in the return is the record type" do
    assert {:ok, {:fun, {:record, fields, ext}, {:record, fields, ext}}} =
             Parser.parse("{ a | x : Int } -> a")
  end

  test "parses constructor payloads as juxtaposed atomic types" do
    assert {:ok, [string, int1, int2]} = Parser.parse_ctor_args("String Int Int")
    assert string == Type.string()
    assert int1 == Type.int()
    assert int2 == Type.int()

    assert {:ok, [list, int]} = Parser.parse_ctor_args("(List Int) Int")
    assert list == Type.list(Type.int())
    assert int == Type.int()
  end

  test "rejects 4-tuples" do
    assert {:error, _} = Parser.parse("(Int, Int, Int, Int)")
  end

  test "parses number constraint and variables" do
    assert {:ok, {:constrained, :number, _}} = Parser.parse("number")
    assert {:ok, {:fun, {:var, a}, {:var, a}}} = Parser.parse("a -> a")
  end

  test "canonicalizes official Time and Json type names" do
    assert {:ok, {:fun, {:named, "Posix", []}, {:named, "Int", []}}} =
             Parser.parse("Time.Posix -> Int")

    assert {:ok, {:named, "Decoder", [{:named, "Int", []}]}} =
             Parser.parse("Json.Decode.Decoder Int")
  end
end
