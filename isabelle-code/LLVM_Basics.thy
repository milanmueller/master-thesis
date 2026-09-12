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
((a+b < 127) ** si_assn a ai ** si_assn b bi)
(add ai bi)
(\<lambda>r. si_assn (a+b) r)\<close>
  unfolding add_def
  supply [simp] = snats_def max_snat_def
  apply (simp only: pure_app_eq in_snat_rel_conv_assn)
  apply vcg
  done

lemma add_correct':
  \<open>llvm_htriple
((a+b < 127) ** si_assn a ai ** si_assn b bi)
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
((ls_assn A) xs xsi ** (xs\<noteq>[]))
(\<lambda>xs. tl xs)
(\<lambda>r. A (tl xs) r ** (ls_assn A) xs xsi)
\<close>

lemma split_list:
  \<open>llvm_htriple
((ls_assn A) xs xsi)
(\<lambda>xs. tl xs)
(\<lambda>r. A (tl xs) r)
\<close>

definition 
  sum :: \<open>nat list \<Rightarrow> nat nres\<close> where
  \<open>sum xs = do {
    let acc = 0;
    let i = 0;
    (acc,i) \<leftarrow> WHILET
      (\<lambda>(acc,i). i < length xs)
      (\<lambda>(acc,i). do {
        let acc = acc + xs ! i;
        let i = i + 1;
        RETURN (acc, i)
      })
    (acc, i);
    RETURN acc
  }\<close>

definition 
  sum' :: \<open>nat list \<Rightarrow> nat nres\<close> where
  \<open>sum' xs = do {
    let acc = 0;
    let i = 0;
    (acc,i) \<leftarrow> WHILET
      (\<lambda>(acc,i). i < length xs)
      (\<lambda>(acc,i). do {
        ASSERT (i < length xs);
        ASSERT (acc + xs ! i < max_snat 64);
        let acc = acc + xs ! i;
        let i = i + 1;
        RETURN (acc, i)
      })
    (acc, i);
    RETURN acc
  }\<close>

sepref_def sum_impl' is \<open>sum'\<close>
  :: \<open>(larray_assn' TYPE(64) (snat_assn' TYPE(64)))\<^sup>k \<rightarrow>\<^sub>a snat_assn' TYPE(64)\<close>
  unfolding sum'_def
  apply (annot_snat_const "TYPE(64)")
  by sepref

definition sum_impl where \<open>
sum_impl \<equiv> \<lambda>xsi. doM {
  (acci, ii) \<leftarrow> llc_while \<comment> \<open>While loop for \<open>llM\<close> programs\<close>
    \<comment> \<open>Break Condition: Only continue with loop, if index < length\<close>
    (\<lambda>(acci, ii). doM {l \<leftarrow> la_length_impl xsi; ll_icmp_slt ii l})
    \<comment> \<open>Loop Body: Add to accumulator, increment index\<close>
    (\<lambda>(acci, ii). doM {
      xi \<leftarrow> la_get_impl xsi ii;
      acci \<leftarrow> ll_add acci xi;
      ii \<leftarrow> ll_add ii 1;
      Mreturn (acci, ii)
    })
    (0, 0);
  Mreturn acci
}\<close>

term sum_impl'
lemma \<open>sum_impl' = sum_impl\<close> unfolding sum_impl'_def sum_impl_def ..

lemma \<open>is_pure (snat_assn' TYPE(64))\<close> by auto

term take

text \<open>\<^const>\<open>take\<close> is implemented by the dynamic array \<^const>\<open>al_assn\<close>, not by
  \<^const>\<open>larray_assn\<close>: truncation only adjusts the length field.\<close>

sepref_def take_test is \<open>uncurry (RETURN oo take)\<close>
  :: \<open>[\<lambda>(i,xs). i \<le> length xs]\<^sub>a
      (snat_assn' TYPE(64))\<^sup>k *\<^sub>a (al_assn' TYPE(64) (snat_assn' TYPE(64)))\<^sup>d
      \<rightarrow> al_assn' TYPE(64) (snat_assn' TYPE(64))\<close>
  by sepref

text \<open>Without the precondition, use the guarded \<^const>\<open>mop_list_take\<close> instead.\<close>

sepref_def take_test' is \<open>uncurry mop_list_take\<close>
  :: \<open>(snat_assn' TYPE(64))\<^sup>k *\<^sub>a (al_assn' TYPE(64) (snat_assn' TYPE(64)))\<^sup>d
      \<rightarrow>\<^sub>a al_assn' TYPE(64) (snat_assn' TYPE(64))\<close>
  by sepref

end
