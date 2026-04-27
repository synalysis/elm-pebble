Nonterminals root lines line module_line import_line module_prefix exposing_opt exposing_clause exposing_body exposing_items exposing_items_rest exposing_item import_tail import_alias_opt import_exposing_opt nls.
Terminals module_kw effect_kw import_kw as_kw exposing_kw port_kw upper_id lower_id dotdot comma lparen rparen newline.

Rootsymbol root.

root -> lines : '$1'.

lines -> newline lines : '$2'.
lines -> newline : [].
lines -> line newline lines : merge_line('$1', '$3').
lines -> line newline : merge_line('$1', []).
lines -> line : merge_line('$1', []).

line -> module_line : '$1'.
line -> import_line : '$1'.

module_line -> module_prefix exposing_opt : {module, '$1', '$2'}.
import_line -> import_kw upper_id import_tail : {import, token_text('$2'), '$3'}.

module_prefix -> module_kw upper_id : token_text('$2').
module_prefix -> port_kw module_kw upper_id : token_text('$3').
module_prefix -> effect_kw module_kw upper_id : token_text('$3').

exposing_opt -> exposing_clause : '$1'.
exposing_opt -> '$empty' : nil.

exposing_clause -> exposing_kw nls lparen nls exposing_body nls rparen : '$5'.

exposing_body -> dotdot : <<"..">>.
exposing_body -> exposing_items : '$1'.

exposing_items -> exposing_item exposing_items_rest : ['$1' | '$2'].

exposing_items_rest -> comma nls exposing_item exposing_items_rest : ['$3' | '$4'].
exposing_items_rest -> '$empty' : [].

exposing_item -> lower_id : token_text('$1').
exposing_item -> upper_id : token_text('$1').
exposing_item -> upper_id lparen dotdot rparen :
  <<(token_text('$1'))/binary, "(..)">>.

import_tail -> import_alias_opt import_exposing_opt : #{as => '$1', exposing => '$2'}.

import_alias_opt -> as_kw upper_id : token_text('$2').
import_alias_opt -> '$empty' : nil.

import_exposing_opt -> exposing_clause : '$1'.
import_exposing_opt -> '$empty' : nil.

nls -> newline nls : ok.
nls -> '$empty' : ok.

Erlang code.

merge_line(none, Rest) -> Rest;
merge_line(Item, Rest) -> [Item | Rest].

token_text({_Token, _Line, Text}) -> Text.
