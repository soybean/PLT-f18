(* Authors: Ashley, Christine, Melanie, Victoria *)
(* Loosely based on MicroC *)

open Ast
open Sast

module StringMap = Map.Make(String)

(* Semantic checking of the AST. Returns an SAST if successful,
   throws an exception if something is wrong.

   Check each global variable, then check each function *)

let check (begin_list, loop_list, end_list, config_list) =

  (* Verify a list of bindings has no void types or duplicate names *)
  let check_binds (kind : string) (binds : bind list) =
    List.iter (function
	(Void, b) -> raise (Failure ("illegal void " ^ kind ^ " " ^ b))
      | _ -> ()) binds;
    let rec dups = function
        [] -> ()
      |	((_,n1) :: (_,n2) :: _) when n1 = n2 ->
	  raise (Failure ("duplicate " ^ kind ^ " " ^ n1))
      | _ :: t -> dups t
    in dups (List.sort (fun (_,a) (_,b) -> compare a b) binds)
  in

  (**** Check global variables ****)

  let (globals, _) = begin_list in check_binds "global" globals;


  (**** Check functions ****)
  (* Collect function declarations for built-in functions: no bodies *)
  let built_in_decls = 
  let add_bind map (ftyp, name, flist) = StringMap.add name {
      ret_type = ftyp;
      fname = name; 
      formals = flist;
      locals = []; body = [] } map
    in List.fold_left add_bind StringMap.empty [ (Int, "string_to_int", [(String, "a")]);
			                         (String, "int_to_string", [(Int, "a")]);
						 (String, "bool_to_string", [(Bool, "a")]);
						 (String, "rgx_to_string", [(Rgx, "a")]);
                                                 (Void, "length", []); 
						 (Void, "print", [(String, "a")]);
            					 (Void, "nprint", [(String, "a")]);
                                                 (Void, "contains", []);
                                                 (Int, "index_of", []);
                                                 (Void, "insert", []);
                                                 (Void, "delete", []);
                                                 (Void, "LOOP", []);
                                                 (Void, "END", []);
                                                 (Void, "loop", []);
                                                 (Void, "end", [])]
  in 
	
  
   (* Add function name to symbol table *)
  let add_func map fd = 
    let built_in_err = "function " ^ fd.fname ^ " may not be defined"
    and dup_err = "duplicate function " ^ fd.fname
    and make_err er = raise (Failure er)
    and n = fd.fname (* Name of the function *)
    in match fd with (* No duplicate functions or redefinitions of built-ins *)
         _ when StringMap.mem n built_in_decls -> make_err built_in_err
       | _ when StringMap.mem n map -> make_err dup_err  
       | _ ->  StringMap.add n fd map 
  in
   (* Collect all function names into one symbol table *)
  let (_, functions) = begin_list in let function_decls = List.fold_left add_func built_in_decls functions

  in
  
  (* Return a function from our symbol table *)
  let find_func s = 
    try StringMap.find s function_decls
    with Not_found -> raise (Failure ("unrecognized function " ^ s))
  in
  
  let (loop_locals,loop_stmts) = loop_list in check_binds "local" loop_locals;
  
  let (end_locals,end_stmts) = end_list in check_binds "local" end_locals;

  let check_function func =
    (* Make sure no formals or locals are void or duplicates *)
    check_binds "formal" func.formals;
    check_binds "local" func.locals;

    (* Raise an exception if the given rvalue type cannot be assigned to
       the given lvalue type *)
    let check_assign lvaluet rvaluet err =
       if (lvaluet = rvaluet) then lvaluet else raise (Failure err)
    in   

    (* Build local symbol table of variables for this function *)
    let symbols = List.fold_left (fun m (ty, name) -> StringMap.add name ty m) (* this might need to be changed later*)
	                StringMap.empty (globals @ func.formals @ func.locals )
    in

    (* Return a variable from our local symbol table *)
    let type_of_identifier s =
      try StringMap.find s symbols
      with Not_found -> raise (Failure ("undeclared identifier " ^ s))
    in
    (* Return a semantically-checked expression, i.e., with a type *)
    let rec expr = function
        Literal l -> (Int, SLiteral l)
      | StringLiteral l -> (String, SStringLiteral l)
      | BoolLit l  -> (Bool, SBoolLit l)
      | RgxLiteral l -> (Rgx, SRgxLiteral l)
      | Noexpr     -> (Void, SNoexpr)
      | Id s       -> (type_of_identifier s, SId s)
      | Access(a) as acc ->
         let (a, a') = expr a in
         if a <> Int then 
                 raise (Failure ("incorrect access in " ^ string_of_expr acc))
         else (String, SAccess(a, a'))
      | ArrayLit(l) -> 
         if List.length l > 0 then 
                 let typ = expr(List.nth l 0) in
                 let (arraytype, _) = typ in
                 let check_array e =
                         let (et, e') = expr e in (et, e')
                         in let l' = List.map check_array l in
                         let types e = 
                                 let (a, _)  = expr e in 
                                 if a <> arraytype then 
                                         raise(Failure("array of different types, expected " ^ 
                                         string_of_typ arraytype ^ " found " ^ string_of_typ a))
                                 in let _ = List.map types l in (ArrayType(arraytype), SArrayLit(l'))
         else (Void, SArrayLit([])) 
      | ArrayDeref (e1, e2) as e ->
         let (arr, e1') = expr e1 and (num, e2') = expr e2 in
         if num <> Int then raise(Failure("Int expression expected in " ^ string_of_expr e))
         else let find_typ arr =
                 match arr with
                 ArrayType(t) -> t 
               | Bool | String | Rgx | Void | Int -> 
                               raise(Failure("array deref should be called on array, not " ^ string_of_typ arr))
         in (find_typ arr, SArrayDeref((arr, e1'), (num, e2')))
      | NumFields -> (Int, SNumFields)
      | Assign(NumFields, _) -> raise (Failure ("illegal assignment of NF"))
      | Assign(e1, e2) as ex ->
         let check_expr typ e =
                 let (t, et') = 
                         match e with
                         ArrayLit(l) ->
                                 if List.length l > 0 then expr e
                                 else (typ, SArrayLit([]))
                       | _ -> expr e
         in (t, et') in
         let (lt, e1') = expr e1 
         in let (rt, e2') = check_expr lt e2 in
         let err = "illegal assignment " ^ string_of_typ lt ^ " = " ^ string_of_typ rt ^ " in " ^ string_of_expr ex
         in (check_assign lt rt err, SAssign((lt, e1'), (rt, e2')))
      | Unop(op, e) as ex -> 
         let (t, e') = expr e in
         let ty =
                 match op with
                 Neg when t = Int -> Int
               | Not when t = Bool -> Bool
               | _ -> raise (Failure ("illegal unary operator " ^ string_of_uop op ^ string_of_typ t ^ " in " ^ string_of_expr ex)) 
         in (ty, SUnop(op, (t, e')))
      | Binop(e1, op, e2) as e -> 
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         let same = t1 = t2 in
         (* Determine expression type based on operator and operand types *)
         let ty = 
                 match op with
                 Add | Sub | Mult | Div when same && t1 = Int   -> Int
               | Equal | Neq            when same               -> Bool
               | Less | Leq | Greater | Geq when same && (t1 = Int || t1 = String) -> Bool
               | And | Or when same && t1 = Bool -> Bool
               | _ -> raise(Failure ("illegal binary operator "  ^ string_of_typ t1 ^ " " ^ string_of_op op ^ " " ^
                            string_of_typ t2 ^ " in " ^ string_of_expr e))
         in (ty, SBinop((t1, e1'), op, (t2, e2')))
      | Increment(a) as e ->
         let (et, e') =  expr a in
         if (et <> Int) then raise (Failure("Int expected for " ^ string_of_expr e))
         else (Int, SIncrement(et, e'))
      | Decrement(a) as e ->
         let (et, e') = expr a in
         if (et <> Int) then raise (Failure("Int expected for " ^ string_of_expr e))
         else (Int, SDecrement(et, e'))
      | Strcat(e1, e2) as e ->
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if (t1 <> String || t2 <> String) then raise(Failure("Strings expected for " ^ string_of_expr e))
         else (String, SStrcat((t1, e1'), (t2, e2')))
      | Pluseq(e1, e2) as e -> 
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if (t1 <> Int || t2 <> Int) then raise (Failure("Ints are expected for " ^ string_of_expr e))
         else (Int, SPluseq((t1, e1'), (t2, e2')))
      | Minuseq(e1, e2) as e ->
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if (t1 <> Int || t2 <> Int) then raise (Failure("Ints are expected for " ^ string_of_expr e))
         else (Int, SMinuseq((t1, e1'), (t2, e2')))
      | Rgxeq(e1, e2) as e ->
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if (t1 <> Rgx || t2 != Rgx) then raise(Failure("Rgx expected for " ^ string_of_expr e))
         else (Bool, SRgxeq((t1, e1'), (t2, e2')))
      | Rgxneq(e1, e2) as e ->
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if (t1 <> Rgx || t2 <> Rgx) then raise(Failure("Rgx expected for " ^ string_of_expr e))
         else (Bool, SRgxneq((t1, e1'), (t2, e2')))
      | Rgxcomp(e1, e2) as e ->
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if ((t1 = Rgx && t2 = String) || (t1 = String && t2 = Rgx)) then
                 (Bool, SRgxcomp((t1, e1'), (t2, e2')))
         else raise(Failure("Different types expected for " ^ string_of_expr e))
      | Rgxnot(e1, e2) as e ->
         let (t1, e1') = expr e1 and (t2, e2') = expr e2 in
         if ((t1 = Rgx && t2 = String) || (t1 = String && t2 = Rgx)) then
                 (Bool, SRgxnot((t1, e1'), (t2, e2')))
	 else raise(Failure("Different types expected for " ^ string_of_expr e))
      | Call("length", args) as length -> 
          if List.length args != 1 then raise (Failure("expecting one argument for " ^ string_of_expr length))
          else let (et, e') = expr (List.nth args 0) in
          if (et = String || et = Bool || et = Void || et = Rgx || et = Int) then 
                  raise (Failure("illegal argument found " ^ 
                  string_of_typ et ^ " arraytype expected in " ^ string_of_expr length))
          else (Int, SCall("length", [(et, e')]))
     | Call ("insert", args) as insert ->
          if List.length args !=3 then raise (Failure("expecting three arguments for " ^ string_of_expr insert))
          else let (t1, e1') = expr (List.nth args 0) and (t2, e2') = expr(List.nth args 1) and (t3, e3') = expr(List.nth args 2) in
          if t2 <> Int then raise (Failure("expecting index argument for insert but had " ^ string_of_typ t2)) 
          else
                  (match t1 with
                  String | Bool | Void | Rgx | Int -> raise (Failure("illegal argument found "  ^ string_of_typ t1 ^ " expected arraytype"))
                | ArrayType(t) ->
                                if (string_of_typ t = string_of_typ(t3) && t3 != Void) 
                                then (Void, SCall("insert", [(t1, e1');(t2, e2');(t3, e3')]))
                                else raise(Failure("cannot perform insert on " ^ 
                                           string_of_typ t1 ^ " and " ^ string_of_typ t3))) 
     | Call("delete", args) as delete -> 
          if List.length args != 2 then raise (Failure("expecting two arguments for " ^ string_of_expr delete))
          else let (t1, e1') = expr (List.nth args 0) and (t2, e2') = expr (List.nth args 1) in
          if t2 <> Int then raise (Failure("expecting index argument for delete but had " ^ string_of_typ t2))
          else (t1, SCall("delete", [(t1, e1');(t2, e2')]))
     | Call("contains", args) as contains -> 
          if List.length args != 2 then raise (Failure("expecting two arguments for " ^ string_of_expr contains))
	  else let (t1, e1') = expr (List.nth args 0) and (t2, e2') = expr (List.nth args 1) in
          (match t1 with 
          String | Bool | Void | Rgx | Int ->
                  raise (Failure("illegal argument found " ^ string_of_typ t1 ^ " arraytype expected"))
         | ArrayType(t) ->
                  if (string_of_typ(t) = string_of_typ(t2) && t2 != Void) 
                  then (Bool, SCall("contains", [(t1, e1');(t2, e2')]))
                  else raise(Failure("cannot perform contains on " ^ string_of_typ(t1) ^ " and " ^ string_of_typ(t2)))) 
     | Call("index_of", args) as index_of -> 
          if List.length args != 2 then raise (Failure("expecting two arguments for " ^ string_of_expr index_of))
	  else let (t1, e1') = expr (List.nth args 0) and (t2, e2') = expr (List.nth args 1) in
          (match t1 with 
          String | Bool | Void | Rgx | Int ->
               raise (Failure("illegal argument found " ^ string_of_typ t1 ^ " arraytype expected"))
          | ArrayType(t) ->
               if (string_of_typ(t) = string_of_typ(t2) && t2 != Void)
	       then (Int, SCall("index_of", [(t1, e1');(t2, e2')]))
	       else raise(Failure("cannot perform index_of on " ^ string_of_typ(t1) ^ " and " ^ string_of_typ(t2)))) 
      | Call(fname, args) as call -> 
          let fd = find_func fname in
          let param_length = List.length fd.formals in
          if List.length args != param_length then
                  raise (Failure ("expecting " ^ string_of_int param_length ^ 
                         " arguments in " ^ string_of_expr call))
          else let check_call (ft, _) e = 
                  let (et, e') = expr e in 
                  let err = "illegal argument found " ^ string_of_typ et ^
                  " expected " ^ string_of_typ ft ^ " in " ^ string_of_expr e 
                  in (check_assign ft et err, e')
                  in 
                  let args' = List.map2 check_call fd.formals args
                  in (fd.ret_type, SCall(fname, args'))
    in

    let check_bool_expr e = 
      let (t', e') = expr e
      and err = "expected Boolean expression in " ^ string_of_expr e 
      in if t' != Bool then raise (Failure err) else (t', e') 
    in

    (* Return a semantically-checked statement i.e. containing sexprs *)
    let rec check_stmt = function
        Expr e -> SExpr (expr e)
      | If(p, b1, b2) -> SIf(check_bool_expr p, check_stmt b1, check_stmt b2)
      | For(e1, e2, e3, st) ->
	  SFor(expr e1, check_bool_expr e2, expr e3, check_stmt st)
      | EnhancedFor(s1, s2, st) ->
          let s2_type = type_of_identifier s2 in
          (match s2_type with
          Bool | Rgx | String | Int | Void ->
                  raise (Failure("cannot iterate over type " ^ string_of_typ s2_type))
          | ArrayType(t) ->
                  if (string_of_typ t = string_of_typ (type_of_identifier s1)) then SEnhancedFor(s1, s2, check_stmt st) 
                  else raise(Failure("mismatch in " ^ string_of_typ (type_of_identifier s1) ^ " and " ^ string_of_typ s2_type)))
      | While(p, s) -> SWhile(check_bool_expr p, check_stmt s)
      | Return e -> let (t, e') = expr e in
        if t = func.ret_type then SReturn (t, e') 
        else raise (Failure ("return gives " ^ string_of_typ t ^ " expected " ^
                    string_of_typ func.ret_type ^ " in " ^ string_of_expr e))
	    
	    (* A block is correct if each statement is correct and nothing
	       follows any Return statement.  Nested blocks are flattened. *)
      | Block sl -> 
          let rec check_stmt_list = function
              [Return _ as s] -> [check_stmt s]
            | Return _ :: _   -> raise (Failure "nothing may follow a return")
            | Block sl :: ss  -> check_stmt_list (sl @ ss) (* Flatten blocks *)
            | s :: ss         -> check_stmt s :: check_stmt_list ss
            | []              -> []
          in SBlock(check_stmt_list sl)

    in (* body of check_function *)
    { sret_type = func.ret_type;
      sfname = func.fname;
      sformals = func.formals;
      slocals  = func.locals;
      sbody = match check_stmt (Block func.body) with
	SBlock(sl) -> sl
      | _ -> raise (Failure ("internal error: block didn't become a block?"))
    }
  in 
  let check_config config_list =  
    (*
    let expr = function
            StringLiteral l -> (String, SStringLiteral l)
      |_ -> raise(Failure("shouldn't have this expr in config"))
    in
    *)
    let obtain_config (default_rs, default_fs) config_list =
      let obtain_config_folder (rs, fs) = function
        | RSAssign e -> (match rs with
          | Some _ -> raise (Failure "RS set twice")
          | None -> (Some (string_of_expr e), fs)
          )
        | FSAssign e -> (match fs with
          | Some _ -> raise (Failure "fS set twice")
          | None -> (fs, Some (string_of_expr e))
          )
      in
      match List.fold_left
            obtain_config_folder (None, None) config_list
      with
      | (Some rs, Some fs) -> rs, fs
      | (Some rs, None) -> rs, default_fs
      | (None, Some fs) -> default_rs, fs
      | (None, None) -> default_rs, default_fs
    in
    obtain_config ("\n", " ") config_list
  in
	let gen_fn name fs binds stmts =
	check_function ({ 
		ret_type = Void;
		fname = name;
		formals = fs;
		locals = binds;
		body = stmts
	}) 
	in 
  ((globals, List.map check_function functions), 
  gen_fn "loop" [(String, "line")] loop_locals loop_stmts,
  gen_fn "end" [] end_locals end_stmts,
	check_config config_list)

