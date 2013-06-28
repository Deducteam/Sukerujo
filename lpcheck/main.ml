
open Types

(* Error Msgs *)

let error str = 
  Global.msg ("\027[31m" ^ str ^ "\027[m\n");
  exit 1 

(* Parsing *)

let parse lb = 
  try
      Parser.top Lexer.token lb
  with 
    | Parsing.Parse_error       -> 
        begin
          let curr = lb.Lexing.lex_curr_p in
          let line = curr.Lexing.pos_lnum in
          let cnum = curr.Lexing.pos_cnum - curr.Lexing.pos_bol in
          let tok = Lexing.lexeme lb in
            raise (ParserError (ParsingError (tok,(line,cnum))))
        end

(* Run *)

let run_on_stdin _ =
  Global.msg (" [ Reading from stdin ]\n") ;
  parse (Lexing.from_channel stdin) ;
  Global.msg (" [ Checking done ]\n") ;
  Env.export_and_clear ()
            
let run_on_file file =
  let input = open_in file in
    Global.msg (" [ Reading from '" ^ file ^ "' ]\n") ;
    parse (Lexing.from_channel input) ;
    Global.msg (" [ Checking done ]\n") ;
    Env.export_and_clear ()

(* Main *)

let args = [
        ("-q"    , Arg.Set Global.quiet                 , "Quiet"               ) ;
        ("-e"    , Arg.Set Global.export                , "Create a .dko" ) ;
        ("-stdin", Arg.Unit run_on_stdin                , "Use standart input"  ) 
]

let _ = 
  try 
    Arg.parse args run_on_file "Usage: dkcheck [options] files"  
  with 
    | Sys_error err             -> error ("System error: "^err)
    | ParserError err           -> error ( Debug.string_of_perr err ) 
    | End_of_file_in_comment    -> error ("Unexpected end of file.") 
    | TypingError err           -> error (Debug.string_of_terr err) 
