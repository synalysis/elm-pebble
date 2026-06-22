Nonterminals let_expr let_bindings let_binding if_expr case_expr case_after_of case_branches case_branch pattern pattern_arg ctor_pattern_args
             lambda_expr lambda_args lambda_arg pipe_right_expr plain_pipe_expr apply_left_expr bool_or_expr bool_and_expr compare_expr compare_op cons_expr append_expr add_expr mul_expr pow_expr app_expr primary opt_field_accessor list_expr
             list_items tuple_items record_expr record_fields record_field pattern_record_fields pattern_list_items.
Terminals lparen rparen lbracket rbracket lbrace rbrace comma semicolon cons append plus minus shl shr pipe_right pipe apply_left eq eqeq gt lt gte lte neq bslash arrow
         times pow int_div divide pipe_dot pipe_eq
          andand oror let_kw in_kw if_kw then_kw else_kw case_kw of_kw as_kw wildcard
         int_lit float_lit string_lit char_lit field_accessor lower_qid upper_qid case_sep.

%% Operator precedence (lowest number = loosest binding). Rule precedence is taken
%% from the rightmost terminal on each production unless a nonterminal carries Unary.
Right 100 cons.
Right 110 append.
Left 120 oror.
Left 130 andand.
Nonassoc 140 eqeq gt lt gte lte neq.
Left 150 plus minus.
Left 160 times divide int_div.
Right 170 pow.
Left 180 shl shr.
Left 190 apply_left.
Left 200 pipe_right pipe_dot pipe_eq.
Unary 210 primary.
Left 220 case_sep.
Left 225 field_accessor.

Rootsymbol pipe_right_expr.
%% Shift/reduce ambiguities (pipes, composition, field access, case) are resolved
%% by the precedence declarations above. Expect matches the current conflict count.
Expect 25.

pipe_right_expr -> let_expr : '$1'.
pipe_right_expr -> if_expr : '$1'.
pipe_right_expr -> case_expr : '$1'.
pipe_right_expr -> lambda_expr : '$1'.
pipe_right_expr -> plain_pipe_expr : '$1'.

plain_pipe_expr -> plain_pipe_expr pipe_right apply_left_expr : build_pipe_right('$1', '$3').
plain_pipe_expr -> plain_pipe_expr pipe_dot apply_left_expr : build_pipe_dot('$1', '$3').
plain_pipe_expr -> plain_pipe_expr pipe_eq apply_left_expr : build_pipe_eq('$1', '$3').
plain_pipe_expr -> apply_left_expr : '$1'.

apply_left_expr -> apply_left_expr shr apply_left_expr : build_compose_right('$1', '$3').
apply_left_expr -> apply_left_expr shl apply_left_expr : build_compose_left('$1', '$3').
apply_left_expr -> bool_or_expr apply_left pipe_right_expr : build_apply_left('$1', '$3').
apply_left_expr -> bool_or_expr : '$1'.

bool_or_expr -> bool_and_expr oror bool_or_expr : build_or('$1', '$3').
bool_or_expr -> bool_and_expr : '$1'.

bool_and_expr -> compare_expr andand bool_and_expr : build_and('$1', '$3').
bool_and_expr -> compare_expr : '$1'.

%% Token-level let/in is accepted here; Elm layout (`in` on its own line) is enforced by
%% `ElmEx.Frontend.LetLayout.validate/1` before this parser is invoked.
let_expr -> let_kw let_bindings in_kw pipe_right_expr :
  build_let_bindings('$2', '$4').

let_bindings -> let_binding semicolon let_bindings : ['$1' | '$3'].
let_bindings -> let_binding : ['$1'].

let_binding -> lower_qid eq pipe_right_expr : {token_value('$1'), '$3'}.
let_binding -> lower_qid lambda_args eq pipe_right_expr : {token_value('$1'), build_lambda_args('$2', '$4')}.
let_binding -> lparen wildcard comma lower_qid rparen eq pipe_right_expr :
  {pattern_bind, build_pattern_tuple(#{kind => wildcard}, build_pattern_var(token_value('$4'))), '$7'}.
let_binding -> lparen lower_qid comma wildcard rparen eq pipe_right_expr :
  {pattern_bind, build_pattern_tuple(build_pattern_var(token_value('$2')), #{kind => wildcard}), '$7'}.
let_binding -> lparen wildcard comma wildcard rparen eq pipe_right_expr :
  {pattern_bind, build_pattern_tuple(#{kind => wildcard}, #{kind => wildcard}), '$7'}.
let_binding -> lparen lower_qid comma wildcard comma wildcard rparen eq pipe_right_expr :
  {pattern_bind, build_pattern_tuple(build_pattern_var(token_value('$2')), build_pattern_tuple(#{kind => wildcard}, #{kind => wildcard})), '$9'}.
let_binding -> lparen wildcard comma lower_qid comma wildcard rparen eq pipe_right_expr :
  {pattern_bind, build_pattern_tuple(#{kind => wildcard}, build_pattern_tuple(build_pattern_var(token_value('$4')), #{kind => wildcard})), '$9'}.
let_binding -> lparen wildcard comma wildcard comma lower_qid rparen eq pipe_right_expr :
  {pattern_bind, build_pattern_tuple(#{kind => wildcard}, build_pattern_tuple(#{kind => wildcard}, build_pattern_var(token_value('$6')))), '$9'}.
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

case_branches -> case_branches case_sep case_branch : '$1' ++ ['$3'].
case_branches -> case_branch : ['$1'].

case_branch -> pattern arrow pipe_right_expr : #{pattern => '$1', expr => '$3'}.

pattern -> wildcard : #{kind => wildcard}.
pattern -> lower_qid : build_pattern_var(token_value('$1')).
pattern -> int_lit : #{kind => int, value => token_value('$1')}.
pattern -> char_lit : #{kind => char, value => parse_char(token_value('$1'))}.
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
pattern -> char_lit cons pattern :
  build_pattern_cons(#{kind => char, value => parse_char(token_value('$1'))}, '$3').
pattern -> lparen pattern comma pattern rparen cons pattern :
  build_pattern_cons(build_pattern_tuple('$2', '$4'), '$7').
pattern -> lower_qid cons pattern : build_pattern_cons(build_pattern_var(token_value('$1')), '$3').
pattern -> wildcard cons pattern : build_pattern_cons(#{kind => wildcard}, '$3').
pattern -> lparen pattern rparen as_kw lower_qid : build_pattern_alias('$2', token_value('$5')).
pattern -> lparen pattern rparen cons pattern : build_pattern_cons('$2', '$5').
pattern -> lparen pattern rparen : '$2'.
pattern -> lparen pattern comma pattern comma pattern rparen :
  build_pattern_tuple('$2', build_pattern_tuple('$4', '$6')).
pattern -> lparen pattern comma pattern rparen : build_pattern_tuple('$2', '$4').

ctor_pattern_args -> pattern_arg ctor_pattern_args : ['$1' | '$2'].
ctor_pattern_args -> pattern_arg : ['$1'].

pattern_arg -> wildcard : #{kind => wildcard}.
pattern_arg -> lower_qid : build_pattern_var(token_value('$1')).
pattern_arg -> int_lit : #{kind => int, value => token_value('$1')}.
pattern_arg -> char_lit : #{kind => char, value => parse_char(token_value('$1'))}.
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
lambda_arg -> lparen wildcard comma lower_qid comma lower_qid rparen :
  {tuple3_wild_left, token_value('$4'), token_value('$6')}.
lambda_arg -> lparen lower_qid comma wildcard comma lower_qid rparen :
  {tuple3_wild_middle, token_value('$2'), token_value('$6')}.
lambda_arg -> lparen lower_qid comma lower_qid comma wildcard rparen :
  {tuple3_wild_right, token_value('$2'), token_value('$4')}.
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

app_expr -> app_expr primary : build_app('$1', ['$2']).
app_expr -> primary : '$1'.

primary -> lparen pipe_right_expr rparen opt_field_accessor :
  build_paren_primary('$2', '$4').
primary -> int_lit : #{op => int_literal, value => token_value('$1')}.
primary -> float_lit : #{op => float_literal, value => token_value('$1')}.
primary -> string_lit : #{op => string_literal, value => parse_string(token_value('$1'))}.
primary -> char_lit : #{op => char_literal, value => parse_char(token_value('$1'))}.
primary -> field_accessor : build_field_accessor(token_value('$1')).
primary -> lower_qid : build_lower_qid(token_value('$1')).
primary -> upper_qid : build_upper_qid(token_value('$1')).
primary -> lparen plus rparen : build_operator_section(plus).
primary -> lparen minus rparen : build_operator_section(minus).
primary -> lparen times rparen : build_operator_section(times).
primary -> lparen pow rparen : build_operator_section(pow).
primary -> lparen eqeq rparen : build_operator_section(eqeq).
primary -> lparen neq rparen : build_operator_section(neq).
primary -> lparen lt rparen : build_operator_section(lt).
primary -> lparen lte rparen : build_operator_section(lte).
primary -> lparen gt rparen : build_operator_section(gt).
primary -> lparen gte rparen : build_operator_section(gte).
primary -> lparen shl rparen : build_operator_section(shl).
primary -> lparen shr rparen : build_operator_section(shr).
primary -> lparen cons rparen : build_operator_section(cons).
primary -> lparen apply_left rparen : build_operator_section(apply_left).
primary -> lparen pipe_dot rparen : build_operator_section(pipe_dot).
primary -> lparen pipe_eq rparen : build_operator_section(pipe_eq).
primary -> lparen rparen : #{op => constructor_ref, target => <<"()">>}.
primary -> lparen apply_left_expr shl apply_left_expr rparen : build_compose_left('$2', '$4').
primary -> lparen apply_left_expr shr apply_left_expr rparen : build_compose_right('$2', '$4').

primary -> lparen tuple_items rparen : build_tuple('$2').
primary -> list_expr : '$1'.
primary -> record_expr : '$1'.

tuple_items -> pipe_right_expr comma pipe_right_expr comma pipe_right_expr : ['$1', '$3', '$5'].
tuple_items -> pipe_right_expr comma pipe_right_expr : ['$1', '$3'].

list_expr -> lbracket list_items rbracket : #{op => list_literal, items => '$2'}.
list_expr -> lbracket rbracket : #{op => list_literal, items => []}.

list_items -> pipe_right_expr : ['$1'].
list_items -> list_items comma pipe_right_expr : '$1' ++ ['$3'].

record_fields -> record_field : ['$1'].
record_fields -> record_fields comma record_field : '$1' ++ ['$3'].

pattern_list_items -> pattern : ['$1'].
pattern_list_items -> pattern_list_items comma pattern : '$1' ++ ['$3'].

pattern_record_fields -> lower_qid : [token_value('$1')].
pattern_record_fields -> pattern_record_fields comma lower_qid : '$1' ++ [token_value('$3')].

record_expr -> lbrace rbrace : #{op => record_literal, fields => []}.
record_expr -> lbrace record_fields rbrace : #{op => record_literal, fields => '$2'}.
record_expr -> lbrace lower_qid pipe record_fields rbrace :
  #{op => record_update, base => #{op => var, name => token_value('$2')}, fields => '$4'}.

record_field -> lower_qid eq pipe_right_expr : build_record_field(token_value('$1'), '$3').

opt_field_accessor -> field_accessor : token_value('$1').
opt_field_accessor -> '$empty' : nil.

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
      [Arg | Rest] = Args,
      First = build_expr_apply(F, build_expr_apply(G, Arg)),
      case Rest of
        [] -> First;
        _ -> build_app(First, Rest)
      end;
    #{op := compose_right, f := F, g := G} ->
      [Arg | Rest] = Args,
      First = build_expr_apply(G, build_expr_apply(F, Arg)),
      case Rest of
        [] -> First;
        _ -> build_app(First, Rest)
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
normalize_lambda_args([{tuple3_wild_left, Middle, Right} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(
    Rest,
    Counter + 1,
    [{tuple3_wild_left, Placeholder, Middle, Right} | Acc]
  );
normalize_lambda_args([{tuple3_wild_middle, Left, Right} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(
    Rest,
    Counter + 1,
    [{tuple3_wild_middle, Placeholder, Left, Right} | Acc]
  );
normalize_lambda_args([{tuple3_wild_right, Left, Middle} | Rest], Counter, Acc) ->
  Placeholder =
    case Counter of
      1 -> <<"tupleArg">>;
      _ -> list_to_binary("tupleArg" ++ integer_to_list(Counter))
    end,
  normalize_lambda_args(
    Rest,
    Counter + 1,
    [{tuple3_wild_right, Placeholder, Left, Middle} | Acc]
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
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple3_wild_left, Placeholder, Middle, Right}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  TailExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [PlaceholderVar]},
  MiddleExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TailExpr]},
  RightExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TailExpr]},
  ExpandedBody =
    build_let(Middle, MiddleExpr, build_let(Right, RightExpr, Body)),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple3_wild_middle, Placeholder, Left, Right}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [PlaceholderVar]},
  TailExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [PlaceholderVar]},
  RightExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [TailExpr]},
  ExpandedBody =
    build_let(Left, FirstExpr, build_let(Right, RightExpr, Body)),
  build_lambda(Placeholder, ExpandedBody);
build_lambda_spec({tuple3_wild_right, Placeholder, Left, Middle}, Body) ->
  PlaceholderVar = #{op => var, name => Placeholder},
  FirstExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [PlaceholderVar]},
  TailExpr = #{op => qualified_call, target => <<"Tuple.second">>, args => [PlaceholderVar]},
  MiddleExpr = #{op => qualified_call, target => <<"Tuple.first">>, args => [TailExpr]},
  ExpandedBody =
    build_let(Left, FirstExpr, build_let(Middle, MiddleExpr, Body)),
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

build_paren_primary(Expr, nil) ->
  Expr;
build_paren_primary(Expr, FieldAccessor) ->
  build_postfix_field_access(Expr, FieldAccessor).

build_postfix_field_access(Expr, <<$., Field/binary>>) ->
  #{op => field_access, arg => Expr, field => Field};
build_postfix_field_access(Expr, Text) ->
  #{op => field_access, arg => Expr, field => Text}.

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

build_expr_apply(Expr, Arg) when is_map(Expr) ->
  case Expr of
    #{op := qualified_call, target := Target, args := ExistingArgs} ->
      #{op => qualified_call, target => Target, args => ExistingArgs ++ [Arg]};
    #{op := call, name := Name, args := ExistingArgs} ->
      #{op => call, name => Name, args => ExistingArgs ++ [Arg]};
    #{op := constructor_call, target := Target, args := ExistingArgs} ->
      #{op => constructor_call, target => Target, args => ExistingArgs ++ [Arg]};
    #{op := var, name := Name} ->
      #{op => call, name => Name, args => [Arg]};
    #{op := qualified_ref, target := Target} ->
      #{op => qualified_call, target => Target, args => [Arg]};
    #{op := constructor_ref, target := Target} ->
      #{op => constructor_call, target => Target, args => [Arg]};
    _ ->
      #{op => call, name => <<"__apply__">>, args => [Expr, Arg]}
  end;
build_expr_apply(Name, Arg) when is_binary(Name) ->
  build_named_call(Name, [Arg]).

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
  case unicode:characters_to_list(unescape(Inner)) of
    [Code] when is_integer(Code) -> Code;
    _ -> 0
  end.

unescape(Bin) ->
  unescape_acc(Bin, <<>>).

unescape_acc(<<>>, Acc) ->
  Acc;
unescape_acc(<<"\\n", Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, $\n>>);
unescape_acc(<<"\\r", Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, $\r>>);
unescape_acc(<<"\\t", Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, $\t>>);
unescape_acc(<<"\\\"", Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, $">>);
unescape_acc(<<"\\'", Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, $'>>);
unescape_acc(<<"\\\\", Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, $\\>>);
unescape_acc(<<"\\u{", Rest/binary>>, Acc) ->
  case take_unicode_escape(Rest, <<>>) of
    {ok, Code, Rest2} when Code >= 0, Code =< 16#10FFFF ->
      Char = unicode:characters_to_binary([Code]),
      unescape_acc(Rest2, <<Acc/binary, Char/binary>>);
    _ ->
      unescape_acc(Rest, <<Acc/binary, "\\u{">>)
  end;
unescape_acc(<<C, Rest/binary>>, Acc) ->
  unescape_acc(Rest, <<Acc/binary, C>>).

take_unicode_escape(<<"}", Rest/binary>>, Acc) when Acc =/= <<>> ->
  try {ok, binary_to_integer(Acc, 16), Rest} catch _:_ -> error end;
take_unicode_escape(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
  take_unicode_escape(Rest, <<Acc/binary, C>>);
take_unicode_escape(<<C, Rest/binary>>, Acc) when C >= $a, C =< $f ->
  take_unicode_escape(Rest, <<Acc/binary, C>>);
take_unicode_escape(<<C, Rest/binary>>, Acc) when C >= $A, C =< $F ->
  take_unicode_escape(Rest, <<Acc/binary, C>>);
take_unicode_escape(_, _) ->
  error.
