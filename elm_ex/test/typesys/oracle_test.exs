defmodule ElmEx.Typesys.OracleTest do
  use ExUnit.Case, async: false

  alias ElmEx.Typesys.Oracle

  @moduletag :typesys_oracle

  test "rejects the same invalid snippets elm make rejects" do
    Enum.each(invalid_snippets(), fn {name, source} ->
      dir = write_project!(name, source)
      assert {:ok, result} = Oracle.compare(dir)

      assert result.typesys == :reject,
             "#{name}: typesys accepted (elm=#{inspect(result.elm)} families=#{inspect(result.typesys_families)}/#{inspect(result.elm_families)})"
      if result.elm != :skip do
        assert result.elm == :reject
        assert_family_overlap!(name, result)
      end
    end)
  end

  test "accepts valid elm/core-shaped programs" do
    Enum.each(valid_snippets(), fn {name, source} ->
      dir = write_project!(name, source)
      assert {:ok, %{typesys: :accept, elm: elm}} = Oracle.compare(dir), name
      if elm != :skip, do: assert(elm == :accept, "#{name}: elm=#{inspect(elm)}")
    end)
  end

  test "false-positive gate: two differently named fixtures still typecheck" do
    fixtures = [
      Path.expand("../../../elmx/test/fixtures/minimal", __DIR__),
      write_project!("counter_valid", """
      module Counter exposing (Model, step)

      type alias Model =
          { count : Int }

      step : Model -> Model
      step model =
          { model | count = model.count + 1 }
      """)
    ]

    Enum.each(fixtures, fn dir ->
      assert File.dir?(dir), "missing fixture #{dir}"
      assert {:ok, %{typesys: :accept}} = Oracle.compare(dir)
    end)
  end

  test "second app-shaped fixture with different names still accepts" do
    source = """
    module Watchface exposing (Model, init)

    type alias Model =
        { ticks : Int }

    init : Model
    init =
        { ticks = 0 }
    """

    dir = write_project!("watchface_valid", source)
    assert {:ok, %{typesys: :accept}} = Oracle.compare(dir)
  end

  defp valid_snippets do
    [
      {"id_int",
       """
       module Main exposing (id)

       id : Int -> Int
       id x =
           x
       """},
      {"maybe_exhaustive",
       """
       module Main exposing (peel)

       peel : Maybe Int -> Int
       peel m =
           case m of
               Just n ->
                   n

               Nothing ->
                   0
       """},
      {"mutual_recursion",
       """
       module Main exposing (even)

       even : Int -> Bool
       even n =
           if n == 0 then
               True

           else
               odd (n - 1)

       odd : Int -> Bool
       odd n =
           if n == 0 then
               False

           else
               even (n - 1)
       """},
      {"alias_params",
       """
       module Main exposing (origin)

       type alias Pair a b =
           ( a, b )

       origin : Pair Int String
       origin =
           ( 1, "x" )
       """},
      {"as_and_cons",
       """
       module Main exposing (head)

       head : List Int -> Int
       head xs =
           case xs of
               n :: _ as whole ->
                   n + List.length whole

               [] ->
                   0
       """},
      {"let_tuple",
       """
       module Main exposing (sum)

       sum : Int
       sum =
           let
               ( a, b ) =
                   ( 1, 2 )
           in
           a + b
       """},
      {"recursive_fun_value",
       """
       module Main exposing (forever)

       forever : Int -> Int
       forever =
           \\n ->
               forever (n + 1)
       """},
      {"time_hour",
       """
       module Main exposing (hour)

       import Time

       hour : Time.Posix -> Int
       hour t =
           Time.toHour Time.utc t
       """},
      {"json_decoder",
       """
       module Main exposing (readInt)

       import Json.Decode as Decode

       readInt : Decode.Decoder Int
       readInt =
           Decode.int
       """},
      {"random_die",
       """
       module Main exposing (roll)

       import Random

       roll : Random.Generator Int
       roll =
           Random.int 1 6
       """},
      {"eq_bool",
       """
       module Main exposing (same)

       same : Bool -> Bool -> Bool
       same a b =
           a == b
       """},
      {"json_value_port",
       """
       port module Main exposing (out)

       import Json.Encode as Encode

       port out : Encode.Value -> Cmd msg
       """},
      {"extensible_record",
       """
       module Main exposing (reset)

       reset : { model | flag : Bool } -> { model | flag : Bool }
       reset model =
           { model | flag = False }
       """},
      {"cons_of_tuple",
       """
       module Main exposing (lookup)

       lookup : String -> List ( String, Int ) -> Maybe Int
       lookup name pairs =
           case pairs of
               [] ->
                   Nothing

               ( key, value ) :: rest ->
                   if key == name then
                       Just value

                   else
                       lookup name rest
       """},
      {"parenthesized_pipes",
       """
       module Main exposing (go)

       go : Int
       go =
           let
               f n =
                   n + 1

               a =
                   (<|) f 10

               b =
                   (|>) 10 f
           in
           a + b
       """},
      {"result_andthen_triple",
       """
       module Main exposing (go)

       go : Result String Int
       go =
           Ok ( [], [], 0 )
               |> Result.andThen
                   (\\( rev, offs, off ) ->
                       Ok ( 1 :: rev, off :: offs, off + 1 )
                   )
               |> Result.map (\\( rev, _, _ ) -> List.length rev)
       """}
    ]
  end

  defp invalid_snippets do
    [
      {"type_mismatch",
       """
       module Main exposing (bad)

       bad : Int -> Int
       bad x =
           "nope"
       """},
      {"unbound",
       """
       module Main exposing (go)

       go : Int -> Int
       go x =
           missing
       """},
      {"missing_patterns",
       """
       module Main exposing (peel)

       peel : Maybe Int -> Int
       peel m =
           case m of
               Just n ->
                   n
       """},
      {"too_many_args",
       """
       module Main exposing (go)

       go : Maybe Int
       go =
           Just 1 2
       """},
      {"too_few_type_args",
       """
       module Main exposing (go)

       go : Maybe
       go =
           Nothing
       """},
      {"too_many_type_args",
       """
       module Main exposing (go)

       go : Maybe Int String
       go =
           Nothing
       """},
      {"qualified_unknown",
       """
       module Main exposing (go)

       go : Int
       go =
           Nope.missing
       """},
      {"rigid_number",
       """
       module Main exposing (id)

       id : a -> a
       id x =
           x + 1
       """},
      {"nested_missing",
       """
       module Main exposing (peel)

       peel : Maybe (Maybe Int) -> Int
       peel m =
           case m of
               Just (Just n) ->
                   n
       """},
      {"redundant_just",
       """
       module Main exposing (peel)

       peel : Maybe Int -> Int
       peel m =
           case m of
               Just _ ->
                   1

               Just n ->
                   n

               Nothing ->
                   0
       """},
      {"ambiguous_import",
       """
       module Main exposing (go)

       import Json.Decode exposing (string)
       import Json.Encode exposing (string)

       go : Json.Decode.Decoder String
       go =
           string
       """},
      {"port_maybe",
       """
       port module Main exposing (out)

       port out : Maybe Int -> Cmd msg
       """},
      {"value_cycle",
       """
       module Main exposing (x)

       x : Int
       x =
           x + 1
       """},
      {"mutual_value_cycle",
       """
       module Main exposing (x)

       x : Int
       x =
           y

       y : Int
       y =
           x
       """},
      {"alias_dotdot",
       """
       module Main exposing (Point(..))

       type alias Point =
           { x : Int }
       """},
      {"missing_record_field",
       """
       module Main exposing (origin)

       type alias Point =
           { x : Int, y : Int }

       origin : Point
       origin =
           { x = 0 }
       """},
      {"four_tuple",
       """
       module Main exposing (go)

       go : Int
       go =
           let
               ( a, b, c, d ) =
                   ( 1, 2, 3, 4 )
           in
           a
       """},
      {"lambda_just",
       """
       module Main exposing (peel)

       peel : Maybe Int -> Int
       peel =
           \\(Just n) ->
               n
       """},
      {"compare_bool",
       """
       module Main exposing (bad)

       bad : Bool
       bad =
           1 < True
       """},
      {"append_mix",
       """
       module Main exposing (bad)

       bad : String
       bad =
           "x" ++ [ 1 ]
       """},
      {"cons_in_cons",
       """
       module Main exposing (peel)

       peel : List Int -> Int
       peel xs =
           case xs of
               a :: b :: rest ->
                   a + b
       """},
      {"record_lt",
       """
       module Main exposing (bad)

       bad : Bool
       bad =
           { x = 1 } < { x = 2 }
       """},
      {"posix_port",
       """
       port module Main exposing (out)

       import Time

       port out : Time.Posix -> Cmd msg
       """}
    ]
  end

  defp assert_family_overlap!(name, result) do
    assert Oracle.families_overlap?(result.typesys_families, result.elm_families),
           "#{name}: typesys=#{inspect(result.typesys_families)} elm=#{inspect(result.elm_families)}"
  end

  defp write_project!(name, source) do
    dir = Path.join(System.tmp_dir!(), "elm-ex-typesys-oracle-#{name}-#{System.unique_integer([:positive])}")
    src = Path.join(dir, "src")
    File.rm_rf!(dir)
    File.mkdir_p!(src)
    file = module_file_name(source)
    File.write!(Path.join(src, file), source)

    elm_json = """
    {
      "type": "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      "dependencies": {
        "direct": {
          "elm/core": "1.0.5",
          "elm/json": "1.1.3",
          "elm/time": "1.0.0",
          "elm/random": "1.0.0"
        },
        "indirect": {}
      },
      "test-dependencies": {
        "direct": {},
        "indirect": {}
      }
    }
    """

    File.write!(Path.join(dir, "elm.json"), elm_json)
    File.write!(Path.join(dir, ".tool-versions"), "elm 0.19.1\n")
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp module_file_name(source) do
    case Regex.run(~r/^module\s+([A-Za-z0-9.]+)/m, source) do
      [_, name] -> String.replace(name, ".", "/") <> ".elm"
      _ -> "Main.elm"
    end
  end
end
