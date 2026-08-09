theory LLVM_Basics
  imports Isabelle_LLVM.IICF
begin

definition \<open>add \<equiv> \<lambda>ai bi. ll_add ai bi\<close>

abbreviation \<open>si_assn \<equiv> snat_assn' TYPE(8)\<close>

lemma add_correct_fail:
  \<open>llvm_htriple
(si_assn a ai ** si_assn b bi)
(add ai bi)
(\<lambda>r. si_assn (a+b) r)\<close>
  unfolding add_def
  supply [simp] = snats_def max_snat_def
  apply (simp only: pure_app_eq in_snat_rel_conv_assn)
  apply vcg
  oops

lemma add_correct:
  \<open>llvm_htriple
(\<up>(a+b < 127) ** si_assn a ai ** si_assn b bi)
(add ai bi)
(\<lambda>r. si_assn (a+b) r)\<close>
  unfolding add_def
  supply [simp] = snats_def max_snat_def
  apply (simp only: pure_app_eq in_snat_rel_conv_assn)
  apply vcg
  done

lemma add_correct':
  \<open>llvm_htriple
(\<up>(a+b < 127) ** si_assn a ai ** si_assn b bi)
(add ai bi)
(\<lambda>r. si_assn (a+b) r ** si_assn a ai ** si_assn b bi)\<close>
  unfolding add_def
  supply [simp] = snats_def max_snat_def
  apply (simp only: pure_app_eq in_snat_rel_conv_assn)
  apply vcg
  done

definition \<open>
  ls_assn :: ('a \<Rightarrow> 'b \<Rightarrow> bool) \<Rightarrow> 'a list \<Rightarrow> 'b llvm_list \<Rightarrow> bool
\<close>

lemma split_list:
  \<open>llvm_htriple
((ls_assn A) xs xsi ** \<up>(xs\<noteq>[]))
(\<lambda>xs. (hd xs, tl xs))
(\<lambda>(rh, rt). A (hd xs) rh ** (ls_assn A) (tl xs) rt ** (ls_assn A) xs xsi)
\<close>

lemma split_list:
  \<open>llvm_htriple
((ls_assn A) xs xsi ** \<up>(xs\<noteq>[]))
(\<lambda>xs. (hd xs, tl xs))
(\<lambda>(rh, rt). A (hd xs) rh ** (ls_assn A) (tl xs) rt)
\<close>

end
