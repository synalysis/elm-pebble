Nonterminals let_expr let_bindings let_binding if_expr case_expr case_after_of case_branches case_branch pattern pattern_arg ctor_pattern_args
             lambda_expr lambda_args lambda_arg pipe_right_expr plain_pipe_expr apply_left_expr bool_or_expr bool_and_expr compare_expr compare_op cons_expr append_expr add_expr mul_expr pow_expr app_expr atom compose_name list_expr
             list_items tuple_items record_expr record_fields record_field pattern_record_fields pattern_list_items.
Terminals lparen rparen lbracket rbracket lbrace rbrace comma semicolon cons append plus minus shl shr pipe_right pipe apply_left eq eqeq gt lt gte lte neq bslash arrow
         times pow int_div divide pipe_dot pipe_eq
          andand oror let_kw in_kw if_kw then_kw else_kw case_kw of_kw as_kw wildcard
         int_lit float_lit string_lit char_lit field_accessor lower_qid upper_qid.

Rootsymbol pipe_right_expr.
Expect 6.

pipe_right_expr -> let_expr : '$1'.
pipe_right_expr -> if_expr : '$1'.
pipe_right_expr -> case_expr : '$1'.
pipe_right_expr -> lambda_expr : '$1'.
pipe_right_expr -> plain_pipe_expr : '$1'.

plain_pipe_expr -> plain_pipe_expr pipe_right apply_left_expr : build_pipe_right('$1', '$3').
plain_pipe_expr -> plain_pipe_expr pipe_dot apply_left_expr : build_pipe_dot('$1', '$3').
plain_pipe_expr -> plain_pipe_expr pipe_eq apply_left_expr : build_pipe_eq('$1', '$3').
plain_pipe_expr -> apply_left_expr : '$1'.

apply_left_expr -> bool_or_expr apply_left pipe_right_expr : build_apply_left('$1', '$3').
apply_left_expr -> bool_or_expr : '$1'.

bool_or_expr -> bool_and_expr oror bool_or_expr : build_or('$1', '$3').
bool_or_expr -> bool_and_expr : '$1'.

bool_and_expr -> compare_expr andand bool_and_expr : build_and('$1', '$3').
bool_and_expr -> compare_expr : '$1'.

let_expr -> let_kw let_bindings in_kw pipe_right_expr :
  build_let_bindings('$2', '$4').

let_bindings -> let_binding semicolon let_bindings : ['$1' | '$3'].
let_bindings -> let_binding let_bindings : ['$1' | '$2'].
let_bindings -> let_binding : ['$1'].

let_binding -> lower_qid eq pipe_right_expr : {token_value('$1'), '$3'}.
let_binding -> lower_qid lambda_args eq pipe_right_expr : {token_value('$1'), build_lambda_args('$2', '$4')}.
let_binding -> lparen pattern rparen eq pipe_right_expr : {pattern_bind, '$2', '$5'}.
let_binding -> lparen lower_qid comma lower_qid rparen eq pipe_right_expr :
  {tuple2_bind, token_value('$2'), token_value('$4'), '$7'}.
let_binding -> lparen lower_qid comma lower_qid comma lower_qid rparen eq pipe_right_expr :
  {tuple3_bind, token_value('$2'), token_value('$4'), token_value('$6'), '$9'}.

if_expr -> if_kw pipe_right_expr then_kw pipe_right_expr else_kw pipe_right_expr :
  build_if('$2', '$4', '$6').

case_expr -> case_kw pipe_right_expr of_kw case_after_of case_branches :
  build_case('$2', '$5').

case_after_of -> semicolon : ok.
case_after_of -> '$empty' : ok.

case_branches -> case_branches semicolon case_branch : '$1' ++ ['$3'].
case_branches -> case_branch : ['$1'].

case_branch -> pattern arrow pipe_right_expr : #{pattern => '$1', expr => '$3'}.

pattern -> wildcard : #{kind => wildcard}.
pattern -> lower_qid : build_pattern_var(token_value('$1')).
pattern -> int_lit : #{kind => int, value => token_value('$1')}.
pattern -> char_lit : #{kind => int, value => parse_char(token_value('$1'))}.
pattern -> string_lit : #{kind => string, value => parse_string(token_value('$1'))}.
pattern -> lparen rparen : build_pattern_ctor(<<"()">>, none).
pattern -> lbrace pattern_record_fields rbrace as_kw lower_qid :
  build_pattern_alias(build_pattern_record('$2'), token_value('$5')).
pattern -> lbrace pattern_record_fields rbrace : build_pattern_record('$2').
pattern -> upper_qid ctor_pattern_args : build_pattern_ctor_args(token_value('$1'), '$2').
pattern -> upper_qid ctor_pattern_args as_kw lower_qid :
  build_pattern_alias(build_pattern_ctor_args(token_value('$1'), '$2'), token_value('$4')).
pattern -> upper_qid : build_pattern_ctor(token_value('$1'), none).
pattern -> lbracket pattern_list_items rbracket as_kw lower_qid :
  build_pattern_alias(build_pattern_list('$2'), token_value('$5')).
pattern -> lbracket rbracket : build_pattern_ctor(<<"[]">>, none).
pattern -> lbracket pattern_list_items rbracket : build_pattern_list('$2').
pattern -> upper_qid ctor_pattern_args cons pattern :
  build_pattern_cons(build_pattern_ctor_args(token_value('$1'), '$2'), '$4').
pattern -> upper_qid cons pattern :
  build_pattern_cons(build_pattern_ctor(token_value('$1'), none), '$3').
pattern -> string_lit cons pattern :
  build_pattern_cons(#{kind => string, value => parse_string(token_value('$1'))}, '$3').
pattern -> lparen pattern comma pattern rparen cons pattern :
  build_pattern_cons(build_pattern_tuple('$2', '$4'), '$7').
pattern -> lower_qid cons pattern : build_pattern_cons(build_pattern_var(token_value('$1')), '$3').
pattern -> wildcard cons pattern : build_pattern_cons(#{kind => wildcard}, '$3').
pattern -> lparen pattern rparen as_kw lower_qid : build_pattern_alias('$2', token_value('$5')).
pattern -> lparen pattern rparen : '$2'.
pattern -> lparen pattern comma pattern comma pattern rparen :
  build_pattern_tuple('$2', build_pattern_tuple('$4', '$6')).
pattern -> lparen pattern comma pattern rparen : build_pattern_tuple('$2', '$4').

ctor_pattern_args -> pattern_arg ctor_pattern_args : ['$1' | '$2'].
ctor_pattern_args -> pattern_arg : ['$1'].

pattern_arg -> wildcard : #{kind => wildcard}.
pattern_arg -> lower_qid : build_pattern_var(token_value('$1')).
pattern_arg -> int_lit : #{kind => int, value => token_value('$1')}.
pattern_arg -> char_lit : #{kind => int, value => parse_char(token_value('$1'))}.
pattern_arg -> string_lit : #{kind => string, value => parse_string(token_value('$1'))}.
pattern_arg -> upper_qid : build_pattern_ctor(token_value('$1'), none).
pattern_arg -> lparen rparen : build_pattern_ctor(<<"()">>, none).
pattern_arg -> lbrace pattern_record_fields rbrace : build_pattern_record('$2').
pattern_arg -> lbracket rbracket : build_pattern_ctor(<<"[]">>, none).
pattern_arg -> lbracket pattern_list_items rbracket : build_pattern_list('$2').
pattern_arg -> lparen pattern rparen : '$2'.
pattern_arg -> lparen pattern comma pattern comma pattern rparen :
  build_pattern_tuple('$2', build_pattern_tuple('$4', '$6')).
pattern_arg -> lparen pattern comma pattern rparen : build_pattern_tuple('$2', '$4').

lambda_expr -> bslash lambda_args arrow pipe_right_expr : build_lambda_args('$2', '$4').

lambda_args -> lambda_arg lambda_args : ['$1' | '$2'].
lambda_args -> lambda_arg : ['$1'].

lambda_arg -> lower_qid : token_value('$1').
lambda_arg -> wildcard : <<"_">>.
lambda_arg -> lparen rparen : <<"unitArg">>.
lambda_arg -> lbrace pattern_record_fields rbrace : {record, '$2'}.
lambda_arg -> lparen lower_qid comma wildcard rparen : {tuple2_wild_right, token_value('$2')}.
lambda_arg -> lparen wildcard comma lower_qid rparen : {tuple2_wild_left, token_value('$4')}.
lambda_arg -> lparen lower_qid comma lower_qid rparen : {tuple2, token_value('$2'), token_value('$4')}.
lambda_arg -> lparen lower_qid comma lower_qid comma lower_qid rparen :
  {tuple3, token_value('$2'), token_value('$4'), token_value('$6')}.
lambda_arg -> lparen pattern rparen : {pattern, '$2'}.

compare_expr -> cons_expr compare_op cons_expr : build_compare('$1', '$2', '$3').
compare_expr -> cons_expr gte cons_expr : build_gte('$1', '$3').
compare_expr -> cons_expr lte cons_expr : build_lte('$1', '$3').
compare_expr -> cons_expr neq cons_expr : build_neq('$1', '$3').
compare_expr -> cons_expr : '$1'.

cons_expr -> append_expr cons cons_expr : build_cons_expr('$1', '$3').
cons_expr -> append_expr : '$1'.

append_expr -> add_expr append append_expr : build_append_expr('$1', '$3').
append_expr -> add_expr : '$1'.

compare_op -> eqeq : eq.
compare_op -> gt : gt.
compare_op -> lt : lt.

add_expr -> add_expr plus mul_expr : build_add('$1', '$3').
add_expr -> add_expr minus mul_expr : build_sub('$1', '$3').
add_expr -> mul_expr : '$1'.

mul_expr -> mul_expr times pow_expr : build_mul('$1', '$3').
mul_expr -> mul_expr divide pow_expr : build_div('$1', '$3').
mul_expr -> mul_expr int_div pow_expr : build_int_div('$1', '$3').
mul_expr -> pow_expr : '$1'.

pow_expr -> app_expr pow pow_expr : build_pow('$1', '$3').
pow_expr -> app_expr : '$1'.

app_expr -> app_expr atom : build_app('$1', ['$2']).
app_expr -> atom : '$1'.

atom -> int_lit : #{op => int_literal, value => token_value('$1')}.
atom -> float_lit : #{op => float_literal, value => token_value('$1')}.
atom -> string_lit : #{op => string_literal, value => parse_string(token_value('$1'))}.
atom -> char_lit : #{op => char_literal, value => parse_char(token_value('$1'))}.
atom -> field_accessor : build_field_accessor(token_value('$1')).
atom -> lower_qid : build_lower_qid(token_value('$1')).
atom -> upper_qid : build_upper_qid(token_value('$1')).
atom -> lparen plus rparen : build_operator_section(plus).
atom -> lparen minus rparen : build_operator_section(minus).
atom -> lparen times rparen : build_operator_section(times).
atom -> lparen pow rparen : build_operator_section(pow).
atom -> lparen eqeq rparen : build_operator_section(eqeq).
atom -> lparen neq rparen : build_operator_section(neq).
atom -> lparen lt rparen : build_operator_section(lt).
atom -> lparen lte rparen : build_operator_section(lte).
atom -> lparen gt rparen : build_operator_section(gt).
atom -> lparen gte rparen : build_operator_section(gte).
atom -> lparen shl rparen : build_operator_section(shl).
atom -> lparen shr rparen : build_operator_section(shr).
atom -> lparen cons rparen : build_operator_section(cons).
atom -> lparen apply_left rparen : build_operator_section(apply_left).
atom -> lparen pipe_dot rparen : build_operator_section(pipe_dot).
atom -> lparen pipe_eq rparen : build_operator_section(pipe_eq).
atom -> lparen rparen : #{op => constructor_ref, target => <<"()">>}.
atom -> lparen compose_name shl compose_name rparen : build_compose_left('$2', '$4').
atom -> lparen compose_name shr compose_name rparen : build_compose_right('$2', '$4').
atom -> lparen pipe_right_expr rparen : '$2'.
compose_name -> lower_qid : token_value('$1').
compose_name -> upper_qid : token_value('$1').

atom -> lparen tuple_items rparen : build_tuple('$2').
atom -> list_expr : '$1'.
atom -> record_expr : '$1'.

tuple_items -> pipe_right_expr comma pipe_right_expr comma pipe_right_expr : ['$1', '$3', '$5'].
tuple_items -> pipe_right_expr comma pipe_right_expr : ['$1', '$3'].

list_expr -> lbracket list_items rbracket : #{op => list_literal, items => '$2'}.
list_expr -> lbracket rbracket : #{op => list_literal, items => []}.

list_items -> pipe_right_expr comma list_items : ['$1' | '$3'].
list_items -> pipe_right_expr comma : ['$1'].
list_items -> pipe_right_expr : ['$1'].

record_expr -> lbrace rbrace : #{op => record_literal, fields => []}.
record_expr -> lbrace record_fields rbrace : #{op => record_literal, fields => '$2'}.
record_expr -> lbrace lower_qid pipe record_fields rbrace :
  #{op => record_update, base => #{op => var, name => token_value('$2')}, fields => '$4'}.

record_fields -> record_field comma record_fields : ['$1' | '$3'].
record_fields -> record_field comma : ['$1'].
record_fields -> record_field : ['$1'].

record_field -> lower_qid eq pipe_right_expr : build_record_field(token_value('$1'), '$3').

pattern_record_fields -> lower_qid comma pattern_record_fields : [token_value('$1') | '$3'].
pattern_record_fields -> lower_qid comma : [token_value('$1')].
pattern_record_fields -> lower_qid : [token_value('$1')].

pattern_list_items -> pattern comma pattern_list_items : ['$1' | '$3'].
pattern_list_items -> pattern comma : ['$1'].
pattern_list_items -> pattern : ['$1'].

Erlang code.

token_value({_Tok, _Line, Value}) -> Value.

build_compare(#{op := var, name := Left}, Kind, Right) ->
  #{op => compare, kind => Kind, left => #{op => var, name => Left}, right => Right};
build_compare(Left, Kind, Right) ->
  #{op => compare, kind => Kind, left => Left, right => Right}.

build_add(#{op := var, name := Var}, #{op := int_literal, value := Int}) ->
  #{op => add_const, var => Var, value => Int};
build_add(#{op := var, name := Left}, #{op := var, name := Right}) ->
  #{op => add_vars, left => Left, right => Right};
build_add(Left, Right) ->
  #{op => call, name => "__add__", args => [Left, Right]}.

build_sub(#{op := var, name := Var}, #{op := int_literal, value := Int}) ->
  #{op => sub_const, var => Var, value => Int};
build_sub(Left, Right) ->
  #{op => call, name => "__sub__", args => [Left, Right]}.

build_mul(Left, Right) ->
  #{op => call, name => "__mul__", args => [Left, Right]}.

build_div(Left, Right) ->
  #{op => call, name => "__fdiv__", args => [Left, Right]}.

build_int_div(Left, Right) ->
  #{op => call, name => "__idiv__", args => [Left, Right]}.

build_pow(Left, Right) ->
  #{op => call, name => "__pow__", args => [Left, Right]}.

build_cons_expr(Head, Tail) ->
  #{op => qualified_call, target => <<"List.cons">>, args => [Head, Tail]}.

build_append_expr(Left, Right) ->
  #{op => call, name => <<"__append__">>, args => [Left, Right]}.

build_app(Base, Args) ->
  case Base of
    #{op := var, name := Name} ->
      #{op => call, name => Name, args => Args};
    #{op := qualified_ref, target := Target} ->
      #{op => qualified_call, target => Target, args => Args};
    #{op := constructor_ref, target := Target} ->
      #{op => constructor_call, target => Target, args => Args};
    #{op := call, name := Name, args := ExistingArgs} ->
      #{op => call, name => Name, args => ExistingArgs ++ Args};
    #{op := qualified_call, target := Target, args := ExistingArgs} ->
      #{op => qualified_call, target => Target, args => ExistingArgs ++ Args};
    #{op := constructor_call, target := Target, args := ExistingArgs} ->
      #{op => constructor_call, target => Target, args => ExistingArgs ++ Args};
    #{op := field_access, arg := Arg, field := Field} ->
      #{op => field_call, arg => Arg, field => Field, args => Args};
    #{op := field_call, arg := Arg, field := Field, args := ExistingArgs} ->
      #{op => field_call, arg => Arg, field => Field, args => ExistingArgs ++ Args};
    #{op := compose_left, f := F, g := G} ->
      case Args of
        [Arg | Rest] ->
          First = build_named_call(F, [build_named_call(G, [Arg])]),
          case Rest of
            [] -> First;
            _ -> build_app(First, Rest)
          end;
        [] ->
          #{op => call, name => <<"__apply__">>, args => [Base]}
      end;
    #{op := compose_right, f := F, g := G} ->
      case Args of
        [Arg | Rest] ->
          First = build_named_call(G, [build_named_call(F, [Arg])]),
          case Rest of
            [] -> First;
            _ -> build_app(First, Rest)
          end;
        [] ->
          #{op => call, name => <<"__apply__">>, args => [Base]}
      end;
    _ ->
      #{op => call, name => "__apply__", args => [Base | Args]}
  end.

build_let(Name, ValueExpr, InExpr) ->
  case binary:match(Name, <<".">>) of
    nomatch -> #{op => let_in, name => Name, value_expr => ValueExpr, in_expr => InExpr};
    _ -> #{op => unsupported, source => Name}
  end.

build_let_bindings([], InExpr) ->
  InExpr;
build_let_bindings([{tuple2_bind, Left, Right, ValueExpr}], InExpr) ->
  TmpName = make_tuple_bind_name([Left, Right]),
  TmpVar = #{op => var, name => TmpName},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TmpVar]},
  SecondExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TmpVar]},
  build_let(TmpName, ValueExpr, build_let(Left, FirstExpr, build_let(Right, SecondExpr, InExpr)));
build_let_bindings([{tuple3_bind, Left, Middle, Right, ValueExpr}], InExpr) ->
  TmpName = make_tuple_bind_name([Left, Middle, Right]),
  TmpVar = #{op => var, name => TmpName},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TmpVar]},
  TailExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TmpVar]},
  MiddleExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TailExpr]},
  RightExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TailExpr]},
  build_let(
    TmpName,
    ValueExpr,
    build_let(Left, FirstExpr, build_let(Middle, MiddleExpr, build_let(Right, RightExpr, InExpr)))
  );
build_let_bindings([{pattern_bind, Pattern, ValueExpr}], InExpr) ->
  TmpName = make_pattern_bind_name(Pattern),
  CaseExpr = #{op => 'case', subject => #{op => var, name => TmpName}, branches => [#{pattern => Pattern, expr => InExpr}]},
  build_let(TmpName, ValueExpr, CaseExpr);
build_let_bindings([{Name, ValueExpr}], InExpr) ->
  build_let(Name, ValueExpr, InExpr);
build_let_bindings([{tuple2_bind, Left, Right, ValueExpr} | Rest], InExpr) ->
  TmpName = make_tuple_bind_name([Left, Right]),
  TmpVar = #{op => var, name => TmpName},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TmpVar]},
  SecondExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TmpVar]},
  build_let(
    TmpName,
    ValueExpr,
    build_let(Left, FirstExpr, build_let(Right, SecondExpr, build_let_bindings(Rest, InExpr)))
  );
build_let_bindings([{tuple3_bind, Left, Middle, Right, ValueExpr} | Rest], InExpr) ->
  TmpName = make_tuple_bind_name([Left, Middle, Right]),
  TmpVar = #{op => var, name => TmpName},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TmpVar]},
  TailExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TmpVar]},
  MiddleExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TailExpr]},
  RightExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TailExpr]},
  build_let(
    TmpName,
    ValueExpr,
    build_let(
      Left,
      FirstExpr,
      build_let(Middle, MiddleExpr, build_let(Right, RightExpr, build_let_bindings(Rest, InExpr)))
    )
  );
build_let_bindings([{pattern_bind, Pattern, ValueExpr} | Rest], InExpr) ->
  TmpName = make_pattern_bind_name(Pattern),
  CaseExpr = #{
    op => 'case',
    subject => #{op => var, name => TmpName},
    branches => [#{pattern => Pattern, expr => build_let_bindings(Rest, InExpr)}]
  },
  build_let(TmpName, ValueExpr, CaseExpr);
build_let_bindings([{Name, ValueExpr} | Rest], InExpr) ->
  build_let(Name, ValueExpr, build_let_bindings(Rest, InExpr)).

make_tuple_bind_name(Names) ->
  NameLists = lists:map(fun binary_to_list/1, Names),
  Suffix = lists:join("_", NameLists),
  list_to_binary("__tupleBind_" ++ Suffix).

make_pattern_bind_name(Pattern) ->
  Hash = integer_to_list(erlang:phash2(Pattern)),
  list_to_binary("__patternBind_" ++ Hash).

build_if(CondExpr, ThenExpr, ElseExpr) ->
  #{op => 'if', 'cond' => CondExpr, then_expr => ThenExpr, else_expr => ElseExpr}.

build_or(Left, Right) ->
  #{op => 'if', 'cond' => Left, then_expr => #{op => constructor_ref, target => <<"True">>}, else_expr => Right}.

build_and(Left, Right) ->
  #{op => 'if', 'cond' => Left, then_expr => Right, else_expr => #{op => constructor_ref, target => <<"False">>}}.

build_apply_left(FnExpr, ArgExpr) ->
  build_app(FnExpr, [ArgExpr]).

build_pipe_right(ArgExpr, FnExpr) ->
  build_app(FnExpr, [ArgExpr]).

build_pipe_dot(LeftExpr, RightExpr) ->
  #{op => call, name => <<"|.">>, args => [LeftExpr, RightExpr]}.

build_pipe_eq(LeftExpr, RightExpr) ->
  #{op => call, name => <<"|=">>, args => [LeftExpr, RightExpr]}.

build_gte(Left, Right) ->
  build_or(build_compare(Left, gt, Right), build_compare(Left, eq, Right)).

build_lte(Left, Right) ->
  build_or(build_compare(Left, lt, Right), build_compare(Left, eq, Right)).

build_neq(Left, Right) ->
  #{op => call, name => <<"not">>, args => [build_compare(Left, eq, Right)]}.

build_case(#{op := var, name := Subject}, Branches) ->
  #{op => 'case', subject => Subject, branches => Branches};
build_case(SubjectExpr, Branches) ->
  #{
    op => let_in,
    name => <<"caseSubject">>,
    value_expr => SubjectExpr,
    in_expr => #{op => 'case', subject => <<"caseSubject">>, branches => Branches}
  }.

build_pattern_var(Name) ->
  case binary:match(Name, <<".">>) of
    nomatch -> #{kind => var, name => Name};
    _ -> #{kind => unknown, source => Name}
  end.

build_pattern_ctor(Name, none) ->
  #{kind => constructor, name => Name, bind => nil, arg_pattern => nil};
build_pattern_ctor(Name, #{kind := wildcard} = WildcardPattern) ->
  #{kind => constructor, name => Name, bind => nil, arg_pattern => WildcardPattern};
build_pattern_ctor(Name, #{kind := var, name := BindName}) ->
  #{kind => constructor, name => Name, bind => BindName, arg_pattern => nil};
build_pattern_ctor(Name, ArgPattern) ->
  #{kind => constructor, name => Name, bind => nil, arg_pattern => ArgPattern}.

build_pattern_ctor_args(Name, [Arg]) ->
  build_pattern_ctor(Name, Arg);
build_pattern_ctor_args(Name, Args) ->
  #{kind => constructor, name => Name, bind => nil, arg_pattern => build_pattern_arg_tuple(Args)}.

build_pattern_tuple(Left, Right) ->
  #{kind => tuple, elements => [Left, Right]}.

build_pattern_arg_tuple([Left, Right]) ->
  build_pattern_tuple(Left, Right);
build_pattern_arg_tuple([Head | Tail]) ->
  build_pattern_tuple(Head, build_pattern_arg_tuple(Tail)).

build_pattern_cons(HeadPattern, TailPattern) ->
  #{
    kind => constructor,
    name => <<"::">>,
    bind => nil,
    arg_pattern => #{kind => tuple, elements => [HeadPattern, TailPattern]}
  }.

build_pattern_list(Patterns) ->
  lists:foldr(
    fun(Head, Tail) -> build_pattern_cons(Head, Tail) end,
    build_pattern_ctor(<<"[]">>, none),
    Patterns
  ).

build_pattern_record(Fields) ->
  #{kind => record, fields => Fields, bind => nil}.

build_pattern_alias(Pattern, Alias) ->
  maps:put(bind, Alias, Pattern).

build_record_field(Name, Expr) ->
  case binary:match(Name, <<".">>) of
    nomatch -> #{name => Name, expr => Expr};
    _ -> #{name => <<"_invalid">>, expr => #{op => unsupported, source => Name}}
  end.

build_lambda(Arg, Body) ->
  case binary:match(Arg, <<".">>) of
    nomatch ->
      #{op => lambda, args => [Arg], body => Body};
    _ ->
      #{op => unsupported, source => Arg}
  end.

build_lambda_args(Args, Body) ->
  NormalizedArgs = normalize_lambda_args(Args),
  build_lambda_chain(NormalizedArgs, Body).

normalize_lambda_args(Args) ->
  normalize_lambda_args(Args, 1, []).

normalize_lambda_args([], _Counter, Acc) ->
  lists:reverse(Acc);
normalize_lambda_args([<<"_">> | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"ignoredArg">>;
      _ -> list_to_binary("ignoredArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(Rest, Counter + 1, [{simple, Placeholder} | Acc]);
normalize_lambda_args([{record, Fields} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"recordArg">>;
      _ -> list_to_binary("recordArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(Rest, Counter + 1, [{record, Placeholder, Fields} | Acc]);
normalize_lambda_args([{pattern, Pattern} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"patternArg">>;
      _ -> list_to_binary("patternArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(Rest, Counter + 1, [{pattern, Placeholder, Pattern} | Acc]);
normalize_lambda_args([{tuple2_wild_right, Left} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(Rest, Counter + 1, [{tuple2_wild_right, Placeholder, Left} | Acc]);
normalize_lambda_args([{tuple2_wild_left, Right} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(Rest, Counter + 1, [{tuple2_wild_left, Placeholder, Right} | Acc]);
normalize_lambda_args([{tuple2, Left, Right} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(Rest, Counter + 1, [{tuple2, Placeholder, Left, Right} | Acc]);
normalize_lambda_args([{tuple3, Left, Middle, Right} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(
    Rest,
    Counter + 1,
    [{tuple3, Placeholder, Left, Middle, Right} | Acc]
  );
normalize_lambda_args([Arg | Rest], Counter, Acc) ->
  normalize_lambda_args(Rest, Counter + 1, [{simple, Arg} | Acc]).

build_lambda_chain([ArgSpec], Body) ->
  build_lambda_spec(ArgSpec, Body);
build_lambda_chain([ArgSpec | Rest], Body) ->
  build_lambda_spec(ArgSpec, build_lambda_chain(Rest, Body)).

build_lambda_spec({simple, Arg}, Body) ->
  build_lambda(Arg, Body);
build_lambda_spec({record, Placeholder, Fields}, Body) ->
  ExpandedBody = build_record_pattern_lets(Fields, Placeholder, Body),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({pattern, Placeholder, Pattern}, Body) ->
  ExpandedBody = build_pattern_bind_body(Pattern, Placeholder, Body),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple2_wild_right, Placeholder, Left}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [PlaceholderVar]},
  ExpandedBody = build_let(Left, FirstExpr, Body),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple2_wild_left, Placeholder, Right}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  SecondExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [PlaceholderVar]},
  ExpandedBody = build_let(Right, SecondExpr, Body),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple2, Placeholder, Left, Right}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [PlaceholderVar]},
  SecondExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [PlaceholderVar]},
  ExpandedBody = build_let(Left, FirstExpr, build_let(Right, SecondExpr, Body)),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple3, Placeholder, Left, Middle, Right}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [PlaceholderVar]},
  TailExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [PlaceholderVar]},
  MiddleExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TailExpr]},
  RightExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TailExpr]},
  ExpandedBody =
    build_let(
      Left,
      FirstExpr,
      build_let(Middle, MiddleExpr, build_let(Right, RightExpr, Body))
    ),
  build_lambda(Placeholder, ExpandedBody).

build_record_pattern_lets([], _Placeholder, Body) ->
  Body;
build_record_pattern_lets([Field | Rest], Placeholder, Body) ->
  FieldExpr = #{op => field_access, arg => Placeholder, field => Field},
  build_let(Field, FieldExpr, build_record_pattern_lets(Rest, Placeholder, Body)).

build_pattern_bind_body(Pattern, Placeholder, Body) ->
  #{op => 'case', subject => #{op => var, name => Placeholder}, branches => [#{pattern => Pattern, expr => Body}]}.

build_lower_qid(Text) ->
  case binary:split(Text, <<".">>, [global]) of
    [Name] ->
      #{op => var, name => Name};
    [Arg, Field] ->
      case starts_upper(Field) of
        true -> #{op => qualified_ref, target => Text};
        false -> #{op => field_access, arg => Arg, field => Field}
      end;
    _ ->
      #{op => qualified_ref, target => Text}
  end.

build_upper_qid(Text) ->
  case has_lower_segment(Text) of
    true -> #{op => qualified_ref, target => Text};
    false -> #{op => constructor_ref, target => Text}
  end.

build_field_accessor(<<$., Rest/binary>>) ->
  Arg = <<"fieldAccessorArg">>,
  #{
    op => lambda,
    args => [Arg],
    body => #{op => field_access, arg => Arg, field => Rest}
  };
build_field_accessor(Text) ->
  #{op => unsupported, source => Text}.

has_lower_segment(Text) ->
  Segments = binary:split(Text, <<".">>, [global]),
  lists:any(fun(Seg) -> not starts_upper(Seg) end, Segments).

starts_upper(<<C, _/binary>>) when C >= $A, C =< $Z -> true;
starts_upper(_) -> false.

build_tuple([A, B]) ->
  #{op => tuple2, left => A, right => B};
build_tuple([A, B, C]) ->
  #{op => tuple2, left => A, right => #{op => tuple2, left => B, right => C}}.

build_operator_section(plus) ->
  #{op => var, name => <<"__add__">>};
build_operator_section(minus) ->
  #{op => var, name => <<"__sub__">>};
build_operator_section(times) ->
  #{op => var, name => <<"__mul__">>};
build_operator_section(pow) ->
  #{op => var, name => <<"^">>};
build_operator_section(eqeq) ->
  #{op => var, name => <<"__eq__">>};
build_operator_section(neq) ->
  #{op => var, name => <<"__neq__">>};
build_operator_section(lt) ->
  #{op => var, name => <<"__lt__">>};
build_operator_section(lte) ->
  #{op => var, name => <<"__lte__">>};
build_operator_section(gt) ->
  #{op => var, name => <<"__gt__">>};
build_operator_section(gte) ->
  #{op => var, name => <<"__gte__">>};
build_operator_section(shl) ->
  #{op => var, name => <<"<<">>};
build_operator_section(shr) ->
  #{op => var, name => <<">>">>};
build_operator_section(cons) ->
  #{op => qualified_ref, target => <<"List.cons">>};
build_operator_section(apply_left) ->
  #{op => var, name => <<"<|">>};
build_operator_section(pipe_dot) ->
  #{op => var, name => <<"|.">>};
build_operator_section(pipe_eq) ->
  #{op => var, name => <<"|=">>}.

build_compose_left(F, G) ->
  #{op => compose_left, f => F, g => G}.

build_compose_right(F, G) ->
  #{op => compose_right, f => F, g => G}.

build_named_call(Name, Args) ->
  case binary:match(Name, <<".">>) of
    nomatch -> #{op => call, name => Name, args => Args};
    _ -> #{op => qualified_call, target => Name, args => Args}
  end.

parse_string(Text) ->
  Inner = binary:part(Text, 1, byte_size(Text) - 2),
  unescape(Inner).

parse_char(Text) ->
  Inner = binary:part(Text, 1, byte_size(Text) - 2),
  case binary_to_list(unescape(Inner)) of
    [Code] -> Code;
    _ -> 0
  end.

unescape(Bin) ->
  Bin1 = binary:replace(Bin, <<"\\n">>, <<"\n">>, [global]),
  Bin2 = binary:replace(Bin1, <<"\\r">>, <<"\r">>, [global]),
  Bin3 = binary:replace(Bin2, <<"\\t">>, <<"\t">>, [global]),
  Bin4 = binary:replace(Bin3, <<"\\\"">>, <<"\"">>, [global]),
  Bin5 = binary:replace(Bin4, <<"\\'">>, <<"'">>, [global]),
  binary:replace(Bin5, <<"\\\\">>, <<"\\">>, [global]).
