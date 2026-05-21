defmodule Ide.Repo do
  use Ecto.Repo,
    otp_app: :ide,
    adapter: Application.compile_env!(:ide, :ecto_adapter)
end
