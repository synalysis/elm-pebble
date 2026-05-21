defmodule Ide.Auth.EmailAddress do
  @moduledoc false

  @spec smtp_deliverable?(String.t()) :: boolean()
  def smtp_deliverable?(email) when is_binary(email) do
    case String.split(email, "@") do
      [local, domain] when local != "" and domain != "" ->
        domain_ascii_encodable?(domain)

      _ ->
        false
    end
  end

  def smtp_deliverable?(_), do: false

  @spec domain_ascii_encodable?(String.t()) :: boolean()
  defp domain_ascii_encodable?(domain) do
    try do
      _ascii = :idna.utf8_to_ascii(domain)
      true
    catch
      :exit, _ -> false
    end
  end
end
