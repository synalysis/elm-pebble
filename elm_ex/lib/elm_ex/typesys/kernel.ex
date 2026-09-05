defmodule ElmEx.Typesys.Kernel do
  @moduledoc """
  elm/core (and later elm/json) value and constructor schemes from documented
  signatures — not C runtime names.
  """

  alias ElmEx.Typesys.{Env, Parser}

  @signatures %{
    "Basics.toFloat" => "Int -> Float",
    "Basics.round" => "Float -> Int",
    "Basics.floor" => "Float -> Int",
    "Basics.ceiling" => "Float -> Int",
    "Basics.truncate" => "Float -> Int",
    "Basics.negate" => "number -> number",
    "Basics.abs" => "number -> number",
    "Basics.max" => "comparable -> comparable -> comparable",
    "Basics.min" => "comparable -> comparable -> comparable",
    "Basics.clamp" => "comparable -> comparable -> comparable -> comparable",
    "Basics.sqrt" => "Float -> Float",
    "Basics.logBase" => "Float -> Float -> Float",
    "Basics.modBy" => "Int -> Int -> Int",
    "Basics.remainderBy" => "Int -> Int -> Int",
    "Basics.not" => "Bool -> Bool",
    "Basics.xor" => "Bool -> Bool -> Bool",
    "Basics.identity" => "a -> a",
    "Basics.always" => "a -> b -> a",
    "Basics.never" => "Never -> a",
    "Basics.compare" => "comparable -> comparable -> Order",
    "Basics.sin" => "Float -> Float",
    "Basics.cos" => "Float -> Float",
    "Basics.tan" => "Float -> Float",
    "Basics.asin" => "Float -> Float",
    "Basics.acos" => "Float -> Float",
    "Basics.atan" => "Float -> Float",
    "Basics.atan2" => "Float -> Float -> Float",
    "Basics.degrees" => "Float -> Float",
    "Basics.radians" => "Float -> Float",
    "Basics.turns" => "Float -> Float",
    "Basics.fromPolar" => "(Float, Float) -> (Float, Float)",
    "Basics.toPolar" => "(Float, Float) -> (Float, Float)",
    "Basics.isNaN" => "Float -> Bool",
    "Basics.isInfinite" => "Float -> Bool",
    "(+)" => "number -> number -> number",
    "(-)" => "number -> number -> number",
    "(*)" => "number -> number -> number",
    "(/)" => "Float -> Float -> Float",
    "(//)" => "Int -> Int -> Int",
    "(^)" => "number -> number -> number",
    "(==)" => "a -> a -> Bool",
    "(/=)" => "a -> a -> Bool",
    "(<)" => "comparable -> comparable -> Bool",
    "(>)" => "comparable -> comparable -> Bool",
    "(<=)" => "comparable -> comparable -> Bool",
    "(>=)" => "comparable -> comparable -> Bool",
    "(&&)" => "Bool -> Bool -> Bool",
    "(||)" => "Bool -> Bool -> Bool",
    "(++)" => "appendable -> appendable -> appendable",
    "(::)" => "a -> List a -> List a",
    "(<|)" => "(a -> b) -> a -> b",
    "(|>)" => "a -> (a -> b) -> b",
    "(<<)" => "(b -> c) -> (a -> b) -> (a -> c)",
    "(>>)" => "(a -> b) -> (b -> c) -> (a -> c)",
    "Basics.add" => "number -> number -> number",
    "Basics.sub" => "number -> number -> number",
    "Basics.mul" => "number -> number -> number",
    "Basics.fdiv" => "Float -> Float -> Float",
    "Basics.idiv" => "Int -> Int -> Int",
    "List.isEmpty" => "List a -> Bool",
    "List.length" => "List a -> Int",
    "List.reverse" => "List a -> List a",
    "List.member" => "a -> List a -> Bool",
    "List.head" => "List a -> Maybe a",
    "List.tail" => "List a -> Maybe (List a)",
    "List.filter" => "(a -> Bool) -> List a -> List a",
    "List.take" => "Int -> List a -> List a",
    "List.drop" => "Int -> List a -> List a",
    "List.singleton" => "a -> List a",
    "List.cons" => "a -> List a -> List a",
    "Elm.Kernel.List.cons" => "a -> List a -> List a",
    "List.repeat" => "Int -> a -> List a",
    "List.range" => "Int -> Int -> List Int",
    "List.append" => "List a -> List a -> List a",
    "List.concat" => "List (List a) -> List a",
    "List.intersperse" => "a -> List a -> List a",
    "List.map" => "(a -> b) -> List a -> List b",
    "List.indexedMap" => "(Int -> a -> b) -> List a -> List b",
    "List.foldl" => "(a -> b -> b) -> b -> List a -> b",
    "List.foldr" => "(a -> b -> b) -> b -> List a -> b",
    "List.filterMap" => "(a -> Maybe b) -> List a -> List b",
    "List.concatMap" => "(a -> List b) -> List a -> List b",
    "List.any" => "(a -> Bool) -> List a -> Bool",
    "List.all" => "(a -> Bool) -> List a -> Bool",
    "List.sort" => "List comparable -> List comparable",
    "List.sortBy" => "(a -> comparable) -> List a -> List a",
    "List.sortWith" => "(a -> a -> Order) -> List a -> List a",
    "List.sum" => "List number -> number",
    "List.product" => "List number -> number",
    "List.maximum" => "List comparable -> Maybe comparable",
    "List.minimum" => "List comparable -> Maybe comparable",
    "List.map2" => "(a -> b -> result) -> List a -> List b -> List result",
    "List.map3" => "(a -> b -> c -> result) -> List a -> List b -> List c -> List result",
    "List.map4" =>
      "(a -> b -> c -> d -> result) -> List a -> List b -> List c -> List d -> List result",
    "List.map5" =>
      "(a -> b -> c -> d -> e -> result) -> List a -> List b -> List c -> List d -> List e -> List result",
    "List.partition" => "(a -> Bool) -> List a -> (List a, List a)",
    "List.unzip" => "List (a, b) -> (List a, List b)",
    "Maybe.withDefault" => "a -> Maybe a -> a",
    "Maybe.map" => "(a -> b) -> Maybe a -> Maybe b",
    "Maybe.map2" => "(a -> b -> value) -> Maybe a -> Maybe b -> Maybe value",
    "Maybe.map3" => "(a -> b -> c -> value) -> Maybe a -> Maybe b -> Maybe c -> Maybe value",
    "Maybe.map4" =>
      "(a -> b -> c -> d -> value) -> Maybe a -> Maybe b -> Maybe c -> Maybe d -> Maybe value",
    "Maybe.map5" =>
      "(a -> b -> c -> d -> e -> value) -> Maybe a -> Maybe b -> Maybe c -> Maybe d -> Maybe e -> Maybe value",
    "Maybe.andThen" => "(a -> Maybe b) -> Maybe a -> Maybe b",
    "Result.withDefault" => "a -> Result x a -> a",
    "Result.map2" => "(a -> b -> value) -> Result x a -> Result x b -> Result x value",
    "Result.map3" =>
      "(a -> b -> c -> value) -> Result x a -> Result x b -> Result x c -> Result x value",
    "Result.map4" =>
      "(a -> b -> c -> d -> value) -> Result x a -> Result x b -> Result x c -> Result x d -> Result x value",
    "Result.map" => "(a -> b) -> Result x a -> Result x b",
    "Result.mapError" => "(x -> y) -> Result x a -> Result y a",
    "Result.andThen" => "(a -> Result x b) -> Result x a -> Result x b",
    "Result.toMaybe" => "Result x a -> Maybe a",
    "Result.fromMaybe" => "x -> Maybe a -> Result x a",
    "String.isEmpty" => "String -> Bool",
    "String.length" => "String -> Int",
    "String.reverse" => "String -> String",
    "String.repeat" => "Int -> String -> String",
    "String.replace" => "String -> String -> String -> String",
    "String.append" => "String -> String -> String",
    "String.concat" => "List String -> String",
    "String.split" => "String -> String -> List String",
    "String.join" => "String -> List String -> String",
    "String.words" => "String -> List String",
    "String.lines" => "String -> List String",
    "String.slice" => "Int -> Int -> String -> String",
    "String.left" => "Int -> String -> String",
    "String.right" => "Int -> String -> String",
    "String.dropLeft" => "Int -> String -> String",
    "String.dropRight" => "Int -> String -> String",
    "String.contains" => "String -> String -> Bool",
    "String.startsWith" => "String -> String -> Bool",
    "String.endsWith" => "String -> String -> Bool",
    "String.indexes" => "String -> String -> List Int",
    "String.indices" => "String -> String -> List Int",
    "String.toInt" => "String -> Maybe Int",
    "String.fromInt" => "Int -> String",
    "String.toFloat" => "String -> Maybe Float",
    "String.fromFloat" => "Float -> String",
    "String.fromChar" => "Char -> String",
    "String.cons" => "Char -> String -> String",
    "String.uncons" => "String -> Maybe (Char, String)",
    "String.toList" => "String -> List Char",
    "String.fromList" => "List Char -> String",
    "String.toUpper" => "String -> String",
    "String.toLower" => "String -> String",
    "String.toLocaleUpper" => "String -> String",
    "String.toLocaleLower" => "String -> String",
    "String.trim" => "String -> String",
    "String.trimLeft" => "String -> String",
    "String.trimRight" => "String -> String",
    "String.map" => "(Char -> Char) -> String -> String",
    "String.filter" => "(Char -> Bool) -> String -> String",
    "String.foldl" => "(Char -> b -> b) -> b -> String -> b",
    "String.foldr" => "(Char -> b -> b) -> b -> String -> b",
    "String.any" => "(Char -> Bool) -> String -> Bool",
    "String.all" => "(Char -> Bool) -> String -> Bool",
    "String.pad" => "Int -> Char -> String -> String",
    "String.padLeft" => "Int -> Char -> String -> String",
    "String.padRight" => "Int -> Char -> String -> String",
    "Char.toCode" => "Char -> Int",
    "Char.fromCode" => "Int -> Char",
    "Char.toUpper" => "Char -> Char",
    "Char.toLower" => "Char -> Char",
    "Char.toLocaleUpper" => "Char -> Char",
    "Char.toLocaleLower" => "Char -> Char",
    "Char.isUpper" => "Char -> Bool",
    "Char.isLower" => "Char -> Bool",
    "Char.isAlpha" => "Char -> Bool",
    "Char.isAlphaNum" => "Char -> Bool",
    "Char.isDigit" => "Char -> Bool",
    "Tuple.pair" => "a -> b -> (a, b)",
    "Tuple.first" => "(a, b) -> a",
    "Tuple.second" => "(a, b) -> b",
    "Tuple.mapFirst" => "(a -> x) -> (a, b) -> (x, b)",
    "Tuple.mapSecond" => "(b -> y) -> (a, b) -> (a, y)",
    "Tuple.mapBoth" => "(a -> x) -> (b -> y) -> (a, b) -> (x, y)",
    "Debug.log" => "String -> a -> a",
    "Debug.toString" => "a -> String",
    "Debug.todo" => "String -> a",
    "Bitwise.and" => "Int -> Int -> Int",
    "Bitwise.or" => "Int -> Int -> Int",
    "Bitwise.xor" => "Int -> Int -> Int",
    "Bitwise.complement" => "Int -> Int",
    "Bitwise.shiftLeftBy" => "Int -> Int -> Int",
    "Bitwise.shiftRightBy" => "Int -> Int -> Int",
    "Bitwise.shiftRightZfBy" => "Int -> Int -> Int",
    "Platform.Cmd.none" => "Cmd msg",
    "Platform.Cmd.batch" => "List (Cmd msg) -> Cmd msg",
    "Platform.Cmd.map" => "(a -> msg) -> Cmd a -> Cmd msg",
    "Platform.Sub.none" => "Sub msg",
    "Platform.Sub.batch" => "List (Sub msg) -> Sub msg",
    "Platform.Sub.map" => "(a -> msg) -> Sub a -> Sub msg",
    "Json.Decode.string" => "Decoder String",
    "Json.Decode.int" => "Decoder Int",
    "Json.Decode.float" => "Decoder Float",
    "Json.Decode.bool" => "Decoder Bool",
    "Json.Decode.list" => "Decoder a -> Decoder (List a)",
    "Json.Decode.array" => "Decoder a -> Decoder (Array a)",
    "Json.Decode.succeed" => "a -> Decoder a",
    "Json.Decode.fail" => "String -> Decoder a",
    "Json.Decode.map" => "(a -> value) -> Decoder a -> Decoder value",
    "Json.Decode.map2" => "(a -> b -> value) -> Decoder a -> Decoder b -> Decoder value",
    "Json.Decode.field" => "String -> Decoder a -> Decoder a",
    "Json.Decode.decodeString" => "Decoder a -> String -> Result Error a",
    "Json.Decode.decodeValue" => "Decoder a -> Value -> Result Error a",
    "Json.Decode.errorToString" => "Error -> String",
    "Json.Decode.map6" =>
      "(a -> b -> c -> d -> e -> f -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder f -> Decoder value",
    "Json.Decode.map7" =>
      "(a -> b -> c -> d -> e -> f -> g -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder f -> Decoder g -> Decoder value",
    "Json.Decode.map8" =>
      "(a -> b -> c -> d -> e -> f -> g -> h -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder f -> Decoder g -> Decoder h -> Decoder value",
    "Json.Encode.string" => "String -> Value",
    "Json.Encode.int" => "Int -> Value",
    "Json.Encode.float" => "Float -> Value",
    "Json.Encode.bool" => "Bool -> Value",
    "Json.Encode.null" => "Value",
    "Json.Encode.list" => "(a -> Value) -> List a -> Value",
    "Json.Encode.object" => "List (String, Value) -> Value",
    "Json.Encode.array" => "(a -> Value) -> Array a -> Value",
    "Json.Encode.set" => "(a -> Value) -> Set a -> Value",
    "Json.Decode.map3" =>
      "(a -> b -> c -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder value",
    "Json.Decode.map4" =>
      "(a -> b -> c -> d -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder value",
    "Json.Decode.map5" =>
      "(a -> b -> c -> d -> e -> value) -> Decoder a -> Decoder b -> Decoder c -> Decoder d -> Decoder e -> Decoder value",
    "Json.Decode.andThen" => "(a -> Decoder b) -> Decoder a -> Decoder b",
    "Json.Decode.oneOf" => "List (Decoder a) -> Decoder a",
    "Json.Decode.index" => "Int -> Decoder a -> Decoder a",
    "Json.Decode.at" => "List String -> Decoder a -> Decoder a",
    "Json.Decode.maybe" => "Decoder a -> Decoder (Maybe a)",
    "Json.Decode.nullable" => "Decoder a -> Decoder (Maybe a)",
    "Json.Decode.value" => "Decoder Value",
    "Json.Decode.null" => "a -> Decoder a",
    "Json.Decode.keyValuePairs" => "Decoder a -> Decoder (List (String, a))",
    "Json.Decode.dict" => "Decoder a -> Decoder (Dict String a)",
    "Json.Encode.dict" => "(comparable -> String) -> (a -> Value) -> Dict comparable a -> Value",
    "Dict.empty" => "Dict k v",
    "Dict.singleton" => "comparable -> v -> Dict comparable v",
    "Dict.insert" => "comparable -> v -> Dict comparable v -> Dict comparable v",
    "Dict.update" => "comparable -> (Maybe v -> Maybe v) -> Dict comparable v -> Dict comparable v",
    "Dict.remove" => "comparable -> Dict comparable v -> Dict comparable v",
    "Dict.isEmpty" => "Dict k v -> Bool",
    "Dict.member" => "comparable -> Dict comparable v -> Bool",
    "Dict.get" => "comparable -> Dict comparable v -> Maybe v",
    "Dict.size" => "Dict k v -> Int",
    "Dict.keys" => "Dict k v -> List k",
    "Dict.values" => "Dict k v -> List v",
    "Dict.toList" => "Dict k v -> List (k, v)",
    "Dict.fromList" => "List (comparable, v) -> Dict comparable v",
    "Dict.map" => "(k -> a -> b) -> Dict k a -> Dict k b",
    "Dict.foldl" => "(k -> v -> b -> b) -> b -> Dict k v -> b",
    "Dict.foldr" => "(k -> v -> b -> b) -> b -> Dict k v -> b",
    "Dict.filter" => "(comparable -> v -> Bool) -> Dict comparable v -> Dict comparable v",
    "Dict.union" => "Dict comparable v -> Dict comparable v -> Dict comparable v",
    "Dict.intersect" => "Dict comparable v -> Dict comparable v -> Dict comparable v",
    "Dict.diff" => "Dict comparable v -> Dict comparable v -> Dict comparable v",
    "Dict.merge" =>
      "(comparable -> a -> result -> result) -> (comparable -> a -> b -> result -> result) -> (comparable -> b -> result -> result) -> Dict comparable a -> Dict comparable b -> result -> result",
    "Dict.partition" =>
      "(comparable -> v -> Bool) -> Dict comparable v -> (Dict comparable v, Dict comparable v)",
    "Set.empty" => "Set a",
    "Set.singleton" => "comparable -> Set comparable",
    "Set.insert" => "comparable -> Set comparable -> Set comparable",
    "Set.remove" => "comparable -> Set comparable -> Set comparable",
    "Set.isEmpty" => "Set a -> Bool",
    "Set.member" => "comparable -> Set comparable -> Bool",
    "Set.size" => "Set a -> Int",
    "Set.toList" => "Set a -> List a",
    "Set.fromList" => "List comparable -> Set comparable",
    "Set.map" => "(comparable -> comparable2) -> Set comparable -> Set comparable2",
    "Set.foldl" => "(a -> b -> b) -> b -> Set a -> b",
    "Set.union" => "Set comparable -> Set comparable -> Set comparable",
    "Set.intersect" => "Set comparable -> Set comparable -> Set comparable",
    "Set.diff" => "Set comparable -> Set comparable -> Set comparable",
    "Set.filter" => "(comparable -> Bool) -> Set comparable -> Set comparable",
    "Set.partition" => "(comparable -> Bool) -> Set comparable -> (Set comparable, Set comparable)",
    "Array.empty" => "Array a",
    "Array.initialize" => "Int -> (Int -> a) -> Array a",
    "Array.repeat" => "Int -> a -> Array a",
    "Array.fromList" => "List a -> Array a",
    "Array.isEmpty" => "Array a -> Bool",
    "Array.length" => "Array a -> Int",
    "Array.get" => "Int -> Array a -> Maybe a",
    "Array.set" => "Int -> a -> Array a -> Array a",
    "Array.push" => "a -> Array a -> Array a",
    "Array.append" => "Array a -> Array a -> Array a",
    "Array.toList" => "Array a -> List a",
    "Array.map" => "(a -> b) -> Array a -> Array b",
    "Array.foldl" => "(a -> b -> b) -> b -> Array a -> b",
    "Array.foldr" => "(a -> b -> b) -> b -> Array a -> b",
    "Array.indexedMap" => "(Int -> a -> b) -> Array a -> Array b",
    "Array.filter" => "(a -> Bool) -> Array a -> Array a",
    "Array.slice" => "Int -> Int -> Array a -> Array a",
    "Array.toIndexedList" => "Array a -> List (Int, a)",
    "Task.succeed" => "a -> Task x a",
    "Task.fail" => "x -> Task x a",
    "Task.map" => "(a -> b) -> Task x a -> Task x b",
    "Task.andThen" => "(a -> Task x b) -> Task x a -> Task x b",
    "Task.mapError" => "(x -> y) -> Task x a -> Task y a",
    "Task.onError" => "(x -> Task y a) -> Task x a -> Task y a",
    "Task.sequence" => "List (Task x a) -> Task x (List a)",
    "Task.perform" => "(a -> msg) -> Task Never a -> Cmd msg",
    "Task.attempt" => "(Result x a -> msg) -> Task x a -> Cmd msg",
    "Task.map2" => "(a -> b -> result) -> Task x a -> Task x b -> Task x result",
    "Task.map3" => "(a -> b -> c -> result) -> Task x a -> Task x b -> Task x c -> Task x result",
    "Process.sleep" => "Float -> Task x ()",
    "Process.spawn" => "Task x a -> Task y Id",
    "Process.kill" => "Id -> Task x ()",
    "Time.now" => "Task x Posix",
    "Time.posixToMillis" => "Posix -> Int",
    "Time.millisToPosix" => "Int -> Posix",
    "Time.toYear" => "Zone -> Posix -> Int",
    "Time.toMonth" => "Zone -> Posix -> Month",
    "Time.toDay" => "Zone -> Posix -> Int",
    "Time.toWeekday" => "Zone -> Posix -> Weekday",
    "Time.toHour" => "Zone -> Posix -> Int",
    "Time.toMinute" => "Zone -> Posix -> Int",
    "Time.toSecond" => "Zone -> Posix -> Int",
    "Time.toMillis" => "Zone -> Posix -> Int",
    "Time.utc" => "Zone",
    "Time.here" => "Task x Zone",
    "Time.every" => "Float -> (Posix -> msg) -> Sub msg",
    "Random.int" => "Int -> Int -> Generator Int",
    "Random.float" => "Float -> Float -> Generator Float",
    "Random.uniform" => "a -> List a -> Generator a",
    "Random.weighted" => "(Float, a) -> List (Float, a) -> Generator a",
    "Random.list" => "Int -> Generator a -> Generator (List a)",
    "Random.pair" => "Generator a -> Generator b -> Generator (a, b)",
    "Random.map" => "(a -> b) -> Generator a -> Generator b",
    "Random.map2" => "(a -> b -> c) -> Generator a -> Generator b -> Generator c",
    "Random.andThen" => "(a -> Generator b) -> Generator a -> Generator b",
    "Random.constant" => "a -> Generator a",
    "Random.generate" => "(a -> msg) -> Generator a -> Cmd msg",
    "Random.map3" =>
      "(a -> b -> c -> d) -> Generator a -> Generator b -> Generator c -> Generator d",
    "Random.step" => "Generator a -> Seed -> (a, Seed)",
    "Random.initialSeed" => "Int -> Seed",
    "Random.independentSeed" => "Generator Seed",
    "Platform.worker" =>
      "{ init : flags -> (model, Cmd msg), update : msg -> model -> (model, Cmd msg), subscriptions : model -> Sub msg } -> Program flags model msg"
  }

  @constructors [
    {"True", "Bool", 0, "Bool"},
    {"False", "Bool", 0, "Bool"},
    {"Just", "Maybe", 1, "a -> Maybe a"},
    {"Nothing", "Maybe", 0, "Maybe a"},
    {"Ok", "Result", 1, "a -> Result x a"},
    {"Err", "Result", 1, "x -> Result x a"},
    {"LT", "Order", 0, "Order"},
    {"EQ", "Order", 0, "Order"},
    {"GT", "Order", 0, "Order"},
    {"::", "List", 2, "a -> List a -> List a"},
    {"[]", "List", 0, "List a"},
    {"Jan", "Month", 0, "Month"},
    {"Feb", "Month", 0, "Month"},
    {"Mar", "Month", 0, "Month"},
    {"Apr", "Month", 0, "Month"},
    {"May", "Month", 0, "Month"},
    {"Jun", "Month", 0, "Month"},
    {"Jul", "Month", 0, "Month"},
    {"Aug", "Month", 0, "Month"},
    {"Sep", "Month", 0, "Month"},
    {"Oct", "Month", 0, "Month"},
    {"Nov", "Month", 0, "Month"},
    {"Dec", "Month", 0, "Month"},
    {"Mon", "Weekday", 0, "Weekday"},
    {"Tue", "Weekday", 0, "Weekday"},
    {"Wed", "Weekday", 0, "Weekday"},
    {"Thu", "Weekday", 0, "Weekday"},
    {"Fri", "Weekday", 0, "Weekday"},
    {"Sat", "Weekday", 0, "Weekday"},
    {"Sun", "Weekday", 0, "Weekday"}
  ]

  @spec install(Env.t()) :: Env.t()
  def install(env) do
    env
    |> install_opaques()
    |> install_signatures()
    |> install_constructors()
    |> install_short_aliases()
    |> ElmEx.Typesys.Kernel.Pebble.install()
    |> ElmEx.Typesys.Kernel.Web.install()
    |> ElmEx.Typesys.Kernel.Parser.install()
    |> Env.harvest_named_arities()
    |> ensure_known_arities()
  end

  @spec ensure_known_arities(Env.t()) :: Env.t()
  def ensure_known_arities(env), do: install_known_arities(env)

  # Import qualification rewrites `Decoder` to `Json.Decode.Decoder`. Keep
  # those qualified names at the same arity harvest saw on the short name.
  @known_arities %{
    "Decoder" => 1,
    "Json.Decode.Decoder" => 1,
    "Encoder" => 1,
    "Json.Encode.Encoder" => 1,
    "Dict" => 2,
    "Dict.Dict" => 2,
    "Set" => 1,
    "Set.Set" => 1,
    "Task" => 2,
    "Task.Task" => 2,
    "Html" => 1,
    "Html.Html" => 1,
    "Html.Attribute" => 1,
    "Attribute" => 1,
    "Svg" => 1,
    "Svg.Svg" => 1,
    "Program" => 3,
    "Array" => 1,
    "Array.Array" => 1,
    "Bytes" => 0,
    "Bytes.Encode.Encoder" => 0,
    "File" => 0,
    "Url" => 0
  }

  defp install_known_arities(env) do
    types =
      Enum.reduce(@known_arities, env.types, fn {name, arity}, types ->
        case Map.get(types, name) do
          nil ->
            Map.put(types, name, %{arity: arity, kind: :opaque})

          %{arity: existing} = info when arity > existing ->
            Map.put(types, name, %{info | arity: arity})

          _ ->
            types
        end
      end)

    %{env | types: types}
  end

  # Official elm/time `Posix` / `Zone` are opaque. Some Pebble stubs rewrite
  # them as `type alias Posix = Int`; do not let that leak into port JSON-ability.
  @opaques ~w(Posix Time.Posix Zone Time.Zone Process.Id)

  defp install_opaques(env) do
    Enum.reduce(@opaques, env, fn name, acc ->
      Map.update!(acc, :types, &Map.put(&1, name, %{arity: 0, kind: :opaque}))
    end)
  end

  defp install_signatures(env) do
    Enum.reduce(@signatures, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} ->
          scheme = Env.generalize(acc, type)
          short = short_name(name)

          acc = Env.put_value(acc, name, scheme)

          if default_unqualified?(name) and is_nil(Env.lookup_value(acc, short)) do
            Env.put_value(acc, short, scheme)
          else
            acc
          end

        {:error, _} ->
          acc
      end
    end)
  end

  defp install_constructors(env) do
    Enum.reduce(@constructors, env, fn {name, union, arity, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} ->
          scheme = Env.generalize(acc, type)

          info = %{
            name: name,
            union: union,
            arity: arity,
            scheme: scheme
          }

          acc =
            acc
            |> Map.update!(:constructors, fn ctors ->
              ctors
              |> Map.put(name, info)
              |> Map.put("#{union}.#{name}", info)
              |> maybe_put_ctor_alias(union, name, info)
            end)
            |> Env.put_value(name, scheme)
            |> Env.put_value("#{union}.#{name}", scheme)

          maybe_put_ctor_value(acc, union, name, scheme)

        {:error, _} ->
          acc
      end
    end)
  end

  defp install_short_aliases(env) do
    aliases = %{
      "Cmd.none" => "Platform.Cmd.none",
      "Cmd.batch" => "Platform.Cmd.batch",
      "Cmd.map" => "Platform.Cmd.map",
      "Sub.none" => "Platform.Sub.none",
      "Sub.batch" => "Platform.Sub.batch",
      "Sub.map" => "Platform.Sub.map",
      "__add__" => "(+)",
      "__sub__" => "(-)",
      "__mul__" => "(*)",
      "__fdiv__" => "(/)",
      "__idiv__" => "(//)",
      "__pow__" => "(^)",
      "__append__" => "(++)",
      "__cons__" => "(::)",
      "List.cons" => "(::)",
      "Elm.Kernel.List.cons" => "(::)",
      "__eq__" => "(==)",
      "__neq__" => "(/=)",
      "__lt__" => "(<)",
      "__lte__" => "(<=)",
      "__gt__" => "(>)",
      "__gte__" => "(>=)",
      "<|" => "(<|)",
      "|>" => "(|>)",
      "<<" => "(<<)",
      ">>" => "(>>)",
      "^" => "(^)"
    }

    Enum.reduce(aliases, env, fn {short, long}, acc ->
      case Env.lookup_value(acc, long) do
        nil -> acc
        scheme -> Env.put_value(acc, short, scheme)
      end
    end)
  end

  defp short_name(name) do
    case String.split(name, ".") do
      [single] -> single
      parts -> List.last(parts)
    end
  end

  # Default imports: Basics exposing (..), operators, not List.map / Dict.get.
  defp default_unqualified?(name) do
    String.starts_with?(name, "Basics.") or String.starts_with?(name, "(")
  end

  defp maybe_put_ctor_alias(ctors, union, name, info) when union in ["Month", "Weekday"] do
    Map.put(ctors, "Time.#{name}", info)
  end

  defp maybe_put_ctor_alias(ctors, _union, _name, _info), do: ctors

  defp maybe_put_ctor_value(env, union, name, scheme) when union in ["Month", "Weekday"] do
    Env.put_value(env, "Time.#{name}", scheme)
  end

  defp maybe_put_ctor_value(env, _union, _name, _scheme), do: env
end
