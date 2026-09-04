defmodule ElmEx.Typesys.Canonicalize do
  @moduledoc """
  Name resolution and structural Elm 0.19 checks before inference.
  """

  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.ImportResolution
  alias ElmEx.IR.Lowerer
  alias ElmEx.Typesys.{Diagnostic, Env, Parser, Pattern, Type}

  @spec run(Project.t(), Env.t()) :: {Env.t(), [map()]}
  def run(%Project{} = project, env) do
    exports = Lowerer.project_module_exports(project.modules)

    app_modules =
      project.modules
      |> Enum.filter(&application_module?(project, &1))

    env =
      app_modules
      |> Enum.reduce(env, fn mod, env ->
        canonicalize_module(env, project, mod, exports)
      end)
      |> check_recursive_aliases_app(app_modules)

    {env, env.errors}
  end

  defp canonicalize_module(env, project, %FrontendModule{} = mod, exports) do
    loc = [module: mod.name, file: Map.get(mod, :path)]

    env
    |> check_module_path(mod, loc)
    |> check_duplicate_decls(mod, loc)
    |> check_exposing(mod, exports, loc)
    |> check_ports(project, mod, loc)
    |> check_unbound(mod, exports, loc)
    |> check_type_arities(mod, loc)
  end

  defp check_module_path(env, mod, loc) do
    path = Map.get(mod, :path)

    if is_binary(path) and is_binary(mod.name) do
      expected = String.replace(mod.name, ".", "/") <> ".elm"
      basename = Path.basename(path)

      if String.ends_with?(path, expected) or basename == Path.basename(expected) do
        env
      else
        Env.add_error(
          env,
          Diagnostic.error(
            "module_name_mismatch",
            "The module name `#{mod.name}` does not match the file path `#{path}`.",
            loc
          )
        )
      end
    else
      env
    end
  end

  defp check_duplicate_decls(env, mod, loc) do
    names =
      mod.declarations
      |> Enum.filter(&(&1.kind in [:function_definition, :function_signature, :type_alias, :union]))
      |> Enum.map(&{&1.kind, &1.name})

    value_names =
      names
      |> Enum.filter(fn {kind, _} -> kind == :function_definition end)
      |> Enum.map(&elem(&1, 1))

    type_names =
      names
      |> Enum.filter(fn {kind, _} -> kind in [:type_alias, :union] end)
      |> Enum.map(&elem(&1, 1))

    env
    |> add_duplicates(value_names, loc, "duplicate_declaration")
    |> add_duplicates(type_names, loc, "duplicate_type")
  end

  defp add_duplicates(env, names, loc, code) do
    names
    |> Enum.frequencies()
    |> Enum.reduce(env, fn
      {name, n}, env when n > 1 and is_binary(name) ->
        Env.add_error(
          env,
          Diagnostic.error(code, "There are #{n} declarations named `#{name}`.", Keyword.put(loc, :name, name))
        )

      _, env ->
        env
    end)
  end

  defp check_exposing(env, mod, exports, loc) do
    exposing = Map.get(mod, :module_exposing)

    cond do
      exposing in [nil, "..", "all"] ->
        env

      is_list(exposing) ->
        available =
          case Map.get(exports, mod.name) do
            %{names: names, types: types} -> MapSet.new(names ++ types)
            _ -> MapSet.new()
          end

        union_names = module_union_names(mod)

        Enum.reduce(exposing, env, fn name, env ->
          clean = exposing_name(name)
          open? = exposing_open?(name)

          cond do
            clean == "" or clean == mod.name ->
              env

            not MapSet.member?(available, clean) ->
              Env.add_error(
                env,
                Diagnostic.error(
                  "bad_exposing",
                  "You are exposing `#{clean}`, but I cannot find it in this module.",
                  Keyword.put(loc, :name, clean)
                )
              )

            open? and not MapSet.member?(union_names, clean) ->
              Env.add_error(
                env,
                Diagnostic.error(
                  "bad_exposing",
                  "You can only use `(..)` on a custom type. `#{clean}` is not a union.",
                  Keyword.put(loc, :name, clean)
                )
              )

            true ->
              env
          end
        end)

      true ->
        env
    end
  end

  defp exposing_name(name) when is_binary(name) do
    name
    |> String.replace(~r/\(.*\)$/, "")
    |> String.trim()
  end

  defp exposing_name(_), do: ""

  defp exposing_open?(name) when is_binary(name), do: String.contains?(name, "..")
  defp exposing_open?(_), do: false

  defp module_union_names(mod) do
    mod.declarations
    |> Enum.filter(&(&1.kind == :union))
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  @spec application_module?(Project.t(), FrontendModule.t()) :: boolean()
  def application_module?(%Project{} = project, mod) do
    project_dir = Path.expand(project.project_dir)

    roots =
      project.elm_json
      |> Map.get("source-directories", ["src"])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and Path.type(&1) == :relative))
      |> Enum.map(&Path.expand(Path.join(project_dir, &1)))
      |> Enum.filter(&app_source_root?(&1, project_dir))

    path = Map.get(mod, :path)

    is_binary(path) and
      Enum.any?(roots, fn root -> String.starts_with?(Path.expand(path), root <> "/") end)
  end

  defp app_source_root?(root, project_dir) do
    inside = root == project_dir or String.starts_with?(root, project_dir <> "/")

    # Generated companion protocol lives under protocol/src inside some
    # compile sandboxes. Infer only real app sources — kernel + annotations
    # cover protocol modules.
    inside and not String.contains?(root, "/protocol/")
  end

  defp check_recursive_aliases_app(env, modules) do
    names =
      modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :type_alias))
        |> Enum.flat_map(fn decl -> [decl.name, "#{mod.name}.#{decl.name}"] end)
      end)
      |> MapSet.new()

    loc = []

    graph =
      env.aliases
      |> Enum.filter(fn {name, _} -> MapSet.member?(names, name) end)
      |> Enum.map(fn {name, info} -> {name, alias_refs(info)} end)
      |> Map.new()

    Enum.reduce(graph, env, fn {name, _}, env ->
      if cyclic?(graph, name, MapSet.new()) do
        Env.add_error(
          env,
          Diagnostic.error(
            "recursive_alias",
            "The type alias `#{name}` is recursive. Use a custom type instead.",
            Keyword.put(loc, :name, name)
          )
        )
      else
        env
      end
    end)
  end

  defp alias_refs(%{body: body}) do
    body
    |> named_refs()
    |> Enum.uniq()
  end

  defp alias_refs(_), do: []

  defp named_refs({:named, name, args}), do: [name | Enum.flat_map(args, &named_refs/1)]
  defp named_refs({:fun, a, b}), do: named_refs(a) ++ named_refs(b)
  defp named_refs({:tuple, elems}), do: Enum.flat_map(elems, &named_refs/1)
  defp named_refs({:record, fields, ext}) do
    Enum.flat_map(Map.values(fields), &named_refs/1) ++ if(ext, do: named_refs(ext), else: [])
  end
  defp named_refs(_), do: []

  defp cyclic?(graph, name, seen) do
    cond do
      MapSet.member?(seen, name) ->
        true

      true ->
        seen = MapSet.put(seen, name)

        graph
        |> Map.get(name, [])
        |> Enum.any?(fn ref ->
          Map.has_key?(graph, ref) and cyclic?(graph, ref, seen)
        end)
    end
  end

  defp check_ports(env, project, mod, loc) do
    ports = Map.get(mod, :ports) || []
    port_module? = Map.get(mod, :port_module, false) == true
    package? = match?(%{"type" => "package"}, project.elm_json)

    env =
      cond do
        ports != [] and not port_module? ->
          Env.add_error(
            env,
            Diagnostic.error("unexpected_ports", "This module declares ports but is not a `port module`.", loc)
          )

        ports != [] and package? ->
          Env.add_error(
            env,
            Diagnostic.error("package_ports", "Packages cannot have ports.", loc)
          )

        true ->
          env
      end

    signatures =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function_signature and &1.name in ports))

    Enum.reduce(signatures, env, fn %{type: type} = sig, env ->
      case Parser.parse(type || "") do
        {:ok, parsed} ->
          parsed = expand_aliases(env, Env.qualify_imported_types(parsed, mod))

          cond do
            not port_effect?(parsed) ->
              Env.add_error(
                env,
                Diagnostic.error(
                  "port_problem",
                  "Port `#{sig.name}` must produce a `Cmd` or `Sub`.",
                  Keyword.put(loc, :name, sig.name)
                )
              )

            not port_jsonable?(parsed) ->
              Env.add_error(
                env,
                Diagnostic.error(
                  "port_problem",
                  "Port `#{sig.name}` payload is not JSON-able. Ports may only send Bool, Int, Float, String, Json.Encode.Value, lists, tuples, and records of those.",
                  Keyword.put(loc, :name, sig.name)
                )
              )

            true ->
              env
          end

        {:error, _} ->
          env
      end
    end)
  end

  defp check_type_arities(env, mod, loc) do
    Enum.reduce(mod.declarations, env, fn decl, env ->
      loc =
        Keyword.merge(loc,
          function: Map.get(decl, :name),
          line: get_in(decl, [:span, :start_line])
        )

      case decl do
        %{kind: kind, type: type} when kind in [:function_signature, :function_definition] and is_binary(type) ->
          check_ann_type_arities(env, type, mod, loc)

        %{kind: :type_alias} = alias_decl ->
          case Map.get(alias_decl, :alias_type) do
            type when is_binary(type) and type != "" ->
              check_ann_type_arities(env, type, mod, loc)

            _ ->
              (Map.get(alias_decl, :field_types) || %{})
              |> Map.values()
              |> Enum.reduce(env, fn
                field_type, env when is_binary(field_type) ->
                  check_ann_type_arities(env, field_type, mod, loc)

                _, env ->
                  env
              end)
          end

        %{kind: :union, constructors: ctors} ->
          Enum.reduce(ctors || [], env, fn
            %{arg: arg}, env when is_binary(arg) and arg != "" ->
              case Parser.parse_ctor_args(arg) do
                {:ok, types} ->
                  Enum.reduce(types, env, fn t, env ->
                    walk_type_arities(env, Env.qualify_annotation_types(t, mod), loc)
                  end)

                _ ->
                  env
              end

            _, env ->
              env
          end)

        _ ->
          env
      end
    end)
  end

  defp check_ann_type_arities(env, source, mod, loc) do
    case Parser.parse(source) do
      {:ok, parsed} ->
        walk_type_arities(env, Env.qualify_annotation_types(parsed, mod), loc)

      _ ->
        env
    end
  end

  defp walk_type_arities(env, type, loc) do
    case type do
      {:named, name, args} ->
        env =
          Enum.reduce(args, env, fn arg, env -> walk_type_arities(env, arg, loc) end)

        case named_type_arity(env, name) do
          expected when is_integer(expected) and length(args) < expected ->
            Env.add_error(
              env,
              Diagnostic.error(
                "too_few_args",
                "`#{name}` needs #{expected} type argument(s), but was given #{length(args)}.",
                Keyword.put(loc, :name, name)
              )
            )

          expected when is_integer(expected) and length(args) > expected ->
            Env.add_error(
              env,
              Diagnostic.error(
                "too_many_args",
                "`#{name}` needs #{expected} type argument(s), but was given #{length(args)}.",
                Keyword.put(loc, :name, name)
              )
            )

          _ ->
            env
        end

      {:fun, a, b} ->
        env |> walk_type_arities(a, loc) |> walk_type_arities(b, loc)

      {:tuple, elems} ->
        Enum.reduce(elems, env, fn elem, env -> walk_type_arities(env, elem, loc) end)

      {:record, fields, ext} ->
        env = Enum.reduce(Map.values(fields), env, fn t, env -> walk_type_arities(env, t, loc) end)
        if ext, do: walk_type_arities(env, ext, loc), else: env

      _ ->
        env
    end
  end

  defp named_type_arity(env, name) do
    current = get_in(env, [:import_lookup, :current_module])
    short = name |> String.split(".") |> List.last()

    local =
      if is_binary(current) and is_binary(name) and not String.contains?(name, ".") do
        Env.lookup_type(env, "#{current}.#{name}")
      end

    kernel_name =
      case short do
        "Cmd" -> "Platform.Cmd"
        "Sub" -> "Platform.Sub"
        "Program" -> "Platform.Program"
        _ -> Parser.canonicalize_name(name)
      end

    case local || Env.lookup_type(env, name) || Env.lookup_type(env, kernel_name) ||
           Env.lookup_type(env, short) do
      %{arity: n, kind: :alias} -> alias_forward_arity(env, name, n)
      %{arity: n} -> n
      _ -> nil
    end
  end

  # 0-param synonyms such as `Pebble.Cmd.Cmd` = `Platform.Cmd` must keep the
  # target arity so `Pebble.Cmd.Cmd msg` is not reported as too many args.
  defp alias_forward_arity(env, name, fallback) do
    case Env.lookup_alias(env, name) do
      %{params: params, body: {:named, target, []}}
      when target != name and (params == [] or is_nil(params)) ->
        named_type_arity(env, target) || fallback

      _ ->
        fallback
    end
  end

  defp port_effect?(type) do
    {_params, ret} = Type.params_and_return(type)
    cmd_or_sub?(ret)
  end

  defp cmd_or_sub?({:named, name, _}) do
    last = name |> String.split(".") |> List.last()
    last in ["Cmd", "Sub"]
  end

  defp cmd_or_sub?(_), do: false

  defp port_jsonable?(type) do
    {params, ret} = Type.params_and_return(type)

    case ret do
      {:named, name, _} when name in ["Cmd", "Platform.Cmd"] ->
        case params do
          [payload] -> jsonable?(payload)
          _ -> false
        end

      {:named, name, _} when name in ["Sub", "Platform.Sub"] ->
        case params do
          [{:fun, payload, _msg}] -> jsonable?(payload)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp jsonable?(:unit), do: true
  defp jsonable?({:named, name, []}) when name in ["Posix", "Time.Posix", "Zone", "Time.Zone"],
    do: false

  defp jsonable?({:named, name, []}) do
    last = name |> String.split(".") |> List.last()
    last in ["Int", "Float", "Bool", "String", "Bytes", "Value"]
  end

  defp jsonable?({:named, name, [elem]}) do
    last = name |> String.split(".") |> List.last()
    last in ["List", "Array"] and jsonable?(elem)
  end
  defp jsonable?({:tuple, elems}), do: Enum.all?(elems, &jsonable?/1)
  defp jsonable?({:record, fields, nil}), do: Enum.all?(Map.values(fields), &jsonable?/1)
  defp jsonable?(_), do: false

  defp expand_aliases(env, type, seen \\ MapSet.new())

  defp expand_aliases(env, {:named, name, args}, seen) do
    args = Enum.map(args, &expand_aliases(env, &1, seen))

    if MapSet.member?(seen, name) do
      {:named, name, args}
    else
      case Env.lookup_alias(env, name) do
        %{body: {:named, target, []}, params: params} when params == [] and args != [] ->
          expand_aliases(env, {:named, target, args}, MapSet.put(seen, name))

        %{body: body, params: params} when is_tuple(body) or body == :unit ->
          subst =
            params
            |> Enum.zip(args)
            |> Enum.reduce(%{}, fn {param, arg}, acc ->
              case alias_param_id(param) do
                nil -> acc
                id -> Map.put(acc, id, arg)
              end
            end)

          expand_aliases(env, Type.subst_apply(subst, body), MapSet.put(seen, name))

        _ ->
          {:named, name, args}
      end
    end
  end

  defp expand_aliases(env, {:fun, a, b}, seen),
    do: {:fun, expand_aliases(env, a, seen), expand_aliases(env, b, seen)}

  defp expand_aliases(env, {:tuple, elems}, seen),
    do: {:tuple, Enum.map(elems, &expand_aliases(env, &1, seen))}

  defp expand_aliases(env, {:record, fields, ext}, seen) do
    {:record, Map.new(fields, fn {k, v} -> {k, expand_aliases(env, v, seen)} end),
     if(ext, do: expand_aliases(env, ext, seen), else: nil)}
  end

  defp expand_aliases(_env, other, _seen), do: other

  defp alias_param_id(id) when is_integer(id), do: id
  defp alias_param_id({:var, id}), do: id

  defp alias_param_id(name) when is_binary(name) do
    case Parser.parse(name) do
      {:ok, {:var, id}} -> id
      _ -> nil
    end
  end

  defp alias_param_id(_), do: nil

  defp check_unbound(env, mod, exports, loc) do
    {alias_map, _members, unqualified, _wild, _types} =
      Lowerer.import_resolution_for(mod, exports)

    env =
      env
      |> Env.put_import_lookup(%{
        alias_map: alias_map,
        import_unqualified_map: unqualified,
        current_module: mod.name
      })
      |> Env.merge_exposed_imports(mod)

    known =
      env.values
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Map.keys(env.constructors)))
      |> MapSet.union(local_names(mod))

    walk_decls(env, mod.declarations, known, alias_map, unqualified, loc)
  end

  defp fun_arg_bound_names(args) do
    Enum.reduce(args || [], MapSet.new(), fn
      name, acc when is_binary(name) ->
        if String.match?(name, ~r/^[a-z_][A-Za-z0-9_]*$/) do
          MapSet.put(acc, name)
        else
          case Pattern.recover(name) do
            {:ok, pat} -> MapSet.union(acc, pattern_var_names(pat))
            :error -> acc
          end
        end

      pat, acc when is_map(pat) ->
        MapSet.union(acc, pattern_var_names(pat))

      _, acc ->
        acc
    end)
  end

  defp local_names(mod) do
    mod.declarations
    |> Enum.filter(&(&1.kind in [:function_definition, :function_signature]))
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  defp walk_decls(env, decls, known, alias_map, unqualified, loc) do
    Enum.reduce(decls, env, fn
      %{kind: :function_definition, name: name, args: args, expr: expr} = decl, env ->
        bound = MapSet.union(known, fun_arg_bound_names(args))
        loc = Keyword.merge(loc, function: name, line: get_in(decl, [:span, :start_line]))
        walk_expr(env, expr, bound, alias_map, unqualified, loc)

      _, env ->
        env
    end)
  end

  defp walk_expr(env, expr, _bound, _aliases, _unqualified, _loc) when not is_map(expr), do: env

  defp walk_expr(env, %{op: :var, name: name}, bound, aliases, unqualified, loc) do
    check_name(env, name, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :call, name: name, args: args}, bound, aliases, unqualified, loc) do
    env = check_name(env, name, bound, aliases, unqualified, loc)
    walk_list(env, args, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :qualified_call, target: target, args: args}, bound, aliases, unqualified, loc) do
    env = check_name(env, target, bound, aliases, unqualified, loc)
    walk_list(env, args, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :constructor_call, target: target, args: args}, bound, aliases, unqualified, loc) do
    env = check_name(env, target, bound, aliases, unqualified, loc)
    walk_list(env, args, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: op, target: target}, bound, aliases, unqualified, loc)
       when op in [:constructor_ref, :qualified_ref] do
    check_name(env, target, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :field_access, arg: arg}, bound, aliases, unqualified, loc) do
    if is_binary(arg) do
      check_name(env, arg, bound, aliases, unqualified, loc)
    else
      walk_expr(env, arg, bound, aliases, unqualified, loc)
    end
  end

  defp walk_expr(env, %{op: :lambda, args: args, body: body}, bound, aliases, unqualified, loc) do
    walk_expr(env, body, MapSet.union(bound, fun_arg_bound_names(args)), aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :let_in, name: name, value_expr: value, in_expr: rest}, bound, aliases, unqualified, loc) do
    bound = MapSet.put(bound, name)
    env = walk_expr(env, value, bound, aliases, unqualified, loc)
    walk_expr(env, rest, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :let_bindings, bindings: bindings, in_expr: rest}, bound, aliases, unqualified, loc) do
    bound =
      Enum.reduce(bindings || [], bound, fn bind, bound ->
        MapSet.union(bound, binding_names(bind))
      end)

    env =
      Enum.reduce(bindings || [], env, fn bind, env ->
        walk_expr(env, Map.get(bind, :value), bound, aliases, unqualified, loc)
      end)

    walk_expr(env, rest, bound, aliases, unqualified, loc)
  end

  defp walk_expr(env, %{op: :case, subject: subject, branches: branches}, bound, aliases, unqualified, loc) do
    env = walk_expr(env, subject, bound, aliases, unqualified, loc)

    Enum.reduce(branches || [], env, fn branch, env ->
      {env, pat_bound} = walk_pattern(env, Map.get(branch, :pattern), bound, aliases, unqualified, loc)
      walk_expr(env, Map.get(branch, :expr), pat_bound, aliases, unqualified, loc)
    end)
  end

  defp walk_expr(env, expr, bound, aliases, unqualified, loc) do
    Enum.reduce(expr, env, fn
      {_k, child}, env when is_map(child) ->
        walk_expr(env, child, bound, aliases, unqualified, loc)

      {_k, children}, env when is_list(children) ->
        walk_list(env, children, bound, aliases, unqualified, loc)

      _, env ->
        env
    end)
  end

  defp walk_list(env, list, bound, aliases, unqualified, loc) do
    Enum.reduce(list || [], env, fn item, env ->
      walk_expr(env, item, bound, aliases, unqualified, loc)
    end)
  end

  defp walk_pattern(env, %{kind: :unknown, source: source}, bound, aliases, unqualified, loc) do
    case Pattern.recover(source) do
      {:ok, recovered} -> walk_pattern(env, recovered, bound, aliases, unqualified, loc)
      :error -> {env, bound}
    end
  end

  defp walk_pattern(env, %{kind: :var, name: name}, bound, _a, _u, _loc) do
    if MapSet.member?(bound, name) do
      # shadowing is allowed; duplicate in the same pattern is checked by caller
      {env, MapSet.put(bound, name)}
    else
      {env, MapSet.put(bound, name)}
    end
  end

  defp walk_pattern(env, %{kind: :constructor, name: name} = pat, bound, aliases, unqualified, loc) do
    env = check_name(env, name, bound, aliases, unqualified, loc)
    {env, bound} = walk_pattern(env, Map.get(pat, :arg_pattern), bound, aliases, unqualified, loc)
    bind = Map.get(pat, :bind)
    bound = if is_binary(bind), do: MapSet.put(bound, bind), else: bound
    {env, bound}
  end

  defp walk_pattern(env, %{kind: :tuple, elements: elems}, bound, aliases, unqualified, loc) do
    {env, bound, _seen, dups} =
      Enum.reduce(elems || [], {env, bound, MapSet.new(), MapSet.new()}, fn el,
                                                                          {env, bound, seen, dups} ->
        names = pattern_var_names(el)
        clash = MapSet.intersection(seen, names)
        {env, bound} = walk_pattern(env, el, bound, aliases, unqualified, loc)
        {env, bound, MapSet.union(seen, names), MapSet.union(dups, clash)}
      end)

    env =
      Enum.reduce(dups, env, fn name, env ->
        Env.add_error(
          env,
          Diagnostic.error(
            "duplicate_pattern",
            "This pattern binds `#{name}` more than once.",
            Keyword.put(loc, :name, name)
          )
        )
      end)

    {env, bound}
  end

  defp walk_pattern(env, %{kind: :record, fields: fields} = pat, bound, _a, _u, _loc) do
    bound = Enum.reduce(fields || [], bound, &MapSet.put(&2, &1))
    bind = Map.get(pat, :bind)
    bound = if is_binary(bind), do: MapSet.put(bound, bind), else: bound
    {env, bound}
  end

  defp walk_pattern(env, %{kind: kind} = pat, bound, aliases, unqualified, loc)
       when kind in [:list, :cons, :alias] do
    Enum.reduce(pat, {env, bound}, fn
      {_k, child}, {env, bound} when is_map(child) ->
        walk_pattern(env, child, bound, aliases, unqualified, loc)

      {_k, children}, {env, bound} when is_list(children) ->
        Enum.reduce(children, {env, bound}, fn child, acc ->
          walk_pattern(elem(acc, 0), child, elem(acc, 1), aliases, unqualified, loc)
        end)

      _, acc ->
        acc
    end)
  end

  defp walk_pattern(env, _pat, bound, _a, _u, _loc), do: {env, bound}

  defp pattern_var_names(%{kind: :var, name: name}), do: MapSet.new([name])

  defp pattern_var_names(%{kind: :tuple, elements: elems}) do
    Enum.reduce(elems || [], MapSet.new(), fn el, acc ->
      MapSet.union(acc, pattern_var_names(el))
    end)
  end

  defp pattern_var_names(%{kind: :constructor} = pat) do
    inner = pattern_var_names(Map.get(pat, :arg_pattern))
    bind = Map.get(pat, :bind)
    if is_binary(bind), do: MapSet.put(inner, bind), else: inner
  end

  defp pattern_var_names(%{kind: :alias, pattern: inner} = pat) do
    names = pattern_var_names(inner)
    bind = Map.get(pat, :bind) || Map.get(pat, :name)
    if is_binary(bind), do: MapSet.put(names, bind), else: names
  end

  defp pattern_var_names(%{kind: :record, fields: fields} = pat) do
    names =
      Enum.reduce(fields || [], MapSet.new(), fn
        name, acc when is_binary(name) -> MapSet.put(acc, name)
        %{name: name}, acc when is_binary(name) -> MapSet.put(acc, name)
        other, acc -> MapSet.union(acc, pattern_var_names(other))
      end)

    bind = Map.get(pat, :bind)
    if is_binary(bind), do: MapSet.put(names, bind), else: names
  end

  defp pattern_var_names(%{kind: kind} = pat) when kind in [:list, :cons] do
    Enum.reduce(pat, MapSet.new(), fn
      {_k, child}, acc when is_map(child) -> MapSet.union(acc, pattern_var_names(child))
      {_k, children}, acc when is_list(children) ->
        Enum.reduce(children, acc, fn child, acc -> MapSet.union(acc, pattern_var_names(child)) end)
      _, acc ->
        acc
    end)
  end

  defp pattern_var_names(_), do: MapSet.new()

  defp binding_names(%{kind: :name, name: name}), do: MapSet.new([name])
  defp binding_names(%{kind: kind, names: names}) when kind in [:tuple2, :tuple3], do: MapSet.new(names)
  defp binding_names(%{kind: :pattern, pattern: pat}), do: pattern_var_names(pat)
  defp binding_names(_), do: MapSet.new()

  defp check_name(env, name, bound, aliases, unqualified, loc) when is_binary(name) do
    resolved = ImportResolution.resolve(name, %{
      alias_map: aliases,
      import_unqualified_map: unqualified,
      local_call_names: bound
    })

    cond do
      MapSet.member?(bound, name) ->
        env

      Env.lookup_value(env, name) != nil ->
        env

      Env.lookup_value(env, resolved) != nil ->
        env

      Env.lookup_ctor(env, name) != nil ->
        env

      operator?(name) ->
        env

      String.starts_with?(name, "__") ->
        env

      Map.get(unqualified, name) == :ambiguous ->
        env

      Map.has_key?(unqualified, name) ->
        env

      Env.lookup_value(env, resolved) != nil ->
        env

      Env.lookup_ctor(env, resolved) != nil ->
        env

      true ->
        Env.add_error(
          env,
          Diagnostic.error(
            "unbound_value",
            "I cannot find a `#{name}` variable",
            Keyword.put(loc, :name, name)
          )
        )
    end
  end

  defp check_name(env, _name, _bound, _a, _u, _loc), do: env

  defp operator?(name) do
    String.starts_with?(name, "(") or name in ~w(+ - * / // ^ == /= < > <= >= && || ++ ::)
  end
end
