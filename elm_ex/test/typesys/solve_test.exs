defmodule ElmEx.Typesys.SolveTest do
  use ExUnit.Case, async: true

  alias ElmEx.Typesys.{Env, Solve, Type}

  test "unifies identical named types" do
    env = Env.new()
    assert {:ok, _} = Solve.unify(env, Type.int(), Type.int())
  end

  test "number inhabits Int and Float" do
    env = Env.new()
    {num, env} = Env.fresh_constrained(env, :number)
    assert {:ok, _} = Solve.unify(env, num, Type.int())

    {num, env} = Env.fresh_constrained(Env.new(), :number)
    assert {:ok, _} = Solve.unify(env, num, Type.float())
  end

  test "occurs check rejects infinite types" do
    env = Env.new()
    {v, env} = Env.fresh(env)
    {:var, id} = v
    assert {:error, _, _} = Solve.unify(env, v, Type.list(Type.var(id)))
  end

  test "record extra field is a mismatch when both are closed" do
    env = Env.new()
    left = Type.record(%{"x" => Type.int()})
    right = Type.record(%{"x" => Type.int(), "y" => Type.int()})
    assert {:error, _, _} = Solve.unify(env, left, right)
  end

  test "rigid type variable does not unify with Int" do
    env = Env.new()
    {v, env} = Env.fresh(env)
    {:var, id} = v
    env = %{env | rigid_ids: MapSet.put(env.rigid_ids, id)}
    assert {:error, _, _} = Solve.unify(env, v, Type.int())
  end

  test "flexible variable binds to a rigid variable" do
    env = Env.new()
    {rigid, env} = Env.fresh(env)
    {:var, rid} = rigid
    env = %{env | rigid_ids: MapSet.put(env.rigid_ids, rid)}
    {flex, env} = Env.fresh(env)
    assert {:ok, _} = Solve.unify(env, flex, rigid)
  end

  test "comparable rejects Bool and records" do
    env = Env.new()
    {cmp, env} = Env.fresh_constrained(env, :comparable)
    assert {:error, _, _} = Solve.unify(env, cmp, Type.bool())

    {cmp, env} = Env.fresh_constrained(Env.new(), :comparable)
    assert {:error, _, _} = Solve.unify(env, cmp, Type.record(%{"x" => Type.int()}))
  end

  test "appendable rejects mixing String and List" do
    env = Env.new()
    {app, env} = Env.fresh_constrained(env, :appendable)
    assert {:ok, env} = Solve.unify(env, app, Type.string())
    assert {:error, _, _} = Solve.unify(env, app, Type.list(Type.int()))
  end

  test "comparable accepts nested lists and tuples of primitives" do
    env = Env.new()
    {cmp, env} = Env.fresh_constrained(env, :comparable)
    assert {:ok, _} = Solve.unify(env, cmp, Type.list(Type.tuple([Type.int(), Type.string()])))
  end

  test "extensible record accepts extra fields" do
    env = Env.new()
    {row, env} = Env.fresh(env)
    left = Type.record(%{"x" => Type.int()}, row)
    right = Type.record(%{"x" => Type.int(), "y" => Type.int()})
    assert {:ok, _} = Solve.unify(env, left, right)
  end

  test "Html.Html unifies with VirtualDom.Node and Styled.Node" do
    env = Env.new()
    html = Type.named("Html.Html", [Type.named("Msg")])
    node = Type.named("VirtualDom.Node", [Type.named("Msg")])
    styled = Type.named("VirtualDom.Styled.Node", [Type.named("Msg")])
    assert {:ok, _} = Solve.unify(env, html, node)
    assert {:ok, _} = Solve.unify(Env.new(), html, styled)
  end

  test "comparable and appendable accept imported String.String names" do
    env = Env.new()
    {cmp, env} = Env.fresh_constrained(env, :comparable)
    assert {:ok, _} = Solve.unify(env, cmp, Type.named("String.String"))

    {app, env} = Env.fresh_constrained(Env.new(), :appendable)
    assert {:ok, _} = Solve.unify(env, app, Type.named("String.String"))

    {cmp, env} = Env.fresh_constrained(Env.new(), :comparable)
    assert {:ok, _} = Solve.unify(env, cmp, Type.named("List.List", [Type.named("String.String")]))
  end

  test "instantiating a generalized number keeps the number constraint" do
    env = Env.new()
    {num, env} = Env.fresh_constrained(env, :number)
    scheme = Env.generalize(env, Type.list(num))
    {inst, _env} = Env.instantiate(env, scheme)
    assert {:named, "List", [{:constrained, :number, _}]} = inst
  end
end
