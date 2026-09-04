defmodule ElmEx.Typesys.Env do
  @moduledoc """
  Name environment for values, types, constructors, aliases, and fields.
  """

  alias ElmEx.Frontend.DefaultImports
  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.Frontend.Project
  alias ElmEx.Typesys.{Kernel, Parser, Type}

  @type scheme :: {:forall, [Type.var_id()], Type.t()}

  @type ctor_info :: %{
          required(:name) => String.t(),
          required(:union) => String.t(),
          required(:arity) => non_neg_integer(),
          required(:scheme) => scheme()
        }

  @type alias_info :: %{
          required(:name) => String.t(),
          required(:params) => [String.t()],
          required(:body) => Type.t() | :record_fields,
          optional(:fields) => %{String.t() => Type.t()},
          optional(:extensible_base) => String.t() | nil
        }

  @type t :: %{
          values: %{String.t() => scheme() | {:alts, [scheme()]}},
          types: %{String.t() => %{arity: non_neg_integer(), kind: :alias | :union | :opaque}},
          constructors: %{String.t() => ctor_info()},
          aliases: %{String.t() => alias_info()},
          modules: %{String.t() => FrontendModule.t()},
          subst: Type.subst(),
          next_id: integer(),
          rigid_ids: MapSet.t(Type.var_id()),
          import_lookup: map(),
          errors: [map()]
        }

  @spec new() :: t()
  def new do
    %{
      values: %{},
      types: %{},
      constructors: %{},
      aliases: %{},
      modules: %{},
      subst: %{},
      next_id: 1,
      rigid_ids: MapSet.new(),
      import_lookup: %{},
      errors: []
    }
  end

  @spec build(Project.t()) :: t()
  def build(%Project{} = project) do
    env =
      new()
      |> put_modules(project.modules)
      |> Kernel.install()

    env =
      Enum.reduce(project.modules, env, fn mod, acc ->
        install_module(acc, project, mod)
      end)

    env
    |> harvest_named_arities()
    |> Kernel.ensure_known_arities()
    |> ElmEx.Typesys.GeneratedResources.install_env(project)
    |> install_fetcher_route_params(project.modules)
  end

  @spec fresh(t()) :: {Type.t(), t()}
  def fresh(env) do
    id = env.next_id
    {Type.var(id), %{env | next_id: id + 1}}
  end

  @spec fresh_constrained(t(), Type.constraint()) :: {Type.t(), t()}
  def fresh_constrained(env, kind) do
    id = env.next_id
    {Type.constrained(kind, id), %{env | next_id: id + 1}}
  end

  @spec instantiate(t(), scheme()) :: {Type.t(), t()}
  def instantiate(env, {:forall, [], type}), do: {type, env}

  def instantiate(env, {:forall, vars, type}) do
    instantiate_vars(env, vars, type, :flexible)
  end

  @doc """
  Instantiate a scheme with rigid variables (annotation checking).
  Rigid ids cannot be bound to a concrete type.
  """
  @spec instantiate_rigid(t(), scheme()) :: {Type.t(), t()}
  def instantiate_rigid(env, {:forall, [], type}), do: {type, env}

  def instantiate_rigid(env, {:forall, vars, type}) do
    instantiate_vars(env, vars, type, :rigid)
  end

  defp instantiate_vars(env, vars, type, rigidity) do
    constraints = Type.constraints(type)

    {subst, env} =
      Enum.reduce(vars, {%{}, env}, fn id, {subst, env} ->
        {fresh, env} =
          case Map.get(constraints, id) do
            kind when kind in [:number, :comparable, :appendable, :compappend] ->
              fresh_constrained(env, kind)

            _ ->
              fresh(env)
          end

        env =
          if rigidity == :rigid do
            id =
              case fresh do
                {:var, new_id} -> new_id
                {:constrained, _kind, new_id} -> new_id
              end

            %{env | rigid_ids: MapSet.put(env.rigid_ids, id)}
          else
            env
          end

        {Map.put(subst, id, fresh), env}
      end)

    {Type.subst_apply(subst, type), env}
  end

  @spec rigid?(t(), Type.var_id()) :: boolean()
  def rigid?(env, id) when is_integer(id), do: MapSet.member?(env.rigid_ids, id)

  @spec drop_rigid(t(), MapSet.t(Type.var_id())) :: t()
  def drop_rigid(env, keep), do: %{env | rigid_ids: keep}

  @spec put_import_lookup(t(), map()) :: t()
  def put_import_lookup(env, lookup) when is_map(lookup), do: %{env | import_lookup: lookup}

  @spec generalize(t(), Type.t()) :: scheme()
  def generalize(env, type) do
    type = Type.subst_apply(env.subst, type)
    env_free = env_free_vars(env)
    free = type |> Type.free_vars() |> MapSet.difference(env_free)
    {:forall, MapSet.to_list(free), type}
  end

  @spec mono(Type.t()) :: scheme()
  def mono(type), do: {:forall, [], type}

  @spec lookup_value(t(), String.t()) :: scheme() | nil
  def lookup_value(env, name) when is_binary(name) do
    case raw_value(env, name) do
      {:alts, [scheme | _]} -> scheme
      scheme -> scheme
    end
  end

  @spec lookup_value_schemes(t(), String.t()) :: [scheme()]
  def lookup_value_schemes(env, name) when is_binary(name) do
    case raw_value(env, name) do
      {:alts, alts} -> alts
      nil -> []
      scheme -> [scheme]
    end
  end

  defp raw_value(env, name) do
    current = get_in(env, [:import_lookup, :current_module])

    values_get(env, name) ||
      (is_binary(current) && values_get(env, "#{current}.#{name}")) ||
      lookup_value_aliased(env, name) ||
      exposed_get(env, :exposed_values, name)
  end

  defp lookup_value_aliased(env, name) do
    alias_map = get_in(env, [:import_lookup, :alias_map]) || %{}

    case String.split(name, ".", parts: 2) do
      [prefix, rest] ->
        case Map.get(alias_map, prefix) do
          mod when is_binary(mod) -> values_get(env, "#{mod}.#{rest}")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Collision mangling rewrites imports to `Pkg.<id>.Module.name`. Kernel and
  # overlay values stay on the canonical Elm name.
  defp values_get(env, name) do
    mangled = Map.get(env.values, name)

    demangled =
      case demangle_pkg_name(name) do
        nil -> nil
        rest -> Map.get(env.values, rest)
      end

    case {mangled, demangled} do
      {nil, other} ->
        other

      {local, nil} ->
        local

      {local, other} ->
        merge_value_schemes(local, other)
    end
  end

  defp merge_value_schemes(same, same), do: same
  defp merge_value_schemes({:alts, left}, {:alts, right}), do: {:alts, left ++ right}
  defp merge_value_schemes({:alts, alts}, scheme), do: {:alts, alts ++ [scheme]}
  defp merge_value_schemes(scheme, {:alts, alts}), do: {:alts, [scheme | alts]}
  defp merge_value_schemes(left, right), do: {:alts, [left, right]}

  defp demangle_pkg_name(name) when is_binary(name) do
    case String.split(name, ".", parts: 3) do
      ["Pkg", _pkg, rest] when rest != "" -> rest
      _ -> nil
    end
  end

  @spec lookup_ctor(t(), String.t()) :: ctor_info() | nil
  def lookup_ctor(env, name) when is_binary(name) do
    current = get_in(env, [:import_lookup, :current_module])

    (is_binary(current) && ctors_get(env, "#{current}.#{name}")) ||
      ctors_get(env, name) ||
      exposed_get(env, :exposed_ctors, name) ||
      lookup_ctor_aliased(env, name)
  end

  defp ctors_get(env, name) do
    Map.get(env.constructors, name) ||
      case demangle_pkg_name(name) do
        nil -> nil
        rest -> Map.get(env.constructors, rest)
      end
  end

  @spec lookup_alias(t(), String.t()) :: alias_info() | nil
  def lookup_alias(env, name) do
    Map.get(env.aliases, name) ||
      case demangle_pkg_name(name) do
        nil -> exposed_get(env, :exposed_aliases, name)
        rest -> Map.get(env.aliases, rest) || exposed_get(env, :exposed_aliases, name)
      end
  end

  @spec merge_exposed_imports(t(), FrontendModule.t()) :: t()
  def merge_exposed_imports(env, %FrontendModule{} = mod) do
    bindings = exposed_import_bindings(env, mod)

    env =
      Enum.reduce(bindings.values, env, fn {name, scheme}, env ->
        if Map.has_key?(env.values, name), do: env, else: put_value(env, name, scheme)
      end)

    env =
      Enum.reduce(bindings.ctors, env, fn {name, info}, env ->
        if Map.has_key?(env.constructors, name) do
          env
        else
          %{env | constructors: Map.put(env.constructors, name, info)}
        end
      end)

    env =
      Enum.reduce(bindings.aliases, env, fn {name, info}, env ->
        if Map.has_key?(env.aliases, name), do: env, else: put_alias(env, name, info)
      end)

    lookup = env.import_lookup

    put_import_lookup(
      env,
      lookup
      |> Map.put(:exposed_values, bindings.values)
      |> Map.put(:exposed_ctors, bindings.ctors)
      |> Map.put(:exposed_aliases, bindings.aliases)
    )
  end

  def merge_exposed_imports(env, _), do: env

  @spec lookup_type(t(), String.t()) :: map() | nil
  def lookup_type(env, name), do: Map.get(env.types, name)

  @spec expand_type(t(), Type.t()) :: Type.t()
  def expand_type(env, type), do: expand_type(env, type, MapSet.new())

  defp expand_type(env, {:named, name, args}, seen) do
    args = Enum.map(args, &expand_type(env, &1, seen))

    if MapSet.member?(seen, name) do
      {:named, name, args}
    else
      case lookup_alias(env, name) do
        %{body: body, params: params} when is_tuple(body) or body == :unit ->
          subst =
            params
            |> Enum.zip(args)
            |> Enum.reduce(%{}, fn {param, arg}, acc ->
              case alias_param_var_id(param) do
                nil -> acc
                id -> Map.put(acc, id, arg)
              end
            end)

          expand_type(env, Type.subst_apply(subst, body), MapSet.put(seen, name))

        _ ->
          {:named, name, args}
      end
    end
  end

  defp expand_type(env, {:fun, a, b}, seen),
    do: {:fun, expand_type(env, a, seen), expand_type(env, b, seen)}

  defp expand_type(env, {:tuple, elems}, seen),
    do: {:tuple, Enum.map(elems, &expand_type(env, &1, seen))}

  defp expand_type(env, {:record, fields, ext}, seen) do
    {:record, Map.new(fields, fn {k, v} -> {k, expand_type(env, v, seen)} end),
     if(ext, do: expand_type(env, ext, seen), else: nil)}
  end

  defp expand_type(_env, other, _seen), do: other

  defp alias_param_var_id(id) when is_integer(id), do: id
  defp alias_param_var_id({:var, id}), do: id

  defp alias_param_var_id(name) when is_binary(name) do
    case Parser.parse(name) do
      {:ok, {:var, id}} -> id
      _ -> nil
    end
  end

  defp alias_param_var_id(_), do: nil

  @doc """
  Record named-type arities from installed schemes (kernel `Maybe a`, `List a`, …).
  Existing alias/union arities are kept; a later sighting may raise the arity.
  """
  @spec harvest_named_arities(t()) :: t()
  def harvest_named_arities(env) do
    types =
      env.values
      |> Map.values()
      |> Enum.reduce(env.types, &harvest_scheme_arities/2)

    types =
      env.constructors
      |> Map.values()
      |> Enum.reduce(types, fn
        %{scheme: scheme}, acc -> harvest_scheme_arities(scheme, acc)
        _, acc -> acc
      end)

    %{env | types: types}
  end

  defp harvest_scheme_arities({:forall, _, type}, acc), do: harvest_named_arities_type(type, acc)
  defp harvest_scheme_arities({:alts, alts}, acc), do: Enum.reduce(alts, acc, &harvest_scheme_arities/2)
  defp harvest_scheme_arities(_, acc), do: acc

  defp harvest_named_arities_type({:named, name, args}, acc) do
    arity = length(args)

    acc =
      case Map.get(acc, name) do
        nil ->
          Map.put(acc, name, %{arity: arity, kind: :opaque})

        %{kind: kind} when kind in [:union, :alias] ->
          acc

        %{arity: 0} = info when arity > 0 ->
          Map.put(acc, name, %{info | arity: arity})

        _ ->
          acc
      end

    Enum.reduce(args, acc, &harvest_named_arities_type/2)
  end

  defp harvest_named_arities_type({:fun, a, b}, acc) do
    acc
    |> then(&harvest_named_arities_type(a, &1))
    |> then(&harvest_named_arities_type(b, &1))
  end

  defp harvest_named_arities_type({:tuple, elems}, acc),
    do: Enum.reduce(elems, acc, &harvest_named_arities_type/2)

  defp harvest_named_arities_type({:record, fields, ext}, acc) do
    acc = Enum.reduce(Map.values(fields), acc, &harvest_named_arities_type/2)
    if ext, do: harvest_named_arities_type(ext, acc), else: acc
  end

  defp harvest_named_arities_type(_, acc), do: acc

  @spec put_value(t(), String.t(), scheme() | {:alts, [scheme()]}) :: t()
  def put_value(env, name, scheme) when is_binary(name) do
    %{env | values: Map.put(env.values, name, scheme)}
  end

  @doc """
  Adds an extra scheme for a kernel overload. Locals must use `put_value/3`
  so they replace rather than merge with a same-named binding.
  """
  @spec put_alt(t(), String.t(), scheme()) :: t()
  def put_alt(env, name, scheme) when is_binary(name) do
    values =
      case Map.get(env.values, name) do
        nil ->
          Map.put(env.values, name, scheme)

        {:alts, alts} ->
          Map.put(env.values, name, {:alts, alts ++ [scheme]})

        existing ->
          Map.put(env.values, name, {:alts, [existing, scheme]})
      end

    %{env | values: values}
  end

  @spec put_values(t(), [{String.t(), scheme()}]) :: t()
  def put_values(env, pairs) do
    Enum.reduce(pairs, env, fn {name, scheme}, acc -> put_value(acc, name, scheme) end)
  end

  @spec add_error(t(), map()) :: t()
  def add_error(env, diag) do
    if generated_elm_pages_diag?(diag) do
      env
    else
      %{env | errors: env.errors ++ [diag]}
    end
  end

  # elm-pages emits `.elm-pages/*.elm` for its own compiler (ports, 4-tuples,
  # injected wire3). Official `elm make` is not the checker for those files.
  defp generated_elm_pages_diag?(diag) when is_map(diag) do
    file = Map.get(diag, :file) || Map.get(diag, "file")
    is_binary(file) and String.contains?(file, "/.elm-pages/")
  end

  defp generated_elm_pages_diag?(_), do: false

  @spec put_alias(t(), String.t(), alias_info()) :: t()
  def put_alias(env, name, info) when is_binary(name) and is_map(info) do
    arity = length(Map.get(info, :params) || [])

    env
    |> Map.update!(:aliases, &Map.put(&1, name, info))
    |> put_type_arity(name, arity, :alias)
  end

  @spec default_import_names() :: [String.t()]
  def default_import_names, do: DefaultImports.module_names()

  defp put_modules(env, modules) do
    %{env | modules: Map.new(modules, &{&1.name, &1})}
  end

  defp env_free_vars(env) do
    env.values
    |> Map.values()
    |> Enum.flat_map(fn
      {:alts, alts} -> alts
      scheme -> [scheme]
    end)
    |> Enum.reduce(MapSet.new(), fn
      {:forall, vars, type}, acc ->
        free = type |> Type.free_vars() |> MapSet.difference(MapSet.new(vars))
        MapSet.union(acc, free)

      _, acc ->
        acc
    end)
  end

  defp install_module(env, project, %FrontendModule{} = mod) do
    app? = ElmEx.Typesys.Canonicalize.application_module?(project, mod)

    decls =
      Enum.sort_by(mod.declarations, fn decl ->
        if type_level_decl?(decl), do: 0, else: 1
      end)

    Enum.reduce(decls, env, fn decl, acc ->
      if app? or type_level_decl?(decl) do
        install_decl(acc, mod, decl)
      else
        acc
      end
    end)
  end

  defp type_level_decl?(%{kind: kind}) when kind in [:type_alias, :union], do: true
  defp type_level_decl?(_), do: false

  defp install_decl(env, mod, %{kind: :function_signature, name: name, type: type})
       when is_binary(name) and is_binary(type) do
    case Parser.parse(type) do
      {:ok, parsed} ->
        parsed = qualify_annotation_types(parsed, mod)
        scheme = generalize_closed(parsed)
        qualified = "#{mod.name}.#{name}"

        # Kernel overloads (for example Pebble.Ui.text 1-arg) must not be
        # replaced by the package annotation when that module is loaded.
        env =
          if Map.has_key?(env.values, qualified) do
            env
          else
            put_value(env, qualified, scheme)
          end

        if default_import_short?(mod.name) and is_nil(lookup_value(env, name)) do
          put_value(env, name, scheme)
        else
          env
        end

      {:error, _} ->
        env
    end
  end

  defp install_decl(env, mod, %{kind: :type_alias, name: name} = decl) when is_binary(name) do
    qualified = "#{mod.name}.#{name}"

    if opaque_type?(env, qualified) do
      env
    else
      install_type_alias(env, mod, decl, name, qualified)
    end
  end

  defp install_decl(env, mod, %{kind: :union, name: name, constructors: constructors} = decl)
       when is_binary(name) and is_list(constructors) do
    install_union(env, mod, decl, name, constructors)
  end

  defp install_decl(env, _mod, _decl), do: env

  @doc """
  Bind unannotated functions on dependency modules so application code can
  call them. Application modules must not get these stubs — Infer treats a
  polymorphic scheme as a rigid annotation.
  """
  @spec install_unannotated_exports(t(), [FrontendModule.t()]) :: t()
  def install_unannotated_exports(env, modules) when is_list(modules) do
    Enum.reduce(modules, env, fn mod, env ->
      Enum.reduce(mod.declarations || [], env, fn
        %{kind: :function_definition, name: name}, env when is_binary(name) ->
          qualified = "#{mod.name}.#{name}"

          if Map.has_key?(env.values, qualified) do
            env
          else
            put_value(env, qualified, {:forall, [0], Type.var(0)})
          end

        _, env ->
          env
      end)
    end)
  end

  defp opaque_type?(env, name), do: match?(%{kind: :opaque}, lookup_type(env, name))

  defp install_type_alias(env, mod, decl, name, qualified) do
    fields = Map.get(decl, :fields) || []
    field_types = Map.get(decl, :field_types) || %{}
    alias_type = Map.get(decl, :alias_type)

    {body, field_map} =
      cond do
        is_map(field_types) and map_size(field_types) > 0 ->
          parsed_fields =
            field_types
            |> Enum.map(fn {k, v} ->
              case Parser.parse(to_string(v)) do
                {:ok, t} -> {to_string(k), qualify_local_types(qualify_imported_types(t, mod), mod)}
                _ -> {to_string(k), Type.named(to_string(v))}
              end
            end)
            |> Map.new()

          {Type.record(parsed_fields), parsed_fields}

        is_binary(alias_type) ->
          case Parser.parse(alias_type) do
            {:ok, t} ->
              t = qualify_local_types(qualify_imported_types(t, mod), mod)

              field_map =
                case t do
                  {:record, fs, _} -> fs
                  _ -> %{}
                end

              {t, field_map}

            _ ->
              {Type.named(alias_type), %{}}
          end

        fields != [] ->
          parsed_fields = Map.new(fields, fn f -> {to_string(f), Type.var(0)} end)
          {Type.record(parsed_fields), parsed_fields}

        empty_record_alias?(decl) ->
          {Type.record(%{}), %{}}

        unit_alias?(decl) ->
          {:unit, %{}}

        true ->
          {Type.named(qualified), %{}}
      end

    params = alias_param_names(decl, name)
    body = apply_alias_body_params(body, params)

    info = %{
      name: qualified,
      params: params,
      body: body,
      fields: field_map,
      extensible_base: Map.get(decl, :extensible_base)
    }

    arity = length(params)

    env
    |> Map.update!(:aliases, &Map.put(&1, qualified, info))
    |> Map.update!(:aliases, &Map.put(&1, name, info))
    |> put_type_arity(qualified, arity, :alias)
    |> put_type_arity(name, arity, :alias)
    |> install_record_ctor(name, qualified, fields, field_map, body, alias_type)
    |> install_wire3_helpers(mod, name, Type.named(qualified))
  end

  defp put_type_arity(env, name, arity, :union) do
    Map.update!(env, :types, &Map.put(&1, name, %{arity: arity, kind: :union}))
  end

  defp put_type_arity(env, name, arity, kind) do
    Map.update!(env, :types, fn types ->
      case Map.get(types, name) do
        %{arity: existing} when is_integer(existing) and existing > arity ->
          types

        _ ->
          Map.put(types, name, %{arity: arity, kind: kind})
      end
    end)
  end

  defp install_record_ctor(env, _name, qualified, fields, field_map, body, alias_type) do
    names =
      cond do
        is_list(fields) and fields != [] ->
          Enum.map(fields, &field_ident/1)

        is_binary(alias_type) ->
          names = field_names_from_record_src(alias_type)
          if names == [], do: map_field_names(field_map), else: names

        true ->
          map_field_names(field_map)
      end

    if names == [] or not is_map(field_map) or map_size(field_map) == 0 do
      env
    else
      arg_ts = Enum.map(names, &Map.get(field_map, &1, Type.var(0)))
      scheme = generalize_closed(Type.funs(arg_ts, body))
      put_value(env, qualified, scheme)
    end
  end

  defp map_field_names(field_map) when is_map(field_map) and map_size(field_map) > 0,
    do: Map.keys(field_map)

  defp map_field_names(_), do: []

  defp field_names_from_record_src(src) when is_binary(src) do
    inner =
      src
      |> String.replace(~r/\A[^{]*\{/, "")
      |> String.replace(~r/\}[^}]*\z/, "")

    inner
    |> String.split(",")
    |> Enum.map(fn part ->
      part = if String.contains?(part, "|"), do: part |> String.split("|") |> List.last(), else: part

      part
      |> String.trim()
      |> String.split(~r/\s*:/, parts: 2)
      |> hd()
      |> String.trim()
    end)
    |> Enum.filter(&String.match?(&1, ~r/\A[a-z][A-Za-z0-9_]*\z/))
  end

  defp field_ident(%{name: name}) when is_binary(name), do: name
  defp field_ident(name) when is_binary(name), do: name
  defp field_ident(_), do: "_"

  defp install_union(env, mod, decl, name, constructors) do
    qualified_union = "#{mod.name}.#{name}"
    param_types = union_param_types(decl)
    arity = length(param_types)
    env = put_type_arity(env, qualified_union, arity, :union)
    env = put_type_arity(env, name, arity, :union)
    union_type = Type.named(qualified_union, param_types)

    Enum.reduce(constructors, env, fn ctor, acc ->
      ctor_name = Map.get(ctor, :name)

      if is_binary(ctor_name) do
        arg = Map.get(ctor, :arg)
        {payload_types, ctor_arity} = ctor_payloads(arg, mod)
        scheme = generalize_closed(Type.funs(payload_types, union_type))

        info = %{
          name: ctor_name,
          union: qualified_union,
          arity: ctor_arity,
          scheme: scheme
        }

        acc
        |> Map.update!(:constructors, fn ctors ->
          ctors
          |> Map.put("#{mod.name}.#{ctor_name}", info)
          |> Map.put("#{qualified_union}.#{ctor_name}", info)
        end)
        |> put_value("#{mod.name}.#{ctor_name}", scheme)
      else
        acc
      end
    end)
    |> install_wire3_helpers(mod, name, union_type)
  end

  # Lamdera / elm-pages injects `w3_encode_*` / `w3_decode_*` at compile time.
  # Typesys must see the same helpers IR synthesizes in Wire3HelperResolution.
  defp install_wire3_helpers(env, %FrontendModule{name: mod_name}, type_name, payload)
       when is_binary(mod_name) and type_name in ["ActionData", "Data"] do
    decode = "#{mod_name}.w3_decode_#{type_name}"
    encode = "#{mod_name}.w3_encode_#{type_name}"

    env =
      if Map.has_key?(env.values, decode) do
        env
      else
        put_value(env, decode, generalize_closed(Type.named("Bytes.Decode.Decoder", [payload])))
      end

    if Map.has_key?(env.values, encode) do
      env
    else
      put_value(env, encode, generalize_closed(Type.funs([payload], Type.named("Bytes.Encode.Encoder"))))
    end
  end

  defp install_wire3_helpers(env, _, _, _), do: env

  # elm-pages generated `Fetcher.*` modules close over route `params` even when
  # the `submit` header omitted the argument (parameterized routes).
  defp install_fetcher_route_params(env, modules) when is_list(modules) do
    Enum.reduce(modules, env, fn
      %{name: "Fetcher." <> rest}, env ->
        params_alias =
          lookup_alias(env, "Route.#{rest}.RouteParams") ||
            lookup_alias(env, "Route.#{rest}.Params")

        key = "Fetcher.#{rest}.params"

        cond do
          Map.has_key?(env.values, key) ->
            env

          is_map(params_alias) ->
            body = Map.get(params_alias, :body) || Type.named("Route.#{rest}.Params")
            put_value(env, key, generalize_closed(body))

          true ->
            env
        end

      _, env ->
        env
    end)
  end

  defp union_param_types(decl) do
    (Map.get(decl, :type_params) || [])
    |> Enum.map(fn param ->
      case Parser.parse(to_string(param)) do
        {:ok, t} -> t
        _ -> Type.var(:erlang.phash2(param, 1_000_000))
      end
    end)
  end

  defp ctor_payloads(nil, _mod), do: {[], 0}
  defp ctor_payloads("", _mod), do: {[], 0}

  defp ctor_payloads(arg, %FrontendModule{} = mod) when is_binary(arg) do
    types =
      case Parser.parse_ctor_args(arg) do
        {:ok, parsed} when parsed != [] ->
          Enum.map(parsed, fn t ->
            t
            |> qualify_imported_types(mod)
            |> qualify_local_types(mod)
          end)

        _ ->
          arg
          |> split_ctor_args()
          |> Enum.map(fn part ->
            case Parser.parse(part) do
              {:ok, t} ->
                t
                |> qualify_imported_types(mod)
                |> qualify_local_types(mod)

              _ ->
                Type.named(part)
            end
          end)
      end

    {types, length(types)}
  end

  defp ctor_payloads(_arg, _mod), do: {[], 0}

  defp split_ctor_args(arg) do
    arg
    |> String.trim()
    |> case do
      "" -> []
      src -> ElmEx.IR.TypeSignature.tuple_element_types("(" <> src <> ")") |> nonempty_or_one(src)
    end
  end

  defp nonempty_or_one([], src), do: [src]
  defp nonempty_or_one(parts, _src), do: parts

  defp generalize_closed(type) do
    {:forall, MapSet.to_list(Type.free_vars(type)), type}
  end

  # Default imports expose Basics (..) and operators, not String.pad / List.map.
  defp default_import_short?(mod_name) when is_binary(mod_name) do
    mod_name == "Basics"
  end

  defp empty_record_alias?(decl) do
    source = Map.get(decl, :source)
    is_binary(source) and String.match?(source, ~r/=\s*\{\s*\}/s)
  end

  defp unit_alias?(decl) do
    alias_type = Map.get(decl, :alias_type)
    source = Map.get(decl, :source)

    alias_type == "()" or
      (is_binary(source) and String.match?(source, ~r/=\s*\(\s*\)\s*$/s))
  end

  defp alias_param_names(decl, name) do
    explicit = Map.get(decl, :type_params)

    cond do
      is_list(explicit) and explicit != [] ->
        Enum.map(explicit, &to_string/1)

      is_binary(Map.get(decl, :source)) ->
        params_from_alias_source(decl.source, name)

      true ->
        []
    end
  end

  defp params_from_alias_source(source, name) when is_binary(source) and is_binary(name) do
    pattern = ~r/type\s+alias\s+#{Regex.escape(name)}\s+([^=]+)=/u

    case Regex.run(pattern, source) do
      [_, params] ->
        params
        |> String.split(~r/\s+/u, trim: true)
        |> Enum.filter(&String.match?(&1, ~r/^[a-z]/))

      _ ->
        []
    end
  end

  defp apply_alias_body_params(body, _params), do: body

  @spec qualify_annotation_types(Type.t(), FrontendModule.t()) :: Type.t()
  def qualify_annotation_types(type, mod) do
    type
    |> qualify_local_types(mod)
    |> qualify_imported_types(mod)
  end

  @spec qualify_imported_types(Type.t(), FrontendModule.t()) :: Type.t()
  def qualify_imported_types(type, mod) do
    aliases = import_alias_map(mod)
    rewrite_named_types(type, fn name ->
      name
      |> resolve_imported_type_name(aliases)
      |> Parser.canonicalize_name()
    end)
  end

  defp rewrite_named_types({:named, name, args}, fun) do
    {:named, fun.(name), Enum.map(args, &rewrite_named_types(&1, fun))}
  end

  defp rewrite_named_types({:fun, a, b}, fun),
    do: {:fun, rewrite_named_types(a, fun), rewrite_named_types(b, fun)}

  defp rewrite_named_types({:tuple, elems}, fun),
    do: {:tuple, Enum.map(elems, &rewrite_named_types(&1, fun))}

  defp rewrite_named_types({:record, fields, ext}, fun) do
    {:record, Map.new(fields, fn {k, v} -> {k, rewrite_named_types(v, fun)} end),
     if(ext, do: rewrite_named_types(ext, fun), else: nil)}
  end

  defp rewrite_named_types(other, _fun), do: other

  defp resolve_imported_type_name(name, aliases) when is_binary(name) and is_map(aliases) do
    cond do
      name in ["Platform.Cmd", "Platform.Sub"] ->
        name

      true ->
        case String.split(name, ".", parts: 2) do
          [prefix, rest] ->
            if String.contains?(rest, ".") do
              name
            else
              case Map.get(aliases, prefix) do
                mod when is_binary(mod) -> "#{mod}.#{rest}"
                _ -> name
              end
            end

          _ ->
            case Map.get(aliases, name) do
              mod when is_binary(mod) -> "#{mod}.#{name}"
              _ -> name
            end
        end
    end
  end

  defp resolve_imported_type_name(name, _), do: name

  defp import_alias_map(%FrontendModule{} = mod) do
    Enum.reduce(mod.import_entries, %{}, fn entry, acc ->
      module_name = entry_field(entry, "module")
      as_name = entry_field(entry, "as")

      if is_binary(module_name) and module_name != "" do
        compact = String.replace(module_name, ".", "")

        acc
        |> maybe_put_alias(as_name, module_name)
        |> maybe_put_alias(compact, module_name)
      else
        acc
      end
    end)
  end

  defp import_alias_map(_), do: %{}

  defp maybe_put_alias(acc, name, module_name)
       when is_binary(name) and name != "" and is_binary(module_name) do
    Map.put(acc, name, module_name)
  end

  defp maybe_put_alias(acc, _, _), do: acc

  defp entry_field(entry, key) when is_map(entry) do
    Map.get(entry, key) || Map.get(entry, String.to_atom(key))
  end

  defp entry_field(_, _), do: nil

  defp qualify_local_types(type, %FrontendModule{} = mod) do
    qualify_local_named(type, mod.name, imported_type_map(mod), local_type_names(mod))
  end

  defp local_type_names(%FrontendModule{} = mod) do
    (mod.declarations || [])
    |> Enum.filter(&(&1.kind in [:type_alias, :union]))
    |> Enum.map(& &1.name)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp qualify_local_named({:named, name, args}, mod_name, imported, local_types) do
    name =
      cond do
        # Only unqualified names can be a local `type`/`alias`. Rewriting
        # `UiResources.Font` to `Pebble.Ui.Font` made the package alias
        # circular and broke `Pebble.Ui.Font` = `Pebble.Ui.Resources.Font`.
        not String.contains?(name, ".") and MapSet.member?(local_types, name) ->
          "#{mod_name}.#{name}"

        true ->
          name = Parser.canonicalize_name(name)

          cond do
            String.contains?(name, ".") ->
              name

            Map.has_key?(imported, name) ->
              Map.get(imported, name)

            String.match?(name, ~r/^[A-Z]/) and name not in kernel_type_names() ->
              "#{mod_name}.#{name}"

            true ->
              name
          end
      end

    {:named, name, Enum.map(args, &qualify_local_named(&1, mod_name, imported, local_types))}
  end

  defp qualify_local_named({:fun, a, b}, mod_name, imported, local_types),
    do:
      {:fun, qualify_local_named(a, mod_name, imported, local_types),
       qualify_local_named(b, mod_name, imported, local_types)}

  defp qualify_local_named({:tuple, elems}, mod_name, imported, local_types),
    do: {:tuple, Enum.map(elems, &qualify_local_named(&1, mod_name, imported, local_types))}

  defp qualify_local_named({:record, fields, ext}, mod_name, imported, local_types) do
    {:record,
     Map.new(fields, fn {k, v} -> {k, qualify_local_named(v, mod_name, imported, local_types)} end),
     if(ext, do: qualify_local_named(ext, mod_name, imported, local_types), else: nil)}
  end

  defp qualify_local_named(other, _mod_name, _imported, _local_types), do: other

  defp kernel_type_names do
    MapSet.new(~w(
      Int Float Bool String Char List Maybe Result Dict Set Array Task Cmd Sub
      Order Never Program Platform Process Json Value Decoder Encoder
      Platform.Cmd Platform.Sub
      Posix Zone Month Weekday Generator Seed
      Json.Decode.Error Process.Id
      Html Attribute Svg Url Bytes File Key
    ))
  end

  defp exposed_get(env, key, name) do
    env
    |> Map.get(:import_lookup, %{})
    |> Map.get(key, %{})
    |> Map.get(name)
  end

  defp lookup_ctor_aliased(env, name) do
    alias_map = get_in(env, [:import_lookup, :alias_map]) || %{}

    case String.split(name, ".", parts: 2) do
      [prefix, rest] ->
        case Map.get(alias_map, prefix) do
          mod when is_binary(mod) -> ctors_get(env, "#{mod}.#{rest}")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp imported_type_map(%FrontendModule{} = mod) do
    Enum.reduce(mod.import_entries, %{}, fn entry, acc ->
      module_name = entry_field(entry, "module")
      exposing = Map.get(entry, "exposing") || Map.get(entry, :exposing)
      as_name = entry_field(entry, "as")

      acc =
        cond do
          not is_binary(module_name) or module_name == "" ->
            acc

          exposing == ".." ->
            acc

          is_list(exposing) ->
            Enum.reduce(exposing, acc, fn item, acc ->
              name = exposing_item_name(item)

              if name != "" and String.match?(name, ~r/^[A-Z]/) do
                Map.put(acc, name, "#{module_name}.#{name}")
              else
                acc
              end
            end)

          true ->
            acc
        end

      # `import Pebble.Ui.Color as Color` then `Color` in a type means
      # `Pebble.Ui.Color.Color` (primary type named after the module).
      last = is_binary(module_name) && List.last(String.split(module_name, "."))

      if is_binary(as_name) and as_name != "" and as_name == last and not Map.has_key?(acc, as_name) do
        Map.put(acc, as_name, "#{module_name}.#{as_name}")
      else
        acc
      end
    end)
  end

  defp exposed_import_bindings(env, %FrontendModule{} = mod) do
    Enum.reduce(mod.import_entries, %{values: %{}, ctors: %{}, aliases: %{}}, fn entry, acc ->
      expose_import_entry(env, entry, acc)
    end)
  end

  defp expose_import_entry(env, entry, acc) do
    module_name = entry_field(entry, "module")
    exposing = Map.get(entry, "exposing") || Map.get(entry, :exposing)

    cond do
      not is_binary(module_name) or module_name == "" ->
        acc

      exposing == ".." ->
        expose_all_from_module(env, module_name, acc)

      is_list(exposing) ->
        Enum.reduce(exposing, acc, fn item, acc ->
          expose_import_item(env, module_name, item, acc)
        end)

      true ->
        acc
    end
  end

  defp expose_import_item(env, module_name, item, acc) do
    name = exposing_item_name(item)
    open? = exposing_item_open?(item)
    acc = expose_type_name(env, module_name, name, acc)
    acc = if open?, do: expose_ctors_of(env, module_name, name, acc), else: acc
    expose_value_name(env, module_name, name, acc)
  end

  defp expose_all_from_module(env, module_name, acc) do
    prefix = module_name <> "."

    acc =
      env.values
      |> Enum.reduce(acc, fn {name, scheme}, acc ->
        if String.starts_with?(name, prefix) do
          put_unless(acc, :values, String.replace_prefix(name, prefix, ""), scheme)
        else
          acc
        end
      end)

    acc =
      env.constructors
      |> Enum.reduce(acc, fn {name, info}, acc ->
        if String.starts_with?(name, prefix) do
          put_unless(acc, :ctors, String.replace_prefix(name, prefix, ""), info)
        else
          acc
        end
      end)

    env.aliases
    |> Enum.reduce(acc, fn {name, info}, acc ->
      if String.starts_with?(name, prefix) do
        put_unless(acc, :aliases, String.replace_prefix(name, prefix, ""), info)
      else
        acc
      end
    end)
  end

  defp expose_type_name(env, module_name, name, acc) when is_binary(name) and name != "" do
    qualified = "#{module_name}.#{name}"

    acc =
      case Map.get(env.aliases, qualified) do
        nil -> acc
        info -> put_unless(acc, :aliases, name, info)
      end

    case Map.get(env.types, qualified) do
      nil ->
        acc

      info ->
        put_unless(
          acc,
          :aliases,
          name,
          Map.get(env.aliases, qualified) || transparent_type_alias(qualified, info)
        )
    end
  end

  defp expose_type_name(_env, _module_name, _name, acc), do: acc

  defp transparent_type_alias(qualified, %{arity: arity})
       when is_integer(arity) and arity > 0 do
    params = Enum.map(1..arity, fn i -> "a#{i}" end)
    args = Enum.map(params, &parse_alias_param/1)
    %{name: qualified, params: params, body: Type.named(qualified, args), fields: %{}}
  end

  defp transparent_type_alias(qualified, _) do
    %{name: qualified, params: [], body: Type.named(qualified), fields: %{}}
  end

  defp parse_alias_param(name) do
    case Parser.parse(name) do
      {:ok, t} -> t
      _ -> Type.named(name)
    end
  end

  defp expose_ctors_of(env, module_name, type_name, acc) do
    qualified_union = "#{module_name}.#{type_name}"

    env.constructors
    |> Map.values()
    |> Enum.uniq_by(&{&1.name, &1.union})
    |> Enum.reduce(acc, fn info, acc ->
      if info.union == qualified_union or info.union == type_name do
        short = info.name |> String.split(".") |> List.last()

        acc
        |> put_unless(:ctors, short, info)
        |> put_unless(:values, short, info.scheme)
      else
        acc
      end
    end)
  end

  defp expose_value_name(env, module_name, name, acc) when is_binary(name) and name != "" do
    case Map.get(env.values, "#{module_name}.#{name}") do
      nil -> acc
      scheme -> put_unless(acc, :values, name, scheme)
    end
  end

  defp expose_value_name(_env, _module_name, _name, acc), do: acc

  defp put_unless(acc, key, name, value) when is_binary(name) and name != "" do
    Map.update!(acc, key, fn map ->
      if Map.has_key?(map, name), do: map, else: Map.put(map, name, value)
    end)
  end

  defp put_unless(acc, _key, _name, _value), do: acc

  defp exposing_item_name(item) when is_binary(item) do
    item
    |> String.replace("(..)", "")
    |> String.replace("..", "")
    |> String.replace(~r/[()]/, "")
    |> String.trim()
  end

  defp exposing_item_name(_), do: ""

  defp exposing_item_open?(item) when is_binary(item), do: String.contains?(item, "..")
  defp exposing_item_open?(_), do: false
end
