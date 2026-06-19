defmodule Ide.Auth.Email do
  @moduledoc """
  Magic-link email authentication for `public_custom` IDE mode.
  """

  import Ecto.Query

  alias Ide.Auth.EmailHash
  alias Ide.Auth.LoginLink
  alias Ide.Auth.LoginLinkEmail
  alias Ide.Auth.EmailAddress
  alias Ide.Auth.LoginToken
  alias Ide.Auth.User
  alias Ide.Repo

  @spec send_login_link(String.t()) ::
          :ok | {:error, :invalid_email | :mailer_not_configured | :delivery_failed}
  def send_login_link(email) when is_binary(email) do
    email = User.normalize_email(email)

    if valid_email?(email) do
      with :ok <- ensure_mailer_ready(),
           {:ok, user} <- ensure_user(email),
           {:ok, raw_token} <- issue_token(user),
           {:ok, _} <- LoginLinkEmail.deliver(email, raw_token) do
        :ok
      else
        {:error, %Ecto.Changeset{}} ->
          {:error, :invalid_email}

        {:error, :mailer_not_configured} = error ->
          error

        {:error, :invalid_email} = error ->
          error

        {:error, reason} ->
          require Logger

          Logger.error(
            "login email delivery failed email_hash=#{String.slice(EmailHash.hash(email), 0, 12)} reason=#{inspect(reason)} mailer=#{mailer_adapter_label()}"
          )

          {:error, :delivery_failed}
      end
    else
      {:error, :invalid_email}
    end
  end

  def send_login_link(_), do: {:error, :invalid_email}

  @doc """
  True when production mail can be sent (SMTP adapter configured).
  """
  @spec mail_delivery_configured?() :: boolean()
  def mail_delivery_configured? do
    case mailer_adapter() do
      Swoosh.Adapters.SMTP -> true
      Swoosh.Adapters.Test -> true
      Swoosh.Adapters.Local -> Application.get_env(:swoosh, :local) != false
      _ -> false
    end
  end

  @spec ensure_mailer_ready() :: :ok | {:error, :mailer_not_configured}
  defp ensure_mailer_ready do
    if mail_delivery_configured?() do
      :ok
    else
      require Logger

      Logger.error(
        "login email requested but mail delivery is not configured adapter=#{mailer_adapter_label()}"
      )

      {:error, :mailer_not_configured}
    end
  end

  @spec mailer_adapter() :: module()
  defp mailer_adapter do
    Application.get_env(:ide, Ide.Mailer, [])
    |> Keyword.get(:adapter, Swoosh.Adapters.Local)
  end

  @spec mailer_adapter_label() :: String.t()
  defp mailer_adapter_label do
    mailer_adapter() |> Module.split() |> List.last()
  end

  @spec verify_login_token(String.t()) ::
          {:ok, User.t()} | {:error, :invalid_token | :expired_token | :used_token}
  def verify_login_token(raw_token) when is_binary(raw_token) do
    raw_token = String.trim(raw_token)
    hash = LoginLink.hash_token(raw_token)
    now = DateTime.utc_now(:second)

    with %LoginToken{} = token <- Repo.get_by(LoginToken, token_hash: hash),
         :ok <- check_used(token),
         :ok <- check_expired(token, now),
         %User{} = user <- Repo.get(User, token.user_id) do
      mark_used(token, now)
      {:ok, user}
    else
      nil -> {:error, :invalid_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_login_token(_), do: {:error, :invalid_token}

  @spec user_exists?(String.t()) :: boolean()
  def user_exists?(email) when is_binary(email) do
    email = User.normalize_email(email)
    not is_nil(Repo.get_by(User, email_hash: EmailHash.hash(email)))
  end

  def user_exists?(_), do: false

  defp ensure_user(email) do
    hash = EmailHash.hash(email)

    case Repo.get_by(User, email_hash: hash) do
      %User{} = user ->
        {:ok, user}

      nil ->
        %User{}
        |> User.email_changeset(%{email: email})
        |> Repo.insert()
    end
  end

  defp issue_token(%User{} = user) do
    {raw, hash} = LoginLink.generate()
    expires_at = expires_at()

    Repo.transaction(fn ->
      from(t in LoginToken,
        where: t.user_id == ^user.id and is_nil(t.used_at)
      )
      |> Repo.delete_all()

      %LoginToken{}
      |> LoginToken.changeset(%{
        user_id: user.id,
        token_hash: hash,
        expires_at: expires_at
      })
      |> Repo.insert!()

      raw
    end)
    |> case do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, reason}
    end
  end

  defp expires_at do
    days = Ide.Auth.login_link_ttl_days()
    DateTime.utc_now(:second) |> DateTime.add(days * 86_400, :second)
  end

  defp mark_used(%LoginToken{} = token, %DateTime{} = now) do
    token
    |> Ecto.Changeset.change(%{used_at: now})
    |> Repo.update!()
  end

  defp check_used(%LoginToken{used_at: %DateTime{}}), do: {:error, :used_token}
  defp check_used(%LoginToken{used_at: nil}), do: :ok

  defp check_expired(%LoginToken{expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    if DateTime.compare(now, expires_at) == :gt do
      {:error, :expired_token}
    else
      :ok
    end
  end

  defp valid_email?(email) do
    email != "" and String.match?(email, ~r/^[^\s]+@[^\s]+$/) and
      EmailAddress.smtp_deliverable?(email)
  end
end
