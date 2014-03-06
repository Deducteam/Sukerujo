open Types
open Printf

module H = Hashtbl.Make(
struct
  type t        = ident
  let equal     = ident_eq
  let hash      = Hashtbl.hash
end )

(* *** Environment management *** *)

type gst =
  | Decl  of term*(int*gdt*rule list) option
  | Def   of term*term 
  | Static of term

let envs : (gst H.t) H.t = H.create 19
let init name = H.add envs name (H.create 251)

(* *** Modules *** *)

let import lc m =
  assert ( not (H.mem envs m) );
  (* If the [.dko] file is not found, try to compile it first.
   This hack is terrible. It uses system calls and can loop with circular dependencies. *)
  begin
    if not ( Sys.file_exists ( string_of_ident m ^ ".dko" ) ) && !Global.autodep then
      ignore ( Sys.command ( "dkcheck -e " ^ string_of_ident m ^ ".dk" ) )
  end ;
  try
    (* If the [.dko] file is not found, try to compile it first.
     This hack is terrible. It uses system calls and can loop with circular dependencies. *)
    begin
      if not ( Sys.file_exists ( string_of_ident m ^ ".dko" ) ) && !Global.autodep then
        ignore ( Sys.command ( "dkcheck -e " ^ string_of_ident m ^ ".dk" ) )
          end ;
      let chan = open_in ( string_of_ident m ^ ".dko" ) in
      let ctx:gst H.t = Marshal.from_channel chan in
        close_in chan ;
        H.add envs m ctx ;
        ctx
  with _ ->
    Global.fail lc "Fail to open module '%a'." pp_ident m

let export_and_clear () =
  ( if !Global.export then
      begin
        let out = open_out (string_of_ident !Global.name ^ ".dko" ) in
        let env = H.find envs !Global.name in
          Marshal.to_channel out env [Marshal.Closures] ;
          close_out out
      end ) ;
  H.clear envs

(* *** Get *** *)

let get_global_symbol lc m v =
  let env =
    try H.find envs m
    with Not_found -> import lc m
  in
    try ( H.find env v )
    with Not_found ->
      Global.fail lc "Cannot find symbol '%a.%a'." pp_ident m pp_ident v

let get_global_type lc m v =
  match get_global_symbol lc m v with
    | Decl (ty,_)       -> ty
    | Def (_,ty)        -> ty
    | Static ty         -> ty

let get_global_rw lc m v =
  match get_global_symbol lc m v with
    | Decl (_,rw)       -> rw
    | _                 -> None

let is_neutral lc m v = 
  match get_global_symbol lc m v with
    | Static _          -> true
    | Decl(_,None)      -> not (ident_eq m !Global.name)
    | _                 -> false

(* *** Add *** *)

let add lc v gst =
  let env = H.find envs !Global.name in
    if H.mem env v then
      if !Global.ignore_redecl then
        Global.debug 1 lc "Redeclaration ignored." 
      else
        Global.fail lc "Already defined symbol '%a'." pp_ident v
    else
      H.add env v gst

let add_decl lc v ty    = add lc v (Decl (ty,None))
let add_static lc v ty  = add lc v (Static ty)
let add_def lc v te ty  = add lc v (Def (te,ty))

let add_rw lc v rs =
  let env = H.find envs !Global.name in
    try (
      match H.find env v with
        | Def (_,_)             ->
            Global.fail lc "Cannot add rewrite\
              rules for the symbol '%a' (Definition)." pp_ident v
        | Decl(ty,Some (i,g,lst))       ->
            let g2 =  Matching.add_rw (i,g) rs in
              H.add env v (Decl (ty,Some (i,g2,rs@lst)))
        | Decl (ty,None)        ->
            let (i,g) = Matching.get_rw v rs in
              H.add env v (Decl (ty,Some (i,g,rs)))
        | Static _              -> 
            Global.fail lc "Cannot add rewrite\
              rules for the symbol '%a' (Static)." pp_ident v
    ) with
        Not_found ->
          Global.fail lc "Cannot find symbol '%a.%a'." 
            pp_ident !Global.name pp_ident v

(* Iteration on rules *)

let foreach_rule_aux f _ : gst H.t -> unit  =
  H.iter (
    fun _ gst -> match gst with
      | Decl (_,Some(_,_,lst))  -> List.iter f lst
      | _                       -> ()
  )

let foreach_rule f = H.iter (foreach_rule_aux f) envs
let foreach_module_rule f = foreach_rule_aux f empty (H.find envs !Global.name)
