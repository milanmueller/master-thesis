This file contains instructions that hold for the LaTeX-based thesis (i.e. *.tex files).
Instructions in this file do NOT apply to the Isabelle project in `./isabelle`.
Instructions do not apply to markdown files, treat them as you usually would (e.g.
large autonomous edits in markdown files are fine.)

It serves simultaneously as a writing guideline for the author, as well as instructions
for AI-agent on what to do and what not to do.

# Expression and Wording

- Use "I" instead of "We":
  - "we implemented hash maps using..." -> "I implemented hash maps using ..."

- Use active voice rather than passive voice:
  - "hash maps were implemented" -> "I implemented hash maps"

- Do not use informal language:
  - "I think that this implementation was not good because [...]" -> "I did not use [...] to implement because [...]"
  - "I figured out that this was the wrong way to do it" -> "In a previous attempt, I had used [...], which resulted in [...]"

- Use past tense for work performed, use present tense for general facts:
  - "I implement hash maps using ..." -> "I implemented hash maps using ..."
  - "section 3 will introduce ..." -> "section 3 introduces ..."

- Avoid contractions:
  - "I didn't use ..." -> "I did not use ..."

- Avoid vague language:
  - "Y is rather slow" -> "Compared to X, Y is 3.4x slower"
  - "X is very efficient" -> "X has O(...) time complexity which is known to be optimal for ..."

- Prefer concise phrasing over wordy constructions:
  - "in order to" -> "to"
  - "due to the fact that" -> "because"
  - "at this point in time" -> "now"

- Do not anthropomorphize tools, algorithms, or the compiler:
  - "The compiler decides to inline the function" -> "The compiler inlines the function when [condition]."

- Define each technical term/acronym on first use, then use the same term consistently:
  - alternating between "hash map", "hash table", and "dictionary" for the same structure (bad), pick one term and use it throughout.

## Approved Uses
- Do provide feedback on semantic clarity of sentences in the thesis.
- Do generate/adjust tooling when asked, such as
  - Generation of build scripts
  - Adjustments to `./flake.nix`
- When reviewing text, inform the author when the text does not adhere to the stylistic
  writing guidelines defined in this file.

## Disapproved Uses
- Do not propose alternative formulations for multiple sentences, unless explicitly asked:
  e.g. do not propose: "section A could be rewritten into [...] to improve clarity"
  Instead, provide constructive feedback such as "in section A, the sentence [...] is ambiguous
  because [...]"
