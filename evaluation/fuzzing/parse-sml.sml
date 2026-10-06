(* parse-sml.sml — parse-only driver for the Imperative-HOL/MLton backend of
   Pasteque.

   It replaces pasteque.sml of IsaFoL/PAC_Checker2/code: the three parse_*_file
   functions are the ones of that driver (parser.sml plus the conversion into
   the checker's types and, for the input polynomials, the insertion into the
   checker's table), and the checker is never called.

   Each file is timed on its own (wall clock, garbage collection included). The
   report on stdout has one `key value` pair per line, in seconds; parse-llvm.c
   prints the same keys.

     polys_s, proof_s, spec_s   parsing of the respective file
     total_s                    their sum
     gc_s                       CPU time of the garbage collector within total_s

   After the timers stopped, the driver traverses everything it parsed and
   prints the number of monomials and variable occurrences. This makes all
   parsed data observable, so that MLton cannot drop any of its construction as
   useless, and it serves as a sanity check of the instance. *)

fun parse_polys_file file_name = let
  val istream = TextIO.openIn file_name
  val a = map (fn x =>
                  let val (lbl, poly) = x
                  in
                    (PAC_Checker.nat_of_integer lbl,
                         map (fn (a,b) => (a, PAC_Checker.Int_of_integer b)) poly)
                  end)
              (PAC_Parser.input_polys istream)
  val _ = TextIO.closeIn istream
in
  foldl (fn ((lbl, a), b) => PAC_Checker.pAC_update_impl lbl a b ()) (PAC_Checker.pAC_empty_impl ()) a
end

fun parse_pac_file file_name = let
  val istream = TextIO.openIn file_name
  val a = PAC_Parser.step_polys istream
  val _ = TextIO.closeIn istream
in
  a
end

fun parse_spec_file file_name = let
  val istream = TextIO.openIn file_name
  val poly = PAC_Parser.parse_polynom istream
  val _ = TextIO.closeIn istream
in
  map(fn (a,b) => (a, PAC_Checker.Int_of_integer b)) poly
end

(* (monomials, variable occurrences, sum of coefficient signs) *)
fun count_poly (p : (string list * PAC_Checker.int) list, acc) =
  foldl (fn ((vs, PAC_Checker.Int_of_integer c), (m, v, s)) =>
            (m + 1, foldl (fn (x, n) => n + Int.min (1, String.size x)) v vs,
             s + IntInf.sign c))
        acc p

fun count_step (PAC_Checker.CL (srcs, _, r), acc) =
      count_poly (r, foldl (fn ((q, _), acc) => count_poly (q, acc)) acc srcs)
  | count_step (PAC_Checker.Extension (_, _, r), acc) = count_poly (r, acc)
  | count_step (PAC_Checker.Del _, acc) = acc

fun secs t = Time.fmt 6 t

fun run [polys, pac, spec] =
    let
      val cpu = Timer.startCPUTimer ()
      val t0 = Time.now ()
      val problem = parse_polys_file polys
      val t1 = Time.now ()
      val pac : (((string list * PAC_Checker.int) list, string, Uint64.uint64) PAC_Checker.pac_step) list =
          parse_pac_file pac
      val t2 = Time.now ()
      val spec = parse_spec_file spec
      val t3 = Time.now ()
      val gc = Timer.checkGCTime cpu
      val _ = print ("polys_s " ^ secs (Time.- (t1, t0)) ^ "\n")
      val _ = print ("proof_s " ^ secs (Time.- (t2, t1)) ^ "\n")
      val _ = print ("spec_s " ^ secs (Time.- (t3, t2)) ^ "\n")
      val _ = print ("total_s " ^ secs (Time.- (t3, t0)) ^ "\n")
      val _ = print ("gc_s " ^ secs gc ^ "\n")
      val acc = Array.foldl (fn (NONE, acc) => acc | (SOME p, acc) => count_poly (p, acc))
                            (0, 0, 0) problem
      val acc = foldl count_step acc pac
      val (m, v, s) = count_poly (spec, acc)
      val _ = print ("steps " ^ Int.toString (length pac) ^ "\n")
      val _ = print ("monomials " ^ Int.toString m ^ "\n")
      val _ = print ("var_occurrences " ^ Int.toString v ^ "\n")
      val _ = print ("sign_sum " ^ Int.toString s ^ "\n")
    in
      ()
    end
  | run _ =
    (TextIO.output (TextIO.stdErr,
                    "usage: parse-sml <file.polys> <file.proof> <file.spec>\n");
     OS.Process.exit OS.Process.failure)

val _ = run (CommandLine.arguments ())
        handle PAC_Parser.Parser_Error err =>
               (TextIO.output (TextIO.stdErr, "parsing failed with error: " ^ err ^ "\n");
                OS.Process.exit OS.Process.failure)
