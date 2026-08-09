theory Poly_Basics
  imports Main HOL.List
begin

definition \<open>
variable \<equiv> string
term \<equiv> variable list
monomial \<equiv> term \<times> int
polynomial \<equiv> monomial list
\<close>

term \<open>nat list\<close>
term \<open>prod\<close>
term \<open>list\<close>
typ \<open>nat list\<close>
typ \<open>(nat, nat) prod\<close>

end