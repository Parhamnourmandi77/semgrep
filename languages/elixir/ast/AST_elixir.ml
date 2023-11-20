(* Yoann Padioleau
 *
 * Copyright (c) 2023 Semgrep Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * LICENSE for more details.
 *)
module G = AST_generic

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* AST(s) for Elixir.
 *
 * Elixir is quite an unusual language with a very flexible syntax and
 * macro system. For example, there are no 'definition' or 'declaration'
 * grammar rules; instead a definition looks really like a function call.
 * This is a bit similar to Lisp where '(defun ...)' is not part of
 * the Lisp syntax definition; 'defun' is actually a call to a
 * special construct that defines functions!
 * This is why we parse Elixir source in 2 phases:
 *  - phase 1, we parse the "Raw" constructs which roughly correspond to
 *    Lisp sexps (see Parse_elixir_tree_sitter.ml)
 *  - phase 2, we analyze those raw constructs and try to infer higher-level
 *    constructs like module definitions or function definitions that
 *    are standard in Elixir (see Elixir_to_elixir.ml), also
 *    called the "Kernel" construts.
 *
 * references:
 * - https://hexdocs.pm/elixir/syntax-reference.html
 * - https://hexdocs.pm/elixir/Kernel.html and
 *   https://hexdocs.pm/elixir/Kernel.SpecialForms.html
 *)

(*****************************************************************************)
(* Raw constructs *)
(*****************************************************************************)
(* AST constructs corresponding to "Raw" Elixir constructs.
 *
 * We try to follow the naming conventions in
 * https://hexdocs.pm/elixir/syntax-reference.html
 *)

(* ------------------------------------------------------------------------- *)
(* Tokens *)
(* ------------------------------------------------------------------------- *)
type 'a wrap = 'a * Tok.t [@@deriving show]
type 'a bracket = Tok.t * 'a * Tok.t [@@deriving show]

(* ------------------------------------------------------------------------- *)
(* Names *)
(* ------------------------------------------------------------------------- *)

type ident =
  (* lowercase ident *)
  | Id of string wrap
  (* actually part of Elixir! *)
  | IdEllipsis of Tok.t (* '...' *)
  (* semgrep-ext: *)
  | IdMetavar of string wrap
[@@deriving show { with_path = false }]

(* uppercase ident; constructs that expand to atoms at compile-time
 * TODO: seems like it contain contains string with dots! Foo.Bar is
 * parsed as a single alias, so maybe we need to inspect it and split it.
 *)
type alias = string wrap [@@deriving show]

(* ref: https://hexdocs.pm/elixir/operators.html *)
type operator =
  (* special forms operators that cannot be overriden *)
  | OPin (* ^ *)
  | ODot (* . *)
  | OMatch (* = *)
  | OCapture (* & *)
  | OType (* :: *)
  (* strict boolean variants *)
  | OStrictAnd
  | OStrictOr
  | OStrictNot
  (* other operators *)
  | OPipeline (* |> *)
  | OModuleAttr (* @ *)
  | OLeftArrow (* <-, used with 'for' and 'with'  *)
  | ODefault (* \\, default argument *)
  | ORightArrow (* -> *)
  | OCons (* |, =~ "::" in OCaml (comes from Erlang/Prolog) *)
  | OWhen (* when, in guards *)
  | O of G.operator
  (* lots of operators here, +++, ---, etc. *)
  | OOther of string
[@@deriving show { with_path = false }]

type ident_or_operator = (ident, operator wrap) Common.either [@@deriving show]

(* ------------------------------------------------------------------------- *)
(* Visitor *)
(* ------------------------------------------------------------------------- *)
(* Used as a parent class for the map visitor autogenerated
 * at the end of the big recursive type via @@deriving visitors.
 *)
class virtual ['self] map_parent =
  object (self : 'self)
    (* Handcoded visitor methods.
     * alt: we could use deriving visitors at the definition site too.
     *)
    method visit_wrap : 'a. ('env -> 'a -> 'a) -> 'env -> 'a wrap -> 'a wrap =
      fun f env (x, tok) ->
        let x = f env x in
        let tok = self#visit_t env tok in
        (x, tok)

    method visit_bracket
        : 'a. ('env -> 'a -> 'a) -> 'env -> 'a bracket -> 'a bracket =
      fun f env (left, x, right) ->
        let left = self#visit_t env left in
        let x = f env x in
        let right = self#visit_t env right in
        (left, x, right)

    method visit_either f1 f2 env x =
      match x with
      | Common.Left a -> Common.Left (f1 env a)
      | Common.Right b -> Common.Right (f2 env b)

    (* Stubs *)
    method visit_t _env x = x
    method visit_ident _env x = x
    method visit_alias _env x = x
    method visit_ident_or_operator _env x = x

    (* stubs for AST_generic types *)
    method visit_literal _env x = x
    method visit_operator _env x = x
    method visit_parsed_int _env x = x
  end

(* ------------------------------------------------------------------------- *)
(* Start of big mutually recursive types *)
(* ------------------------------------------------------------------------- *)
(* Recursive types because atoms can contain interpolated exprs *)

(* TODO: need extract ':' for simple ident case *)
type atom = Tok.t (* ':' *) * string__wrap__or_quoted

(* TODO: need to extract the ':' for the ident case *)
and keyword = string__wrap__or_quoted * Tok.t (* : *)

(* ideally we would use this generic type:
 *   and 'a or_quoted =
 *     | X of 'a
 *     | Quoted of quoted
 * instead of X1 (and X2 further below), but the visitors ppx
 * can't handle such type and return an error "or_quoted is irregular"
 * so we monomorphize it instead.
 *)
and string__wrap__or_quoted = X1 of string wrap | Quoted1 of quoted
and quoted = (string wrap, expr bracket) Common.either list bracket

(* ------------------------------------------------------------------------- *)
(* Keywords and arguments *)
(* ------------------------------------------------------------------------- *)
(* inside calls and stab_clause *)
and arguments = expr list * keywords

(* inside containers (list, bits, maps, tuples), separated by commas *)
and items = expr list * keywords

(* Elixir semantic is to unsugar in regular (atom, expr) pair *)
and keywords = pair list

(* note that Elixir supports also pairs using the (:atom => expr) syntax *)
and pair = keyword * expr
and expr_or_kwds = E of expr | Kwds of keywords

(* ------------------------------------------------------------------------- *)
(* Expressions *)
(* ------------------------------------------------------------------------- *)
and expr =
  (* lowercase idents *)
  | I of ident
  (* uppercase idents *)
  | Alias of alias
  | L of G.literal
  | A of atom
  | String of quoted
  | Charlist of quoted
  | Sigil of Tok.t (* '~' *) * sigil_kind * string wrap option
  | List of items bracket
  | Tuple of items bracket
  | Bits of items bracket
  | Map of Tok.t (* "%" *) * astruct option * items bracket
  | Block of block
  | DotAlias of expr * Tok.t * alias
  | DotTuple of expr * Tok.t * items bracket
  (* only inside Call *)
  | DotAnon of expr * Tok.t
  (* only inside Call *)
  | DotRemote of remote_dot
  | ModuleVarAccess of Tok.t (* @ *) * expr
  | ArrayAccess of expr * expr bracket
  (* a Call can be a thousand things, including function and module definitions
   * when parsed in phase 1. A Call is transformed in more precise
   * AST constructs in phase 2 (see Elixir_to_elixir.ml).
   *)
  | Call of call
  | UnaryOp of operator wrap * expr
  | BinaryOp of expr * operator wrap * expr
  (* coming from Erlang (coming itself from Prolog) *)
  | OpArity of
      operator wrap
      * Tok.t
        (* '/' *)
        (* must rename this so the visitor does not conflict with Tok.t *)
      * (Parsed_int.t[@name "parsed_int"])
  | When of expr * Tok.t (* 'when' *) * expr_or_kwds
  | Join of expr * Tok.t (* '|' *) * expr_or_kwds
  | Lambda of Tok.t (* 'fn' *) * clauses * Tok.t (* 'end' *)
  | Capture of Tok.t (* '&' *) * expr
  | ShortLambda of Tok.t (* '&' *) * expr bracket
  | PlaceHolder of
      (* must rename this so the visitor does not conflict with Tok.t *)
      Tok.t
      (* & *)
      * (Parsed_int.t[@name "parsed_int"])
  | S of stmt
  (* semgrep-ext: *)
  | DeepEllipsis of expr bracket

(* restricted to Alias/A/I/DotAlias/DotTuple and all unary op *)
and astruct = expr

and sigil_kind =
  | Lower of char wrap * quoted
  | Upper of char wrap * string wrap bracket

(* the parenthesis can be fake *)
and call = expr * arguments bracket * do_block option
and remote_dot = expr * Tok.t (* '.' *) * ident_or_operator__or_quoted
and ident_or_operator__or_quoted = X2 of ident_or_operator | Quoted2 of quoted

(* ------------------------------------------------------------------------- *)
(* Blocks *)
(* ------------------------------------------------------------------------- *)

(* the bracket here are () *)
and block = body_or_clauses bracket

(* in after/rescue/catch/else and do blocks *)
and body_or_clauses =
  | Body of body
  (* can be empty *)
  | Clauses of clauses

(* really just exprs separated by terminators (newlines or semicolons) *)
and body = stmts

(* The bracket here are do/end.
 * Elixir semantic is to unsugar in a list of pairs with "do:", "after:",
 * as the keys.
 *)
and do_block =
  (body_or_clauses * (exn_clause_kind wrap * body_or_clauses) list) bracket

and exn_clause_kind = After | Rescue | Catch | Else

(* ------------------------------------------------------------------------- *)
(* Clauses *)
(* ------------------------------------------------------------------------- *)
and clauses = stab_clause list

(* Ideally it should be pattern list * tok * body option, but Elixir
 * is more general and use '->' also for type declarations in typespecs,
 * or for parameters (kind of patterns though).
 *)
and stab_clause =
  (arguments * (Tok.t (*'when'*) * expr) option) * Tok.t (* '->' *) * body

(*****************************************************************************)
(* Kernel constructs *)
(*****************************************************************************)
(* ref: https://hexdocs.pm/elixir/Kernel.html *)

(* ------------------------------------------------------------------------- *)
(* Stmts *)
(* ------------------------------------------------------------------------- *)
and stmts = expr list

and stmt =
  | If of
      Tok.t
      * expr
      * Tok.t (* 'do' *)
      * stmts
      * (Tok.t * stmts) option
      * Tok.t (* 'end' *)
  | D of definition

(* ------------------------------------------------------------------------- *)
(* Definitions *)
(* ------------------------------------------------------------------------- *)
and definition =
  | FuncDef of function_definition
  | ModuleDef of module_definition

and function_definition = {
  f_def : Tok.t;
  (* alt: could introduce an external 'entity' like in AST_generic.ml
   * but FuncDef and ModuleDef have different kind of constraints
   * on the name so better to be precise when we can.
   *)
  f_name : ident;
  f_params : parameters;
  (* bracket is do/end *)
  f_body : stmts bracket;
}

and parameters = parameter list bracket

and parameter =
  | P of parameter_classic
  | OtherParamExpr of expr
  | OtherParamPair of pair

and parameter_classic = {
  pname : ident;
  pdefault : (Tok.t (* \\ *) * expr) option;
}

and module_definition = {
  m_defmodule : Tok.t;
  m_name : alias;
  (* less: we could restrict it maybet to definition list *)
  m_body : stmts bracket;
}

(*****************************************************************************)
(* Program *)
(*****************************************************************************)
and program = body
[@@deriving
  show { with_path = false },
    (* Autogenerated visitors:
     * http://gallium.inria.fr/~fpottier/visitors/manual.pdf
     * To view the generated source, build, navigate to
     * `_build/default/languages/elixir/ast/`, and then run:
     *     ocamlc -stop-after parsing -dsource AST_elixir.pp.ml
     *)
    visitors { variety = "map"; ancestors = [ "map_parent" ] }]

(*****************************************************************************)
(* Any *)
(*****************************************************************************)

type any = Pr of program [@@deriving show { with_path = false }]

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let string_of_exn_kind = function
  | After -> "after"
  | Rescue -> "rescue"
  | Catch -> "catch"
  | Else -> "else"
