type debug_taint = {
  sources : (Range_with_metavars.t * Rule.taint_source) list;
      (** Ranges matched by `pattern-sources:` *)
  sanitizers : Range_with_metavars.ranges;
      (** Ranges matched by `pattern-sanitizers:` *)
  sinks : (Range_with_metavars.t * Rule.taint_sink) list;
      (** Ranges matched by `pattern-sinks:` *)
}
(** To facilitate debugging of taint rules. *)

(* The type of the specialized formual cache used for inter-rule
   match sharing.
*)
type formula_cache

(* These formula caches are only safe to use to share results between
   runs of rules on the same target! It is consumed by [taint_instance_for_rule_and_target].
*)
val mk_specialized_formula_cache : Rule.taint_rule list -> formula_cache

val hook_setup_hook_function_taint_signature :
  (Match_env.xconfig ->
  Rule.taint_rule ->
  Taint_instance.t ->
  Xtarget.t ->
  unit)
  option
  ref
(** This is used for intra-file inter-procedural taint-tracking, and the idea is
  * that this hook will do top-sorting and infer the signature of each function
  * in the file, and while doing this it will also setup
  * 'Dataflow_tainting.hook_function_taint_signature'.
  *
  * Doing it here (vs what DeepSemgrep does) has the advantage that we can re-use
  * the same 'Taint_instance.t' without having to do any caching on disk.
  *
  * FIXME: Once we have the taint signature of a function we do not need to run
  *   taint tracking on it anymore... but we still do it hence duplicating work.
  *   We only need to analyze anonymous functions which do not get taint sigantures
  *   (or we could infer a signature for them too...).
  *)

(* It could be a private function, but it is also used by Deep Semgrep. *)
(* This [formula_cache] argument is exposed here because this function is also
   a subroutine but the cache itself should be created outside of the any main
   loop which runs over rules. This cache is only safe to share with if
   [taint_instance_for_rule_and_target] is used on the same file!
*)
val taint_instance_for_rule_and_target :
  per_file_formula_cache:formula_cache ->
  Match_env.xconfig ->
  Language.t ->
  string (* filename *) ->
  AST_generic.program * Tok.location list ->
  Rule.taint_rule ->
  Taint_instance.handle_findings ->
  Taint_instance.t * debug_taint * Matching_explanation.t list

val mk_fun_input_env :
  Taint_instance.t ->
  ?glob_env:Taint_lval_env.t ->
  AST_generic.function_definition ->
  Taint_lval_env.t
(** Constructs the initial taint environment for a given function definition.
 * Essentially, it records the parameters that are taint sources, or whose
 * default value is a taint source.
 * It is exposed to be used by inter-file taint analysis in Pro.  *)

val check_fundef :
  Taint_instance.t ->
  ?entity:AST_generic.entity (** entity being analyzed *) ->
  AST_to_IL.ctx ->
  ?glob_env:Taint_lval_env.t ->
  Dataflow_tainting.java_props_cache ->
  AST_generic.function_definition ->
  IL.cfg * Dataflow_tainting.mapping
(** Check a function definition using a [Taint_instance.t] (which can
  * be obtained with [taint_instance_for_rule_and_target]). Findings are passed on-the-fly
  * to the [handle_findings] callback in the taint instance.
  *
  * This is a low-level function exposed for debugging purposes (-dfg_tainting).
  *)

val check_rules :
  match_hook:(string -> Pattern_match.t -> unit) ->
  per_rule_boilerplate_fn:
    (Rule.rule ->
    (unit -> Core_profiling.rule_profiling Core_result.match_result) ->
    Core_profiling.rule_profiling Core_result.match_result) ->
  Rule.taint_rule list ->
  Match_env.xconfig ->
  Xtarget.t ->
  (* timeout function *)
  Core_profiling.rule_profiling Core_result.match_result list
(** Runs the engine on a group of taint rules, which should be for the
  * same language. Running on multiple rules at once enables inter-rule
  * optimizations.
  *)
