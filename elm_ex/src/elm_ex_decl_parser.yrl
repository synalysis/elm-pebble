Nonterminals decl type_alias_decl union_decl constructor_decl union_constructor_seq union_constructor_item signature_decl function_header_decl port_signature_decl header_arg_list type_var_opt type_var_seq arg_opt ctor_arg_seq ctor_arg_token type_seq type_token.
Terminals type_kw alias_kw port_kw arrow eq pipe colon lower_id upper_id wildcard_id lparen rparen lbrace rbrace lbracket rbracket comma.

Rootsymbol decl.

decl -> type_alias_decl : '$1'.
decl -> union_decl : '$1'.
decl -> constructor_decl : '$1'.
decl -> signature_decl : '$1'.
decl -> port_signature_decl : '$1'.
decl -> function_header_decl : '$1'.

type_alias_decl -> type_kw alias_kw upper_id type_var_opt eq type_seq : {type_alias, token_text('$3')}.

union_decl -> type_kw upper_id type_var_opt : {union_start, token_text('$2'), none}.
union_decl -> type_kw upper_id type_var_opt eq union_constructor_seq : {union_start_many, token_text('$2'), '$5'}.

constructor_decl -> eq union_constructor_seq : {union_constructors, '$2'}.
constructor_decl -> pipe union_constructor_seq : {union_constructors, '$2'}.

union_constructor_seq -> union_constructor_item pipe union_constructor_seq : ['$1' | '$3'].
union_constructor_seq -> union_constructor_item : ['$1'].

union_constructor_item -> upper_id arg_opt : {constructor, token_text('$1'), '$2'}.

signature_decl -> lower_id colon type_seq : {function_signature, token_text('$1'), tokens_to_string('$3')}.
port_signature_decl -> port_kw lower_id colon type_seq : {port_signature, token_text('$2'), tokens_to_string('$4')}.

function_header_decl -> lower_id eq : {function_header, token_text('$1'), []}.
function_header_decl -> lower_id header_arg_list eq : {function_header, token_text('$1'), '$2'}.

type_var_opt -> type_var_seq : '$1'.
type_var_opt -> '$empty' : [].

type_var_seq -> lower_id type_var_seq : [token_text('$1') | '$2'].
type_var_seq -> lower_id : [token_text('$1')].

header_arg_list -> wildcard_id header_arg_list : [token_text('$1') | '$2'].
header_arg_list -> wildcard_id : [token_text('$1')].
header_arg_list -> lower_id header_arg_list : [token_text('$1') | '$2'].
header_arg_list -> lower_id : [token_text('$1')].

arg_opt -> ctor_arg_seq : tokens_to_string('$1').
arg_opt -> '$empty' : nil.

ctor_arg_seq -> ctor_arg_token ctor_arg_seq : ['$1' | '$2'].
ctor_arg_seq -> ctor_arg_token : ['$1'].

ctor_arg_token -> lower_id : '$1'.
ctor_arg_token -> upper_id : '$1'.
ctor_arg_token -> lparen : '$1'.
ctor_arg_token -> rparen : '$1'.
ctor_arg_token -> lbrace : '$1'.
ctor_arg_token -> rbrace : '$1'.
ctor_arg_token -> lbracket : '$1'.
ctor_arg_token -> rbracket : '$1'.
ctor_arg_token -> comma : '$1'.
ctor_arg_token -> arrow : '$1'.
ctor_arg_token -> colon : '$1'.

type_seq -> type_token type_seq : ['$1' | '$2'].
type_seq -> type_token : ['$1'].

type_token -> lower_id : '$1'.
type_token -> upper_id : '$1'.
type_token -> lparen : '$1'.
type_token -> rparen : '$1'.
type_token -> lbrace : '$1'.
type_token -> rbrace : '$1'.
type_token -> lbracket : '$1'.
type_token -> rbracket : '$1'.
type_token -> comma : '$1'.
type_token -> arrow : '$1'.
type_token -> colon : '$1'.
type_token -> pipe : '$1'.

Erlang code.
token_text({lower_id, _Line, Value}) -> Value;
token_text({upper_id, _Line, Value}) -> Value;
token_text({wildcard_id, _Line, Value}) -> Value;
token_text({lparen, _Line}) -> <<"(">>;
token_text({rparen, _Line}) -> <<")">>;
token_text({lbrace, _Line}) -> <<"{">>;
token_text({rbrace, _Line}) -> <<"}">>;
token_text({lbracket, _Line}) -> <<"[">>;
token_text({rbracket, _Line}) -> <<"]">>;
token_text({comma, _Line}) -> <<",">>;
token_text({arrow, _Line}) -> <<"->">>;
token_text({colon, _Line}) -> <<":">>;
token_text({pipe, _Line}) -> <<"|">>.

tokens_to_string(Tokens) ->
  list_to_binary(join_tokens([token_text(T) || T <- Tokens], [])).

join_tokens([], Acc) ->
  lists:reverse(Acc);
join_tokens([Tok], Acc) ->
  lists:reverse([Tok | Acc]);
join_tokens([Tok, Next | Rest], Acc) ->
  NeedsSpace = needs_space(Tok, Next),
  NewAcc =
    case NeedsSpace of
      true -> [<<" ">>, Tok | Acc];
      false -> [Tok | Acc]
    end,
  join_tokens([Next | Rest], NewAcc).

needs_space(<<",">>, _) -> true;
needs_space(<<"(">>, _) -> false;
needs_space(_, <<")">>) -> false;
needs_space(<<"{">>, _) -> false;
needs_space(_, <<"}">>) -> false;
needs_space(<<"[">>, _) -> false;
needs_space(_, <<"]">>) -> false;
needs_space(_, <<",">>) -> false;
needs_space(_, <<":">>) -> true;
needs_space(_, <<"|">>) -> true;
needs_space(_, _) -> true.
