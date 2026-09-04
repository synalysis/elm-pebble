defmodule ElmEx.Typesys.Kernel.Parser do
  @moduledoc """
  Official elm/parser 1.1 schemes, including the `|=` / `|.` operators.
  """

  alias ElmEx.Typesys.{Env, Parser, Type}

  @parser "Parser.Parser"
  @step "Parser.Step"
  @trailing "Parser.Trailing"
  @nestable "Parser.Nestable"

  @signatures %{
    "Parser.succeed" => "a -> Parser.Parser a",
    "Parser.problem" => "String -> Parser.Parser a",
    "Parser.run" => "Parser.Parser a -> String -> Result (List DeadEnd) a",
    "Parser.int" => "Parser.Parser Int",
    "Parser.float" => "Parser.Parser Float",
    "Parser.number" =>
      "{ int : Maybe (Int -> a), hex : Maybe (Int -> a), octal : Maybe (Int -> a), binary : Maybe (Int -> a), float : Maybe (Float -> a) } -> Parser.Parser a",
    "Parser.spaces" => "Parser.Parser ()",
    "Parser.symbol" => "String -> Parser.Parser ()",
    "Parser.keyword" => "String -> Parser.Parser ()",
    "Parser.token" => "String -> Parser.Parser ()",
    "Parser.end" => "Parser.Parser ()",
    "Parser.lineComment" => "String -> Parser.Parser ()",
    "Parser.multiComment" => "String -> String -> Parser.Nestable -> Parser.Parser ()",
    "Parser.variable" =>
      "{ start : (Char -> Bool), inner : (Char -> Bool), reserved : Set String } -> Parser.Parser String",
    "Parser.sequence" =>
      "{ start : String, separator : String, end : String, spaces : Parser.Parser (), item : Parser.Parser a, trailing : Parser.Trailing } -> Parser.Parser (List a)",
    "Parser.oneOf" => "List (Parser.Parser a) -> Parser.Parser a",
    "Parser.map" => "(a -> b) -> Parser.Parser a -> Parser.Parser b",
    "Parser.andThen" => "(a -> Parser.Parser b) -> Parser.Parser a -> Parser.Parser b",
    "Parser.lazy" => "(() -> Parser.Parser a) -> Parser.Parser a",
    "Parser.backtrackable" => "Parser.Parser a -> Parser.Parser a",
    "Parser.commit" => "a -> Parser.Parser a",
    "Parser.loop" => "state -> (state -> Parser.Parser (Parser.Step state a)) -> Parser.Parser a",
    "Parser.getChompedString" => "Parser.Parser a -> Parser.Parser String",
    "Parser.chompIf" => "(Char -> Bool) -> Parser.Parser ()",
    "Parser.chompWhile" => "(Char -> Bool) -> Parser.Parser ()",
    "Parser.chompUntil" => "String -> Parser.Parser ()",
    "Parser.chompUntilEndOr" => "String -> Parser.Parser ()",
    "Parser.getOffset" => "Parser.Parser Int",
    "Parser.getSource" => "Parser.Parser String",
    "Parser.getRow" => "Parser.Parser Int",
    "Parser.getCol" => "Parser.Parser Int",
    "Parser.getPosition" => "Parser.Parser (Int, Int)",
    "|=" => "Parser.Parser (a -> b) -> Parser.Parser a -> Parser.Parser b",
    "|." => "Parser.Parser keep -> Parser.Parser ignore -> Parser.Parser keep",
    "Parser.|=" => "Parser.Parser (a -> b) -> Parser.Parser a -> Parser.Parser b",
    "Parser.|." => "Parser.Parser keep -> Parser.Parser ignore -> Parser.Parser keep"
  }

  @constructors [
    {"Parser.Forbidden", @trailing, 0, "Parser.Trailing"},
    {"Parser.Optional", @trailing, 0, "Parser.Trailing"},
    {"Parser.Mandatory", @trailing, 0, "Parser.Trailing"},
    {"Parser.Nestable", @nestable, 0, "Parser.Nestable"},
    {"Parser.NotNestable", @nestable, 0, "Parser.Nestable"},
    {"Parser.Loop", @step, 1, "state -> Parser.Step state a"},
    {"Parser.Done", @step, 1, "a -> Parser.Step state a"}
  ]

  @spec install(Env.t()) :: Env.t()
  def install(env) do
    env
    |> install_types()
    |> install_signatures()
    |> install_constructors()
  end

  defp install_types(env) do
    types =
      env.types
      |> Map.put_new(@parser, %{arity: 1, kind: :opaque})
      |> Map.put_new("Parser", %{arity: 1, kind: :opaque})
      |> Map.put_new(@step, %{arity: 2, kind: :union})
      |> Map.put_new(@trailing, %{arity: 0, kind: :union})
      |> Map.put_new(@nestable, %{arity: 0, kind: :union})
      |> Map.put_new("DeadEnd", %{arity: 0, kind: :opaque})
      |> Map.put_new("Parser.DeadEnd", %{arity: 0, kind: :opaque})

    env = %{env | types: types}

    Env.put_alias(env, "Parser", %{
      name: @parser,
      params: ["a"],
      body: Type.named(@parser, [Type.var(1)]),
      fields: %{}
    })
  end

  defp install_signatures(env) do
    Enum.reduce(@signatures, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} -> Env.put_value(acc, name, Env.generalize(acc, type))
        {:error, _} -> acc
      end
    end)
  end

  defp install_constructors(env) do
    Enum.reduce(@constructors, env, fn {name, union, arity, src}, acc ->
      install_one_ctor(acc, name, union, arity, src)
    end)
  end

  defp install_one_ctor(env, name, union, arity, src) do
    case Parser.parse(src) do
      {:ok, type} ->
        scheme = Env.generalize(env, type)
        info = %{name: name, union: union, arity: arity, scheme: scheme}

        env
        |> Map.update!(:constructors, &Map.put(&1, name, info))
        |> Env.put_value(name, scheme)
        |> maybe_put_short_ctor(name, info, scheme)

      {:error, _} ->
        env
    end
  end

  defp maybe_put_short_ctor(env, name, info, scheme) do
    short = name |> String.split(".") |> List.last()

    if short in ["Nestable", "NotNestable", "Forbidden", "Optional", "Mandatory"] do
      env
      |> Map.update!(:constructors, &Map.put(&1, short, info))
      |> Env.put_value(short, scheme)
    else
      env
    end
  end
end
