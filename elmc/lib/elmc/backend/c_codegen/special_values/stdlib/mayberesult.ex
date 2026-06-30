defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.MaybeResult do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Maybe.withDefault", [default_val]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{
        op: :runtime_call,
        function: "elmc_maybe_with_default",
        args: [default_val, %{op: :var, name: "__m"}]
      }
    }

  def special_value_from_target("Maybe.map", [f]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{op: :runtime_call, function: "elmc_maybe_map", args: [f, %{op: :var, name: "__m"}]}
    }

  def special_value_from_target("Maybe.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__m"],
      body: %{
        op: :runtime_call,
        function: "elmc_maybe_and_then",
        args: [f, %{op: :var, name: "__m"}]
      }
    }

  def special_value_from_target("Result.map", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{op: :runtime_call, function: "elmc_result_map", args: [f, %{op: :var, name: "__r"}]}
    }

  def special_value_from_target("Result.mapError", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_map_error",
        args: [f, %{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Result.andThen", [f]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_and_then",
        args: [f, %{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Result.withDefault", [default_val]),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_with_default",
        args: [default_val, %{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Result.toMaybe", []),
    do: %{
      op: :lambda,
      args: ["__r"],
      body: %{
        op: :runtime_call,
        function: "elmc_result_to_maybe",
        args: [%{op: :var, name: "__r"}]
      }
    }

  def special_value_from_target("Maybe.withDefault", [
        default_val,
        %{
          op: :qualified_call,
          target: head_target,
          args: [
            %{
              op: :qualified_call,
              target: drop_target,
              args: [index, list]
            }
          ]
        }
      ])
      when head_target in ["List.head", "head"] and
             drop_target in ["List.drop", "drop"] do
    list_nth_maybe = %{
      op: :runtime_call,
      function: "elmc_list_nth_maybe",
      args: [list, index]
    }

    if int_list_with_default_fusion?(default_val) do
      %{
        op: :runtime_call,
        function: "elmc_list_nth_int_default_boxed",
        args: [list, index, default_val]
      }
    else
      %{
        op: :runtime_call,
        function: "elmc_maybe_with_default",
        args: [default_val, list_nth_maybe]
      }
    end
  end

  def special_value_from_target("Maybe.withDefault", [
        default_val,
        %{op: :runtime_call, function: "elmc_list_nth_maybe", args: [list, index]} = list_nth_maybe
      ]) do
    if int_list_with_default_fusion?(default_val) do
      %{
        op: :runtime_call,
        function: "elmc_list_nth_int_default_boxed",
        args: [list, index, default_val]
      }
    else
      %{
        op: :runtime_call,
        function: "elmc_maybe_with_default",
        args: [default_val, list_nth_maybe]
      }
    end
  end

  def special_value_from_target("Maybe.withDefault", [
        _default_val,
        %{op: :runtime_call, function: "elmc_list_nth_int_default_boxed"} = list_nth
      ]) do
    list_nth
  end

  def special_value_from_target("Maybe.withDefault", [default_val, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_with_default", args: [default_val, maybe]}

  def special_value_from_target("Maybe.map", [f, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_map", args: [f, maybe]}

  def special_value_from_target("Maybe.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_maybe_map2", args: [f, a, b]}

  def special_value_from_target("Maybe.andThen", [f, maybe]),
    do: %{op: :runtime_call, function: "elmc_maybe_and_then", args: [f, maybe]}

  # --- elm/core: Result ---
  def special_value_from_target("Result.map", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_map", args: [f, result]}

  def special_value_from_target("Result.mapError", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_map_error", args: [f, result]}

  def special_value_from_target("Result.andThen", [f, result]),
    do: %{op: :runtime_call, function: "elmc_result_and_then", args: [f, result]}

  def special_value_from_target("Result.withDefault", [default_val, result]),
    do: %{op: :runtime_call, function: "elmc_result_with_default", args: [default_val, result]}

  def special_value_from_target("Result.toMaybe", [result]),
    do: %{op: :runtime_call, function: "elmc_result_to_maybe", args: [result]}

  def special_value_from_target("Result.fromMaybe", [err, maybe]),
    do: %{op: :runtime_call, function: "elmc_result_from_maybe", args: [err, maybe]}


  def special_value_from_target(_target, _args), do: nil

  defp int_list_with_default_fusion?(%{op: :int_literal}), do: true
  defp int_list_with_default_fusion?(_), do: false
end
