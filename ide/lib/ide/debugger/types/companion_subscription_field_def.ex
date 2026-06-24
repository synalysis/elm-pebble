defmodule Ide.Debugger.Types.CompanionSubscriptionFieldDef do
  @moduledoc """
  Companion subscription injection field metadata from `CompanionSubscriptionTrigger`.

  Contract tables use **atom keys** in Elixir; simulator form payloads stringify them.
  """

  @type field_type :: :boolean | :integer | :string

  @type t :: %{
          required(:key) => String.t(),
          required(:label) => String.t(),
          required(:type) => field_type(),
          optional(:setting) => String.t(),
          required(:default) => boolean() | integer() | String.t()
        }
end
