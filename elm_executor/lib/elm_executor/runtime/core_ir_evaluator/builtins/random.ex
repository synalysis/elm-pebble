defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Random do
  @moduledoc false

  @min_int -2_147_483_648
  @max_int 2_147_483_647
  @debugger_seed 1_722_529

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("minint", [], _ops), do: {:ok, @min_int}
  def eval("maxint", [], _ops), do: {:ok, @max_int}
  def eval("initialseed", [seed], _ops) when is_integer(seed), do: {:ok, random_seed(seed)}

  def eval("step", [generator, seed], _ops), do: run_generator(generator, seed)

  def eval("generate", [tagger, generator], ops) do
    with {:ok, {value, _seed}} <- run_generator(generator, random_seed(@debugger_seed)),
         {:ok, message_value} <- ops.call.(tagger, [value]) do
      {:ok,
       %{
         "kind" => "cmd.random.generate",
         "package" => "elm/random",
         "message" => message_name(message_value),
         "message_value" => message_value,
         "value" => value
       }}
    end
  end

  def eval("int", [low, high], _ops) when is_integer(low) and is_integer(high),
    do: {:ok, %{"kind" => "random.generator", "type" => "int", "low" => low, "high" => high}}

  def eval("constant", [value], _ops),
    do: {:ok, %{"kind" => "random.generator", "type" => "constant", "value" => value}}

  def eval("map", [fun, generator], ops),
    do:
      {:ok,
       %{
         "kind" => "random.generator",
         "type" => "map",
         "fun" => fun,
         "generator" => generator,
         "ops" => ops
       }}

  def eval("map2", [fun, left, right], ops),
    do:
      {:ok,
       %{
         "kind" => "random.generator",
         "type" => "map2",
         "fun" => fun,
         "left" => left,
         "right" => right,
         "ops" => ops
       }}

  def eval("bool", [], _ops),
    do: {:ok, %{"kind" => "random.generator", "type" => "bool"}}

  def eval("list", [count, generator], _ops) when is_integer(count),
    do:
      {:ok,
       %{
         "kind" => "random.generator",
         "type" => "list",
         "count" => count,
         "generator" => generator
       }}

  def eval(_function_name, _values, _ops), do: :no_builtin

  defp run_generator(
         %{"kind" => "random.generator", "type" => "int", "low" => low, "high" => high},
         seed
       )
       when is_integer(low) and is_integer(high) do
    {raw, next_seed} = next(seed)
    lo = min(low, high)
    hi = max(low, high)
    span = max(1, hi - lo + 1)
    {:ok, {lo + Integer.mod(raw, span), next_seed}}
  end

  defp run_generator(
         %{"kind" => "random.generator", "type" => "constant", "value" => value},
         seed
       ),
       do: {:ok, {value, seed}}

  defp run_generator(%{"kind" => "random.generator", "type" => "bool"}, seed) do
    with {:ok, {value, next_seed}} <-
           run_generator(
             %{"kind" => "random.generator", "type" => "int", "low" => 0, "high" => 1},
             seed
           ) do
      {:ok, {value == 1, next_seed}}
    end
  end

  defp run_generator(%{"kind" => "random.generator", "type" => "map"} = generator, seed) do
    ops = Map.fetch!(generator, "ops")

    with {:ok, {value, next_seed}} <- run_generator(Map.fetch!(generator, "generator"), seed),
         {:ok, mapped} <- ops.call.(Map.fetch!(generator, "fun"), [value]) do
      {:ok, {mapped, next_seed}}
    end
  end

  defp run_generator(%{"kind" => "random.generator", "type" => "map2"} = generator, seed) do
    ops = Map.fetch!(generator, "ops")

    with {:ok, {left, left_seed}} <- run_generator(Map.fetch!(generator, "left"), seed),
         {:ok, {right, right_seed}} <- run_generator(Map.fetch!(generator, "right"), left_seed),
         {:ok, mapped} <- ops.call.(Map.fetch!(generator, "fun"), [left, right]) do
      {:ok, {mapped, right_seed}}
    end
  end

  defp run_generator(%{"kind" => "random.generator", "type" => "list"} = generator, seed) do
    count = max(0, Map.fetch!(generator, "count"))

    range = if count == 0, do: [], else: 1..count

    Enum.reduce_while(range, {:ok, {[], seed}}, fn _index, {:ok, {values, acc_seed}} ->
      case run_generator(Map.fetch!(generator, "generator"), acc_seed) do
        {:ok, {value, next_seed}} -> {:cont, {:ok, {[value | values], next_seed}}}
        other -> {:halt, other}
      end
    end)
    |> case do
      {:ok, {values, next_seed}} -> {:ok, {Enum.reverse(values), next_seed}}
      other -> other
    end
  end

  defp run_generator(_generator, _seed), do: :no_builtin

  defp random_seed(seed) when is_integer(seed),
    do: %{"kind" => "random.seed", "seed" => normalize(seed)}

  defp next(%{"kind" => "random.seed", "seed" => seed}) when is_integer(seed) do
    advanced = normalize(seed * 1_103_515_245 + 12_345)
    {advanced, random_seed(advanced)}
  end

  defp normalize(value) when is_integer(value) do
    normalized = Integer.mod(value, @max_int)
    if normalized <= 0, do: normalized + @max_int, else: normalized
  end

  defp message_name(%{"ctor" => ctor}) when is_binary(ctor), do: ctor
  defp message_name(_), do: "RandomGenerated"
end
