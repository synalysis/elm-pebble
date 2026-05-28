defmodule Ide.Debugger.SubscriptionGuards do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeModelHydrate
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.CmdCall

  @type guard :: CmdCall.activation_guard()
  @type guards :: :always | [guard()]

  @spec satisfied?(Types.runtime_state(), Types.surface_target(), [guard()]) :: boolean()
  def satisfied?(state, target, guards)
      when is_map(state) and target in [:watch, :companion, :phone] and is_list(guards) do
    Enum.all?(guards, &guard_satisfied?(state, target, &1))
  end

  def satisfied?(_state, _target, _guards), do: true

  @spec field_value(Types.runtime_state(), Types.surface_target(), String.t()) ::
          {:ok, Types.wire_input()} | :error
  def field_value(state, target, subject)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    ei = Surface.introspect(surface) || %{}
    subscriptions_params = IntrospectAccess.list(ei, "subscriptions_params")

    case runtime_field_key(subject, subscriptions_params) do
      "" ->
        :error

      field ->
        value =
          case Map.fetch(runtime_model, field) do
            {:ok, found} ->
              RuntimeModelHydrate.static_value(found)

            :error ->
              init =
                case Surface.introspect(surface) do
                  %{"init_model" => value} when is_map(value) -> value
                  _ -> %{}
                end

              RuntimeModelHydrate.static_value(Map.get(init, field))
          end

        {:ok, value}
    end
  end

  def field_value(_state, _target, _subject), do: :error

  @spec truthy?(Types.wire_input()) :: boolean()
  def truthy?(value) when is_boolean(value), do: value
  def truthy?(nil), do: false
  def truthy?(0), do: false
  def truthy?(%{"ctor" => "Nothing", "args" => []}), do: false
  def truthy?(%{"$ctor" => "Nothing", "$args" => []}), do: false

  def truthy?(%{"ctor" => "Just", "args" => [value]}), do: truthy?(value)
  def truthy?(%{"$ctor" => "Just", "$args" => [value]}), do: truthy?(value)

  def truthy?(value) when is_binary(value) do
    case RuntimeModelHydrate.normalize_boolean_string(value) do
      bool when is_boolean(bool) -> bool
      _ -> String.trim(value) != ""
    end
  end

  def truthy?(_value), do: true

  @spec branch_label(Types.wire_input()) :: String.t()
  def branch_label(value) when is_binary(value), do: value
  def branch_label(value) when is_atom(value), do: Atom.to_string(value)

  def branch_label(%{"ctor" => ctor, "args" => _}) when is_binary(ctor), do: ctor
  def branch_label(%{"$ctor" => ctor, "$args" => _}) when is_binary(ctor), do: ctor
  def branch_label(value), do: to_string(value)

  @spec guard_satisfied?(Types.runtime_state(), Types.surface_target(), guard()) :: boolean()
  defp guard_satisfied?(state, target, %{"kind" => "field_truthy", "subject" => subject})
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) do
    case field_value(state, target, subject) do
      {:ok, value} -> truthy?(value)
      _ -> false
    end
  end

  defp guard_satisfied?(state, target, %{"kind" => "field_falsy", "subject" => subject})
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) do
    case field_value(state, target, subject) do
      {:ok, value} -> not truthy?(value)
      _ -> false
    end
  end

  defp guard_satisfied?(state, target, %{
         "kind" => "case_branch",
         "subject" => subject,
         "branch" => branch
       })
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(subject) and
              is_binary(branch) do
    case field_value(state, target, subject) do
      {:ok, value} -> branch_label(value) == branch
      _ -> false
    end
  end

  defp guard_satisfied?(_state, _target, _guard), do: true

  @spec runtime_field_key(String.t(), Types.param_list()) :: String.t()
  defp runtime_field_key(subject, subscriptions_params)
       when is_binary(subject) and is_list(subscriptions_params) do
    Enum.find_value(subscriptions_params, fn param ->
      prefix = param <> "."

      if is_binary(param) and param != "_" and param != "" and String.starts_with?(subject, prefix) do
        String.replace_prefix(subject, prefix, "")
      end
    end) || ""
  end

  defp runtime_field_key(_subject, _subscriptions_params), do: ""

end
