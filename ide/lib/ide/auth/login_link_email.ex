defmodule Ide.Auth.LoginLinkEmail do
  @moduledoc false

  import Swoosh.Email

  alias Ide.Auth
  alias Ide.Auth.Types, as: AuthTypes
  alias Ide.Auth.LoginLink
  alias Ide.Mailer

  @spec deliver(String.t(), String.t()) ::
          {:ok, AuthTypes.mail_delivery_response()} | {:error, AuthTypes.mail_delivery_error()}
  def deliver(email, raw_token) when is_binary(email) and is_binary(raw_token) do
    url = LoginLink.verify_url(raw_token)
    {from_name, from_address} = Auth.mail_from()

    email =
      new()
      |> from({from_name, from_address})
      |> to(email)
      |> subject("Log in to elm-pebble IDE")
      |> text_body("""
      Use this link to log in to the elm-pebble IDE:

      #{url}

      The link expires in #{Auth.login_link_ttl_days()} days and can only be used once.
      If you did not request this email, you can ignore it.
      """)
      |> html_body("""
      <p>Use the button below to log in to the elm-pebble IDE.</p>
      <p><a href="#{url}" style="display:inline-block;padding:12px 20px;background:#18181b;color:#fff;text-decoration:none;border-radius:8px;font-weight:600;">Log in</a></p>
      <p style="font-size:14px;color:#52525b;">Or copy this link into your browser:<br><a href="#{url}">#{url}</a></p>
      <p style="font-size:14px;color:#52525b;">This link expires in #{Auth.login_link_ttl_days()} days and works once. If you did not request it, you can ignore this email.</p>
      """)

    try do
      Mailer.deliver(email)
    catch
      :exit, {:bad_label, _} -> {:error, :invalid_email}
      :exit, reason -> {:error, reason}
    end
  end
end
