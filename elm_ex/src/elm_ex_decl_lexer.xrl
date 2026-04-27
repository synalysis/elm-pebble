Definitions.
WS = [\s\t\r\n]+
LOWER_ID = [a-z][A-Za-z0-9_']*
UPPER_ID = [A-Z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*
WILDCARD = _

Rules.
{WS} : skip_token.
type : {token, {type_kw, TokenLine}}.
alias : {token, {alias_kw, TokenLine}}.
port : {token, {port_kw, TokenLine}}.
\-> : {token, {arrow, TokenLine}}.
\= : {token, {eq, TokenLine}}.
\| : {token, {pipe, TokenLine}}.
\: : {token, {colon, TokenLine}}.
\( : {token, {lparen, TokenLine}}.
\) : {token, {rparen, TokenLine}}.
\{ : {token, {lbrace, TokenLine}}.
\} : {token, {rbrace, TokenLine}}.
\[ : {token, {lbracket, TokenLine}}.
\] : {token, {rbracket, TokenLine}}.
\, : {token, {comma, TokenLine}}.
{UPPER_ID} : {token, {upper_id, TokenLine, list_to_binary(TokenChars)}}.
{WILDCARD} : {token, {wildcard_id, TokenLine, list_to_binary(TokenChars)}}.
{LOWER_ID} : {token, {lower_id, TokenLine, list_to_binary(TokenChars)}}.

Erlang code.
