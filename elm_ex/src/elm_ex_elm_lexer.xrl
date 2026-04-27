Definitions.
WS = [\s\t\r]+
NEWLINE = \n
MODULE = module
EFFECT = effect
IMPORT = import
AS = as
EXPOSING = exposing
PORT = port
DOTDOT = \.\.
UPPER_ID = [A-Z][A-Za-z0-9_\.]*
LOWER_ID = [a-z][A-Za-z0-9_']*

Rules.
{WS} : skip_token.
{NEWLINE}+ : {token, {newline, TokenLine}}.
{DOTDOT} : {token, {dotdot, TokenLine}}.
\, : {token, {comma, TokenLine}}.
\( : {token, {lparen, TokenLine}}.
\) : {token, {rparen, TokenLine}}.
\: : {token, {colon, TokenLine}}.
{MODULE} : {token, {module_kw, TokenLine}}.
{EFFECT} : {token, {effect_kw, TokenLine}}.
{IMPORT} : {token, {import_kw, TokenLine}}.
{AS} : {token, {as_kw, TokenLine}}.
{EXPOSING} : {token, {exposing_kw, TokenLine}}.
{PORT} : {token, {port_kw, TokenLine}}.
{UPPER_ID} : {token, {upper_id, TokenLine, list_to_binary(TokenChars)}}.
{LOWER_ID} : {token, {lower_id, TokenLine, list_to_binary(TokenChars)}}.
\-\-[^\n]* : skip_token.
. : skip_token.

Erlang code.
