theory Lists
  imports Main
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

end