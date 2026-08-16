theory Lists
  imports Main Isabelle_LLVM.LLVM_DS_Open_List
begin

fun 
  merge :: \<open>nat list \<Rightarrow> nat list \<Rightarrow> nat list\<close> where
  \<open>merge [] q = []\<close>
| \<open>merge p [] = p\<close>
| \<open>merge (p#ps) (q#qs) = (
    if p \<le> q then 
      p # merge ps (q#qs)
    else
      q # merge (p#ps) qs
  )\<close>

lemma sorted:
  assumes \<open>sorted p\<close> and \<open>sorted q\<close>
  shows \<open>sorted (merge p q)\<close>
  using assms apply (induction p q rule: merge.induct)
  subgoal by simp
  subgoal by auto
  subgoal by (smt (verit, ccfv_SIG) list.inject merge.elims nat_le_linear sorted2)
  done

datatype 'a node = Node ("val": \<open>'a\<close>) ("next": \<open>'a node ptr\<close>)

definition \<open>
list_aux A = (\<lambda>(xs::'a list) (xsi::'b list). 
  (length xs = length xsi) ** (\<forall>i\<in>{0..<length xs}. A xs!i xsi!i))
\<close>
(*
fun \<open>
lseg :: \<open>'b list \<Rightarrow> 'b node ptr \<Rightarrow> 'b node ptr \<Rightarrow> bool\<close> where
  \<open>lseg [] p s = (p=s)\<close>
| \<open>lseg (x#xs) p s = (if p=null then False
                      else (\<exists> q. pto (Node x q) p ** lseg xs q s)))\<close>
end
*)
definition \<open>
  ls_assn A = (\<lambda>(xs::'a list) (p::'b node ptr).
    \<exists>xsi. lseg xsi p null ** list_aux A xs xsi)
\<close>
  
fun 
  sum :: \<open>nat list \<Rightarrow> nat\<close> where
  \<open>sum [] = 0\<close> |
  \<open>sum (x#xs) = x + sum xs\<close>