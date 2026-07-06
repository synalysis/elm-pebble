defmodule Ide.Test.TemplateElmxElmcParity.ExecutionPlan do
  @moduledoc false

  alias Ide.Debugger.CompileContract
  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Test.TemplateElmxElmcParity.Scaffold

  @type step_op :: :init | :update | :view | :subscriptions
  @type step :: %{
          required(:id) => String.t(),
          required(:op) => step_op(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => map() | nil,
          optional(:source) => String.t()
        }

  @type t :: %{
          required(:template_key) => String.t(),
          required(:watch_profile_id) => String.t(),
          required(:contract) => map(),
          required(:steps) => [step()]
        }

  @spec build!(String.t(), String.t(), keyword()) :: t()
  def build!(project_dir, template_key, opts \\ [])
      when is_binary(project_dir) and is_binary(template_key) do
    watch_profile_id = "basalt"

    contract =
      case Keyword.get(opts, :contract) do
        %{} = contract ->
          contract

        nil ->
          case CompileContract.build_for_project_dir(project_dir) do
            {:ok, contract} -> contract
            {:error, reason} -> raise "compile contract failed for #{template_key}: #{inspect(reason)}"
          end
      end

    update_branches = list_field(contract, "update_case_branches")

    from_phone_ctors = from_phone_update_constructors(update_branches)

    update_steps =
      update_branches
      |> Enum.reject(fn branch ->
        branch == "FromPhone" or String.starts_with?(branch, "FromPhone ")
      end)
      |> Enum.map(fn branch ->
        %{
          id: "update:#{branch}",
          op: :update,
          message: branch,
          message_value: default_message_value(branch, contract),
          source: "update_case_branch"
        }
      end)

    phone_steps =
      if MapSet.size(from_phone_ctors) > 0 do
        project_dir
        |> phone_to_watch_steps(contract)
        |> Enum.filter(fn step ->
          inner = get_in(step.message_value, ["args", Access.at(0), "ctor"])
          is_binary(inner) and MapSet.member?(from_phone_ctors, inner)
        end)
      else
        []
      end
    subscription_steps = subscription_catalog_steps(contract)

    update_messages =
      update_steps
      |> Enum.map(& &1.message)
      |> MapSet.new()

    subscription_steps =
      Enum.reject(subscription_steps, fn step ->
        MapSet.member?(update_messages, step.message)
      end)

    steps =
      [
        %{id: "init", op: :init},
        %{id: "view:init", op: :view},
        %{id: "subscriptions:init", op: :subscriptions}
      ] ++
        expand_update_block(update_steps ++ phone_steps ++ subscription_steps)

    %{
      template_key: template_key,
      watch_profile_id: watch_profile_id,
      contract: contract,
      steps: steps
    }
  end

  @spec for_watch_profile(t(), String.t()) :: t()
  def for_watch_profile(%{} = plan, watch_profile_id) when is_binary(watch_profile_id) do
    %{plan | watch_profile_id: watch_profile_id}
  end

  @doc """
  Init plus repeated `DownPressed` updates without walking the full update-branch catalog.

  Simulates pressing the Down button in the emulator/debugger on a fresh Elmtris game.
  """
  @spec game_elmtris_down_button_scenario!(String.t(), keyword()) :: t()
  def game_elmtris_down_button_scenario!(project_dir, opts \\ [])
      when is_binary(project_dir) do
    template_key = Keyword.get(opts, :template_key, "game-elmtris")
    presses = Keyword.get(opts, :down_presses, 8)
    base = build!(project_dir, template_key, opts)

    down_steps =
      1..presses
      |> Enum.map(fn index ->
        %{
          id: "update:DownPressed:#{index}",
          op: :update,
          message: "DownPressed",
          message_value: nil,
          source: "down_button_scenario"
        }
      end)

    init_block = [
      %{id: "init", op: :init},
      %{id: "view:init", op: :view},
      %{id: "subscriptions:init", op: :subscriptions}
    ]

    %{base | steps: init_block ++ expand_update_block(down_steps)}
  end

  defp expand_update_block(steps) when is_list(steps) do
    Enum.flat_map(steps, fn step ->
      [
        step,
        %{id: "view:#{step.id}", op: :view},
        %{id: "subscriptions:#{step.id}", op: :subscriptions}
      ]
    end)
  end

  defp subscription_catalog_steps(contract) do
    contract
    |> TriggerCandidates.for_surface("watch")
    |> Enum.filter(fn row ->
      trigger = row_string(row, :trigger)
      message = row_string(row, :message)

      trigger != "" and message != "" and
        not SubscriptionTriggerWire.opaque_gateway_trigger?(trigger)
    end)
    |> Enum.map(fn row ->
      message = row_string(row, :message)

      %{
        id: "update:subscription:#{row_string(row, :trigger)}:#{message}",
        op: :update,
        message: message,
        message_value: subscription_message_value(message),
        source: "subscription_catalog"
      }
    end)
    |> Enum.uniq_by(& &1.message)
  end

  defp from_phone_update_constructors(branches) when is_list(branches) do
    branches
    |> Enum.filter(&String.starts_with?(&1, "FromPhone "))
    |> Enum.map(fn branch ->
      branch
      |> String.replace_prefix("FromPhone ", "")
      |> String.split(~r/\s|\(/, parts: 2)
      |> List.first()
    end)
    |> MapSet.new()
  end

  defp phone_to_watch_steps(project_dir, _contract) do
    with path when is_binary(path) <- Scaffold.phone_to_watch_path(project_dir),
         ctors when ctors != [] <- parse_phone_to_watch_constructors(path) do
      Enum.map(ctors, fn {name, sample_value} ->
        %{
          id: "update:FromPhone:#{name}",
          op: :update,
          message: "FromPhone",
          message_value: Corpus.companion_from_phone_value(name, sample_value),
          source: "phone_to_watch"
        }
      end)
    else
      _ -> []
    end
  end

  defp parse_phone_to_watch_constructors(path) do
    source = File.read!(path)

    with [block | _] <-
           Regex.run(
             ~r/type PhoneToWatch[^\n]*\n((?:\s*(?:\||=)[^\n]+\n?)+)/,
             source
           ) do
      block
      |> String.split("|")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.trim_leading/1)
      |> Enum.map(&String.replace_prefix(&1, "= ", ""))
      |> Enum.map(&parse_phone_ctor_line/1)
      |> Enum.reject(&is_nil/1)
    else
      _ -> []
    end
  end

  defp parse_phone_ctor_line(line) do
    case Regex.run(~r/^([A-Za-z][A-Za-z0-9_']*)(?:\s+(.+))?$/, line) do
      [_, name, args] ->
        {name, sample_args(args)}

      [_, name] ->
        {name, []}

      _ ->
        nil
    end
  end

  defp sample_args(args_line) when is_binary(args_line) do
    args_line
    |> split_type_tokens()
    |> Enum.map(&sample_type_arg/1)
  end

  defp split_type_tokens(line) do
    split_type_tokens(String.trim(line), 0, false, "", [])
    |> Enum.reverse()
  end

  defp split_type_tokens("", _depth, _in_parens, current, acc) do
    case String.trim(current) do
      "" -> acc
      token -> [token | acc]
    end
  end

  defp split_type_tokens(<<char, rest::binary>>, depth, in_parens, current, acc) do
    case {char, depth, in_parens} do
      {?(, _, false} ->
        split_type_tokens(rest, depth + 1, true, current <> <<char>>, acc)

      {?(, _, true} ->
        split_type_tokens(rest, depth + 1, true, current <> <<char>>, acc)

      {?), 1, true} ->
        split_type_tokens(rest, depth - 1, false, current <> <<char>>, acc)

      {?), depth, true} when depth > 1 ->
        split_type_tokens(rest, depth - 1, true, current <> <<char>>, acc)

      {?\s, 0, false} ->
        split_type_tokens(rest, depth, false, "", finalize_type_token(acc, current))

      _ ->
        split_type_tokens(rest, depth, in_parens, current <> <<char>>, acc)
    end
  end

  defp finalize_type_token(acc, current) do
    case String.trim(current) do
      "" -> acc
      token -> [token | acc]
    end
  end

  defp sample_type_arg("Int"), do: 0
  defp sample_type_arg("String"), do: "parity"
  defp sample_type_arg("Bool"), do: true
  defp sample_type_arg("(List Int)"), do: sample_piece_coords()
  defp sample_type_arg("List Int"), do: sample_piece_coords()
  defp sample_type_arg(type), do: %{"ctor" => type, "args" => []}

  defp sample_piece_coords, do: [0, 3, -3, -5, -35, -28, -43, 3, -43, 3]

  defp default_message_value(message, contract) do
    ctor = message |> String.trim() |> String.split(~r/\s+/, parts: 2) |> List.first()

    case Map.get(Map.get(contract, "msg_constructor_arities") || %{}, ctor) do
      0 ->
        nil

      _ ->
        if wildcard_update_branch?(message) do
          nil
        else
          Ide.Test.TemplateElmxElmcParity.ExecutionPlan.TimelineMessageValue.sample_for_ctor(ctor)
        end
    end
  end

  defp wildcard_update_branch?(message) when is_binary(message) do
    String.match?(String.trim(message), ~r/ _\z/)
  end

  defp wildcard_update_branch?(_), do: false

  defp subscription_message_value(message) do
    Ide.Test.TemplateElmxElmcParity.ExecutionPlan.TimelineMessageValue.sample_for_message(message)
  end

  defp list_field(map, key) when is_map(map) do
    map
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp row_string(row, key) do
    row
    |> TriggerCandidates.row_field(key)
    |> case do
      nil -> ""
      value -> to_string(value)
    end
  end
end

defmodule Ide.Test.TemplateElmxElmcParity.ExecutionPlan.TimelineMessageValue do
  @moduledoc false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus

  @spec sample_for_ctor(String.t()) :: map() | nil
  def sample_for_ctor("CurrentDateTime") do
    %{
      "year" => 2026,
      "month" => 7,
      "day" => 1,
      "dayOfWeek" => %{"ctor" => "Wednesday", "args" => []},
      "hour" => 10,
      "minute" => 30,
      "second" => 0,
      "utcOffsetMinutes" => 120
    }
  end

  def sample_for_ctor("CurrentTime"), do: %{"hour" => 10, "min" => 30}
  def sample_for_ctor("CurrentTimeString"), do: "10:30"
  def sample_for_ctor("MinuteChanged"), do: 0
  def sample_for_ctor("AnimationFinished"), do: 1
  def sample_for_ctor("HourChanged"), do: 10
  def sample_for_ctor("SecondChanged"), do: 0
  def sample_for_ctor("BatteryLevelChanged"), do: 80
  def sample_for_ctor("ConnectionChanged"), do: true
  def sample_for_ctor("ConnectionStatusChanged"), do: true
  def sample_for_ctor("GotBatteryLevel"), do: 80
  def sample_for_ctor("GotConnectionStatus"), do: true
  def sample_for_ctor("GotHealthSupported"), do: true
  def sample_for_ctor("GotStepsToday"), do: 5000
  def sample_for_ctor("HealthEvent"), do: %{"ctor" => "SignificantUpdate", "args" => []}
  def sample_for_ctor("ButtonUp"), do: nil
  def sample_for_ctor("ButtonDown"), do: nil
  def sample_for_ctor("ButtonSelect"), do: nil
  def sample_for_ctor(_), do: nil

  @spec sample_for_message(String.t()) :: map() | nil
  def sample_for_message(message) when is_binary(message) do
    ctor =
      message
      |> String.trim()
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()

    sample_for_ctor(ctor)
  end
end
