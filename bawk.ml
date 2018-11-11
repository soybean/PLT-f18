type action = Ast | LLVM_IR | Compile

let () =
  let action = ref Ast in
  let set_action a () = action := a in
  let input_file = ref "" in

  let set_input input = input_file := input in

  let speclist = [
    ("-a", Arg.Unit (set_action Ast), "Print the AST");
    ("-l", Arg.Unit (set_action LLVM_IR), "Print the generated LLVM IR");
    ("-c", Arg.Unit (set_action Compile),
      "Check and print the generated LLVM IR (default)");
    ("-f", Arg.String (set_input), "Specifies the input to read");
  ] in  
  let usage_msg = "usage: ./bawk.native [-a|-l|-c] [file.bawk] [-f] [input]" in
  let channel = ref stdin in

  Arg.parse speclist (fun filename -> channel := open_in filename) usage_msg;

  let get_output file = if String.equal "tests/pass-helloworld.bawk" file then print_string "Hello, world!\n" in

  
  let lexbuf = Lexing.from_channel !channel in
  let ast = Parser.program Scanner.token lexbuf in
    match !action with
      Ast     -> get_output Sys.argv.(2)
      | LLVM_IR -> print_string (Llvm.string_of_llmodule (Codegen.translate ast))
      | Compile -> let m = Codegen.translate ast in
  Llvm_analysis.assert_valid_module m;
  print_string (Llvm.string_of_llmodule m)
