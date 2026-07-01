defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.List do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Helpers
  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("List.cons", []),
    do: %{
      op: :lambda,
      args: ["__head", "__tail"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_cons",
        args: [%{op: :var, name: "__head"}, %{op: :var, name: "__tail"}]
      }
    }

  def special_value_from_target("List.cons", [head]),
    do: %{
      op: :lambda,
      args: ["__tail"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_cons",
        args: [head, %{op: :var, name: "__tail"}]
      }
    }

  def special_value_from_target("List.cons", [head, tail]),
    do: %{op: :runtime_call, function: "elmc_list_cons", args: [head, tail]}

  def special_value_from_target("List.head", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_head", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.tail", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_tail", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.reverse", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_reverse", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.length", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_length", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.isEmpty", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_is_empty", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.sum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_sum", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.product", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_product", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.maximum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_maximum", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.minimum", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_minimum", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.sort", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_sort", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.concat", []),
    do: %{
      op: :lambda,
      args: ["__l"],
      body: %{op: :runtime_call, function: "elmc_list_concat", args: [%{op: :var, name: "__l"}]}
    }

  def special_value_from_target("List.head", [
        %{op: :call, target: {mod, "drop"}, args: [index, list]}
      ])
      when mod in ["List"],
      do: %{op: :runtime_call, function: "elmc_list_nth_maybe", args: [list, index]}

  def special_value_from_target("List.head", [
        %{op: :qualified_call, target: "List.filter", args: [pred, list]}
      ]),
      do: %{op: :runtime_call, function: "elmc_list_find_first", args: [pred, list]}

  def special_value_from_target("List.head", [
        %{op: :runtime_call, function: "elmc_list_filter", args: [pred, list]}
      ]),
      do: %{op: :runtime_call, function: "elmc_list_find_first", args: [pred, list]}

  def special_value_from_target("List.head", [
        %{op: :qualified_call, target: target, args: [index, list]}
      ])
      when target in ["List.drop", "drop"],
      do: %{op: :runtime_call, function: "elmc_list_nth_maybe", args: [list, index]}

  def special_value_from_target("List.head", [list]),
    do: %{op: :runtime_call, function: "elmc_list_head", args: [list]}

  def special_value_from_target("List.tail", [list]),
    do: %{op: :runtime_call, function: "elmc_list_tail", args: [list]}

  def special_value_from_target("List.isEmpty", [list]),
    do: %{op: :runtime_call, function: "elmc_list_is_empty", args: [list]}

  def special_value_from_target("List.length", [list]),
    do: %{op: :runtime_call, function: "elmc_list_length", args: [list]}

  def special_value_from_target("List.reverse", [list]),
    do: %{op: :runtime_call, function: "elmc_list_reverse", args: [list]}

  def special_value_from_target("List.member", [value, list]),
    do: %{op: :runtime_call, function: "elmc_list_member", args: [value, list]}

  def special_value_from_target("List.map", [f]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_map",
        args: [f, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.map", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_map", args: [f, list]}

  def special_value_from_target("List.filter", [f]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_filter",
        args: [f, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.filter", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_filter", args: [f, list]}

  def special_value_from_target("List.foldl", [f, acc, list]),
    do: %{op: :runtime_call, function: "elmc_list_foldl", args: [f, acc, list]}

  def special_value_from_target("List.foldl", []),
    do: Helpers.runtime_fn_lambda("elmc_list_foldl", ["__f", "__acc", "__list"])

  def special_value_from_target("List.foldl", [f, acc]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldl",
        args: [f, acc, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.foldl", [f]),
    do: %{
      op: :lambda,
      args: ["__acc", "__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldl",
        args: [f, %{op: :var, name: "__acc"}, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("Elm.Kernel.List.foldl", []),
    do: Helpers.runtime_fn_lambda("elmc_list_foldl", ["__f", "__acc", "__list"])

  def special_value_from_target("List.foldr", [f, acc, list]),
    do: %{op: :runtime_call, function: "elmc_list_foldr", args: [f, acc, list]}

  def special_value_from_target("List.foldr", []),
    do: Helpers.runtime_fn_lambda("elmc_list_foldr", ["__f", "__acc", "__list"])

  def special_value_from_target("List.foldr", [f, acc]),
    do: %{
      op: :lambda,
      args: ["__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldr",
        args: [f, acc, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.foldr", [f]),
    do: %{
      op: :lambda,
      args: ["__acc", "__list"],
      body: %{
        op: :runtime_call,
        function: "elmc_list_foldr",
        args: [f, %{op: :var, name: "__acc"}, %{op: :var, name: "__list"}]
      }
    }

  def special_value_from_target("List.append", [a, b]),
    do: %{op: :runtime_call, function: "elmc_list_append", args: [a, b]}

  def special_value_from_target("List.concat", [lists]),
    do: %{op: :runtime_call, function: "elmc_list_concat", args: [lists]}

  def special_value_from_target("List.concatMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_concat_map", args: [f, list]}

  def special_value_from_target("List.indexedMap", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_indexed_map", args: [f, list]}

  def special_value_from_target("List.filterMap", [f, list]) do
    f = Elmc.Backend.CCodegen.ListHofResolve.normalize_filter_map_fn(f)

    %{op: :runtime_call, function: "elmc_list_filter_map", args: [f, list]}
  end

  def special_value_from_target("List.sum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_sum", args: [list]}

  def special_value_from_target("List.product", [list]),
    do: %{op: :runtime_call, function: "elmc_list_product", args: [list]}

  def special_value_from_target("List.maximum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_maximum", args: [list]}

  def special_value_from_target("List.minimum", [list]),
    do: %{op: :runtime_call, function: "elmc_list_minimum", args: [list]}

  def special_value_from_target("List.any", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_any", args: [f, list]}

  def special_value_from_target("List.all", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_all", args: [f, list]}

  def special_value_from_target("List.sort", [list]),
    do: %{op: :runtime_call, function: "elmc_list_sort", args: [list]}

  def special_value_from_target("List.sortBy", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_sort_by", args: [f, list]}

  def special_value_from_target("List.sortWith", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_sort_with", args: [f, list]}

  def special_value_from_target("List.singleton", [value]),
    do: %{op: :runtime_call, function: "elmc_list_singleton", args: [value]}

  def special_value_from_target("List.range", [lo, hi]),
    do: %{op: :runtime_call, function: "elmc_list_range", args: [lo, hi]}

  def special_value_from_target("List.repeat", [n, value]),
    do: %{op: :runtime_call, function: "elmc_list_repeat", args: [n, value]}

  def special_value_from_target("List.take", [n, list]),
    do: %{op: :runtime_call, function: "elmc_list_take", args: [n, list]}

  def special_value_from_target("List.drop", [n, list]),
    do: %{op: :runtime_call, function: "elmc_list_drop", args: [n, list]}

  def special_value_from_target("List.partition", [f, list]),
    do: %{op: :runtime_call, function: "elmc_list_partition", args: [f, list]}

  def special_value_from_target("List.unzip", [list]),
    do: %{op: :runtime_call, function: "elmc_list_unzip", args: [list]}

  def special_value_from_target("List.intersperse", [sep, list]),
    do: %{op: :runtime_call, function: "elmc_list_intersperse", args: [sep, list]}

  def special_value_from_target("List.map2", [f, a, b]),
    do: %{op: :runtime_call, function: "elmc_list_map2", args: [f, a, b]}

  def special_value_from_target("List.map3", [f, a, b, c]),
    do: %{op: :runtime_call, function: "elmc_list_map3", args: [f, a, b, c]}

  def special_value_from_target("List.map4", [f, a, b, c, d]),
    do: %{op: :runtime_call, function: "elmc_list_map4", args: [f, a, b, c, d]}

  def special_value_from_target("List.map5", [f, a, b, c, d, e]),
    do: %{op: :runtime_call, function: "elmc_list_map5", args: [f, a, b, c, d, e]}


  def special_value_from_target(_target, _args), do: nil
end
