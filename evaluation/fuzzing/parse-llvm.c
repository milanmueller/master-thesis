/* parse-llvm.c — parse-only driver for the Isabelle-LLVM backend of Pasteque.
 *
 * It replaces main.c of IsaFoL-Pasteque-LLVM/PAC_Checker_LLVM/code: it lexes and
 * parses the three files with the same trusted parser (parser.c), which builds
 * the checker's heap representation through the verified builders, and then
 * exits without calling the checker. Nothing is freed: there are no C-side
 * destructors for the built objects, and the process ends anyway.
 *
 * Each file is timed on its own (wall clock), lexing included, in the order the
 * SML driver reads them. The report on stdout has one `key value` pair per
 * line, in seconds; parse-sml.sml prints the same keys.
 *
 *   polys_s, proof_s, spec_s   lexing + parsing of the respective file
 *   total_s                    their sum
 *   lex_s                      the share of total_s spent lexing
 */

/* clock_gettime()/CLOCK_MONOTONIC are POSIX, not ISO C — request them. */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "parser.h"

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec + 1e-9 * (double)t.tv_nsec;
}

/* The parsed objects are stored here so that the builders' results stay
 * observable, i.e. no part of the construction is dead code under LTO. */
void *volatile sink;

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s <file.polys> <file.proof> <file.spec>\n",
            argv[0]);
    return 2;
  }

  char *buf = NULL;
  token_array ta = {0};
  double lex = 0;

  double t0 = now();
  if (lex_file(argv[1], &buf, &ta) != 0)
    return 2;
  double t = now();
  lex += t - t0;
  sink = parse_inputs(&ta);
  double t1 = now();

  if (lex_file(argv[2], &buf, &ta) != 0)
    return 2;
  t = now();
  lex += t - t1;
  sink = parse_proof(&ta);
  double t2 = now();

  if (lex_file(argv[3], &buf, &ta) != 0)
    return 2;
  t = now();
  lex += t - t2;
  sink = parse_target(&ta);
  double t3 = now();

  printf("polys_s %.6f\n", t1 - t0);
  printf("proof_s %.6f\n", t2 - t1);
  printf("spec_s %.6f\n", t3 - t2);
  printf("total_s %.6f\n", t3 - t0);
  printf("lex_s %.6f\n", lex);
  return 0;
}
