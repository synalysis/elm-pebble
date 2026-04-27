Definitions.
WS = [\s\t\r\n]+
FLOAT_DEC = -?[0-9]+\.[0-9]+([eE][\+\-]?[0-9]+)?
FLOAT_EXP = -?[0-9]+[eE][\+\-]?[0-9]+
HEX = 0x[0-9A-Fa-f]+
INT = -?[0-9]+
FIELD = [a-z][A-Za-z0-9_]*
LOWER_QID = [a-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*
UPPER_QID = [A-Z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*
STRING = \"([^\"\\]|\\.)*\"
CHAR = \'([^'\\]|\\.)\'

Rules.
{WS} : skip_token.
let : {token, {let_kw, TokenLine}}.
in : {token, {in_kw, TokenLine}}.
if : {token, {if_kw, TokenLine}}.
then : {token, {then_kw, TokenLine}}.
else : {token, {else_kw, TokenLine}}.
case : {token, {case_kw, TokenLine}}.
of : {token, {of_kw, TokenLine}}.
as : {token, {as_kw, TokenLine}}.
_ : {token, {wildcard, TokenLine}}.
\( : {token, {lparen, TokenLine}}.
\) : {token, {rparen, TokenLine}}.
\[ : {token, {lbracket, TokenLine}}.
\] : {token, {rbracket, TokenLine}}.
\{ : {token, {lbrace, TokenLine}}.
\} : {token, {rbrace, TokenLine}}.
\; : {token, {semicolon, TokenLine}}.
:: : {token, {cons, TokenLine}}.
\/= : {token, {neq, TokenLine}}.
\= : {token, {eq, TokenLine}}.
\-> : {token, {arrow, TokenLine}}.
\\ : {token, {bslash, TokenLine}}.
, : {token, {comma, TokenLine}}.
\+\+ : {token, {append, TokenLine}}.
\+ : {token, {plus, TokenLine}}.
\- : {token, {minus, TokenLine}}.
\/\/ : {token, {int_div, TokenLine}}.
\/ : {token, {divide, TokenLine}}.
\* : {token, {times, TokenLine}}.
\^ : {token, {pow, TokenLine}}.
<< : {token, {shl, TokenLine}}.
>> : {token, {shr, TokenLine}}.
&& : {token, {andand, TokenLine}}.
\|\| : {token, {oror, TokenLine}}.
== : {token, {eqeq, TokenLine}}.
\|\. : {token, {pipe_dot, TokenLine}}.
\|= : {token, {pipe_eq, TokenLine}}.
\|> : {token, {pipe_right, TokenLine}}.
\| : {token, {pipe, TokenLine}}.
<\| : {token, {apply_left, TokenLine}}.
>= : {token, {gte, TokenLine}}.
<= : {token, {lte, TokenLine}}.
> : {token, {gt, TokenLine}}.
< : {token, {lt, TokenLine}}.
{FLOAT_DEC} : {token, {float_lit, TokenLine, parse_float(TokenChars)}}.
{FLOAT_EXP} : {token, {float_lit, TokenLine, parse_float(TokenChars)}}.
{HEX} : {token, {int_lit, TokenLine, parse_hex(TokenChars)}}.
{INT} : {token, {int_lit, TokenLine, list_to_integer(TokenChars)}}.
{STRING} : {token, {string_lit, TokenLine, to_binary(TokenChars)}}.
{CHAR} : {token, {char_lit, TokenLine, to_binary(TokenChars)}}.
\.{FIELD} : {token, {field_accessor, TokenLine, to_binary(TokenChars)}}.
{LOWER_QID} : {token, {lower_qid, TokenLine, to_binary(TokenChars)}}.
{UPPER_QID} : {token, {upper_qid, TokenLine, to_binary(TokenChars)}}.

Erlang code.

parse_hex([$0, $x | Digits]) ->
  list_to_integer(Digits, 16).

parse_float(TokenChars) ->
  try
    list_to_float(TokenChars)
  catch
    error:badarg ->
      list_to_float(normalize_exp_float(TokenChars))
  end.

normalize_exp_float(TokenChars) ->
  case split_exp(TokenChars) of
    {Mantissa, Exp} ->
      case lists:member($., Mantissa) of
        true -> Mantissa ++ Exp;
        false -> Mantissa ++ ".0" ++ Exp
      end;
    nomatch ->
      TokenChars
  end.

split_exp(TokenChars) ->
  case lists:splitwith(fun(C) -> C =/= $e andalso C =/= $E end, TokenChars) of
    {_Mantissa, []} ->
      nomatch;
    {Mantissa, Exp} ->
      {Mantissa, Exp}
  end.

to_binary(TokenChars) ->
  unicode:characters_to_binary(TokenChars).
