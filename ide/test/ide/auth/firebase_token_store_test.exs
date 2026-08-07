defmodule Ide.Auth.FirebaseTokenStoreTest do
  use ExUnit.Case, async: false

  alias Ide.Auth.FirebaseTokenStore

  test "stores and retrieves firebase id tokens by user id" do
    user_id = System.unique_integer([:positive])
    token = "firebase-jwt-#{user_id}"

    assert FirebaseTokenStore.get(user_id) == nil
    assert :ok = FirebaseTokenStore.put(user_id, token)
    assert FirebaseTokenStore.get(user_id) == token
    assert :ok = FirebaseTokenStore.delete(user_id)
    assert FirebaseTokenStore.get(user_id) == nil
  end
end
