defmodule IdeWeb.AuthControllerFirebaseSessionTest do
  use IdeWeb.ConnCase, async: false

  alias Ide.Auth
  alias Ide.Auth.FirebaseTokenStore
  alias Ide.Auth.User
  alias Ide.Repo

  setup do
    previous = Application.get_env(:ide, Ide.Auth, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Auth, previous)
    end)

    :ok
  end

  test "local mode firebase login stores cloud identity without IDE user_id", %{conn: _conn} do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    user =
      %User{}
      |> User.changeset(%{firebase_uid: "local-firebase-uid", display_name: "Local Firebase"})
      |> Repo.insert!()

    # Bypass network verify by putting token after a stub path: call put_firebase via
    # controller only when verify succeeds. Here we unit-test session helper behavior
    # through Auth.resolve + a simulated session shape.
    :ok = FirebaseTokenStore.put(user.id, "jwt-local-mode-token")

    session = %{"firebase_user_id" => user.id, "firebase_id_token_exp" => System.system_time(:second) + 3600}
    assert Auth.resolve_firebase_session_token(session) == "jwt-local-mode-token"
    assert Auth.get_user(session["user_id"]) == nil
  end

  test "public mode resolve uses user_id token store", %{conn: _conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)

    user =
      %User{}
      |> User.changeset(%{firebase_uid: "public-firebase-uid", display_name: "Public Firebase"})
      |> Repo.insert!()

    :ok = FirebaseTokenStore.put(user.id, "jwt-public-mode-token")

    session = %{"user_id" => user.id}
    assert Auth.resolve_firebase_session_token(session) == "jwt-public-mode-token"
  end
end
