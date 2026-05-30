# Regenerate EffectAnalysis split from git monolith.
# Run from ide/: elixir scripts/split_effect_analysis.exs

root = Path.dirname(Path.dirname(Path.expand(__ENV__.file)))
repo_root = Path.dirname(root)
git_path = "ide/lib/ide/debugger/elm_introspect/effect_analysis.ex"
src = Path.join(root, "lib/ide/debugger/elm_introspect/effect_analysis.ex")

text =
  case System.cmd("git", ["show", "HEAD:#{git_path}"], cd: repo_root, stderr_to_stdout: true) do
    {body, 0} -> body
    {err, _} -> raise "read monolith from git failed: #{err}"
  end

lines = String.split(text, "\n", parts: :infinity)
lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines

support_common =
  """
    alias ElmEx.Frontend.Module
    alias Ide.Debugger.ElmIntrospect
    alias Ide.Debugger.ElmIntrospect.Types

  """

subscription_common = support_common

cmd_common =
  """
    alias ElmEx.Frontend.Module
    alias Ide.Debugger.ElmIntrospect
    alias Ide.Debugger.ElmIntrospect.Types
    alias Ide.Debugger.Types.CmdCall

  """

parent_common = cmd_common

wrap = fn name, body, extra ->
  mod = "Ide.Debugger.ElmIntrospect.EffectAnalysis.#{name}"

  """
  defmodule #{mod} do
    @moduledoc false

  #{extra}#{body}end
  """
end

to_body = fn slice -> Enum.map(slice, &(&1 <> "\n")) |> IO.iodata_to_binary() end

take_slices = fn slices ->
  Enum.flat_map(slices, fn {start, finish} ->
    Enum.slice(lines, start - 1, finish - start + 1)
  end)
end

support_slices = [
  {9, 15},
  {941, 961},
  {1027, 1052},
  {1087, 1088},
  {1091, 1231},
  {1234, 1235},
  {1237, 1239}
]
subscription_slices = [{232, 295}, {336, 466}, {470, 560}, {885, 938}]
cmd_slices = [{57, 229}, {298, 335}, {562, 883}, {1251, 1268}]
parent_slices = [{17, 55}, {964, 1023}, {1053, 1085}, {1240, 1250}]

support_body = take_slices.(support_slices) |> to_body.()
subscription_body = take_slices.(subscription_slices) |> to_body.()
cmd_body = take_slices.(cmd_slices) |> to_body.()
parent_body = take_slices.(parent_slices) |> to_body.()

support_public = [
  "view_type_name",
  "peel_lets",
  "init_case_subjects",
  "init_case_subject_allowed?",
  "update_case_subject_allowed?",
  "update_case_subjects",
  "peel_update_outer",
  "pattern_constructor_name",
  "inline_let_bindings",
  "expr_to_json_value"
]

support_body =
  Enum.reduce(support_public, support_body, fn name, acc ->
    String.replace(acc, "defp #{name}(", "def #{name}(")
  end)

support_cross = [
  {"peel_lets(", "Support.peel_lets("},
  {"init_case_subjects(", "Support.init_case_subjects("},
  {"init_case_subject_allowed?(", "Support.init_case_subject_allowed?("},
  {"update_case_subjects(", "Support.update_case_subjects("},
  {"update_case_subject_allowed?(", "Support.update_case_subject_allowed?("},
  {"peel_update_outer(", "Support.peel_update_outer("},
  {"view_type_name(", "Support.view_type_name("},
  {"pattern_constructor_name(", "Support.pattern_constructor_name("}
]

cmd_cross =
  support_cross ++
    [
      {"subscription_item_label(", "Subscriptions.subscription_item_label("},
      {"subscription_arg_snippet(", "Subscriptions.subscription_arg_snippet("},
      {"&subscription_arg_snippet/", "&Subscriptions.subscription_arg_snippet/"},
      {"inline_let_bindings(", "Support.inline_let_bindings("},
      {"expr_to_json_value(", "Support.expr_to_json_value("}
    ]

subscription_cross =
  support_cross ++
    [
      {"view_type_name(", "Support.view_type_name("},
      {"callback_constructor_from_args(", "CmdCalls.callback_constructor_from_args("},
      {"expr_arg_kind(", "CmdCalls.expr_arg_kind("},
      {"&expr_arg_kind/", "&CmdCalls.expr_arg_kind/"}
    ]

apply_cross = fn body, replacements ->
  Enum.reduce(replacements, body, fn {from, to}, acc -> String.replace(acc, from, to) end)
end

dedupe_cross = fn body ->
  body
  |> String.replace("Support.Support.", "Support.")
  |> String.replace("Subscriptions.Subscriptions.", "Subscriptions.")
  |> String.replace("CmdCalls.CmdCalls.", "CmdCalls.")
end

subscription_body =
  subscription_body
  |> apply_cross.(subscription_cross)
  |> dedupe_cross.()
  |> then(fn body ->
    Enum.reduce(
      [
        "extract_subscription_items",
        "subscription_call_rows",
        "subscription_item_label",
        "subscription_event_kind",
        "subscription_arg_snippet",
        "subscription_batch_target?",
        "maybe_if_branch_guards",
        "maybe_case_branch_guards",
        "guard_from_if_cond",
        "guard_from_case_branch",
        "subscription_guard_subject"
      ],
      body,
      fn name, acc -> String.replace(acc, "defp #{name}(", "def #{name}(")
    end)
  end)

cmd_body =
  cmd_body
  |> apply_cross.(cmd_cross)
  |> dedupe_cross.()
  |> then(fn body ->
    Enum.reduce(
      [
        "extract_cmd_op_items",
        "extract_cmd_calls",
        "callback_constructor_from_args",
        "callback_arg_count_from_args",
        "callback_arg_count_from_expr",
        "task_sources_from_args",
        "qualified_call_targets",
        "callback_preferred_over_result_mapper?",
        "callback_constructor_from_expr",
        "constructor_like_name?",
        "expr_arg_kind",
        "cmd_ops_from_case_branch_expr",
        "cmd_calls_from_case_branch_expr",
        "maybe_put_branch_constructor"
      ],
      body,
      fn name, acc -> String.replace(acc, "defp #{name}(", "def #{name}(")
    end)
  end)

parent_body =
  parent_body
  |> apply_cross.(support_cross)
  |> dedupe_cross.()
  |> String.replace("@spec ViewTreeEval.", "@spec ")
  |> String.replace("@spec Support.", "@spec ")
  |> String.replace("@spec Subscriptions.", "@spec ")
  |> String.replace("@spec CmdCalls.", "@spec ")

parent_body =
  Enum.reduce(
    ["main_kind_from_target", "init_model_expr", "first_case_branch_init_model"],
    parent_body,
    fn name, acc -> String.replace(acc, "defp #{name}(", "def #{name}(")
  end)

dir = Path.join(root, "lib/ide/debugger/elm_introspect/effect_analysis")
File.mkdir_p!(dir)

File.write!(
  Path.join(dir, "support.ex"),
  wrap.("Support", support_body, support_common)
)

File.write!(
  Path.join(dir, "subscriptions.ex"),
  wrap.(
    "Subscriptions",
    subscription_body,
    subscription_common <>
      """
        alias Ide.Debugger.ElmIntrospect.EffectAnalysis.CmdCalls
        alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Support

      """
  )
)

File.write!(
  Path.join(dir, "cmd_calls.ex"),
  wrap.(
    "CmdCalls",
    cmd_body,
    cmd_common <>
      """
        alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Subscriptions
        alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Support

      """
  )
)

facade_header = Enum.slice(lines, 0, 2) |> Enum.map(&(&1 <> "\n")) |> IO.iodata_to_binary()

facade =
  facade_header <>
    parent_common <>
    """
      alias Ide.Debugger.ElmIntrospect
      alias Ide.Debugger.ElmIntrospect.EffectAnalysis.CmdCalls
      alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Subscriptions
      alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Support
      alias Ide.Debugger.ElmIntrospect.Types

    """ <>
    parent_body <>
    """

      defdelegate function_cmd_calls(mod), to: CmdCalls
      defdelegate init_cmd_ops_outline(expr, init_params), to: CmdCalls
      defdelegate init_cmd_calls_outline(expr, init_params), to: CmdCalls
      defdelegate update_cmd_ops_outline(expr, update_params), to: CmdCalls
      defdelegate update_cmd_calls_outline(expr, update_params), to: CmdCalls
      defdelegate subscriptions_outline(expr, subscriptions_params), to: Subscriptions
      defdelegate extract_subscription_calls(expr, subscriptions_params), to: Subscriptions

      defdelegate extract_subscription_calls(expr, bindings, guards, subscriptions_params),
                  to: Subscriptions
    end
    """
    |> String.replace(
      "def init_model_value(expr, mod) do\n    expr\n    |> init_model_expr()\n    |> expr_to_json_value(0, 12, mod)\n  end",
      "def init_model_value(expr, mod) do\n    expr\n    |> init_model_expr()\n    |> Support.expr_to_json_value(0, 12, mod)\n  end"
    )
    |> String.replace(~r/  @spec peel_lets\(.*\n/, "")

File.write!(src, facade)
IO.puts("split complete")
