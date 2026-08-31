defmodule IdeWeb.UserSocketAuthTest do
  use Ide.DataCase, async: false

  import Phoenix.ChannelTest

  alias Ide.Auth.User
  alias Ide.Repo

  @endpoint IdeWeb.Endpoint

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "local mode accepts socket connect without a session" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :local)
    )

    assert {:ok, _socket} = connect(IdeWeb.UserSocket, %{}, [])
  end

  test "public mode rejects socket connect without a session" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :public_pebble)
    )

    assert :error = connect(IdeWeb.UserSocket, %{}, [])
  end

  test "public mode accepts socket connect with a session user" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :public_pebble)
    )

    user =
      %User{}
      |> User.changeset(%{firebase_uid: "socket-auth-#{System.unique_integer([:positive])}"})
      |> Repo.insert!()

    assert {:ok, socket} =
             connect(IdeWeb.UserSocket, %{},
               connect_info: %{session: %{"user_id" => user.id}}
             )

    assert socket.assigns.current_user.id == user.id
  end
end
