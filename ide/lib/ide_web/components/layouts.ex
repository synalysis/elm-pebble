defmodule IdeWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use IdeWeb, :controller` and
  `use IdeWeb, :live_view`.
  """
  use IdeWeb, :html

  embed_templates "layouts/*"

  @spec header_account(map()) :: Ide.Auth.User.t() | nil
  def header_account(assigns) when is_map(assigns) do
    assigns[:current_user] || assigns[:firebase_account]
  end

  @spec firebase_logout?(map()) :: boolean()
  def firebase_logout?(assigns) when is_map(assigns) do
    assigns[:auth_mode] in [:local, :public_pebble] and not is_nil(header_account(assigns))
  end
end
