theory Lists
  imports Main Isabelle_LLVM.IICF Isabelle_LLVM.LLVM_DS_Open_List
    PAC_Checker_LLVM.IICF_Copying_List PAC_Checker_LLVM.PAC_Polynomials_Operations
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
  subgoal by (smt (verit, best) Lists.merge.elims list.inject nat_le_linear sorted2_simps(2)) 
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

term foldl
definition
ll_foldl :: \<open>('a \<Rightarrow> 'b \<Rightarrow> 'a llM) \<Rightarrow> 'a \<Rightarrow> 'b node ptr \<Rightarrow> 'a llM\<close> where
  \<open>ll_foldl f a p \<equiv> if p = null then Mreturn a else do {
      n \<leftarrow> ll_load p;
      a \<leftarrow> f a (node.val n);
      ll_foldl f (node.next n) a
  }\<close>

definition
sum' :: \<open>nat list \<Rightarrow> nat\<close> where
  \<open>sum' = foldl (+) 0\<close>

definition
sum_nres :: \<open>nat list \<Rightarrow> nat nres\<close> where
\<open>sum_nres xs \<equiv> doN {
  (r,_) \<leftarrow> REC\<^sub>T (\<lambda> f (r,xs). doN {
    if xs = [] then RETURN (r,xs)
    else doN {
      (x,xs) \<leftarrow> mop_list_pop_hd xs;
      (r,xs) \<leftarrow> f (r,xs);
      ASSERT(r+x < max_unat 64);
      RETURN (r+x,xs)
    }
  }) (0, xs);
  RETURN r
}\<close>

text \<open>The deep free of a copying list lives in the \<open>freeable_assn\<close> locale, which fixes
  an element assertion together with a deallocator for a single element.  Interpreting
  it for @{term \<open>unat_assn' TYPE(64)\<close>} -- elements are plain machine words, so freeing
  one is a no-op -- yields both the named constant \<open>unat64.cl_free\<close> and the rule
  \<open>MK_FREE (cl_assn' (unat_assn' TYPE(64))) unat64.cl_free\<close>, which the frame solver needs
  for the list the recursion returns.\<close>
lemma unat64_freeable: \<open>freeable_assn (unat_assn' TYPE(64)) (\<lambda>_. Mreturn ())\<close>
  by unfold_locales (metis free_thms(2))

interpretation unat64: freeable_assn \<open>unat_assn' TYPE(64)\<close> \<open>\<lambda>_. Mreturn ()\<close>
  by (rule unat64_freeable)

sepref_def sum_impl' is \<open>sum_nres\<close>
  :: \<open>(cl_assn' (unat_assn' TYPE(64)))\<^sup>d \<rightarrow>\<^sub>a unat_assn' TYPE(64)\<close>
  unfolding sum_nres_def
  apply (annot_unat_const \<open>TYPE(64)\<close>)
  by sepref

text \<open>The synthesized implementation, spelled out with readable names.  \<open>ri\<close> is the
  accumulated sum and \<open>xsi\<close> the list of remaining elements; both are the concrete
  counterparts of \<open>r\<close> and \<open>xs\<close> in @{term sum_nres}.\<close>
definition 
sum_impl :: \<open>64 word cl_list \<Rightarrow> 64 word llM\<close> where
  \<open>sum_impl \<equiv> \<lambda>xsi. doM {
    (ri, xsi) \<leftarrow> MMonad.REC (\<lambda>sumr (ri, xsi). doM {
        b \<leftarrow> os_is_empty xsi;
        llc_if b
          (Mreturn (ri, xsi)) \<comment> \<open>Base case\<close>
          (doM {              \<comment> \<open>Recursion step\<close>
            \<comment> \<open>Destructure the list\<close>
            (xi, xsi) \<leftarrow> os_pop xsi;
            \<comment> \<open>Recurse on list tail\<close>
            (ri, xsi) \<leftarrow> sumr (ri, xsi);
            \<comment> \<open>Combine\<close>
            ri \<leftarrow> ll_add ri xi;
            Mreturn (ri, xsi)
          })
      }) (0, xsi);
    \<comment> \<open>Free the (now empty) remaining xsi\<close>
    unat64.cl_free xsi;
    Mreturn ri
  }\<close>

text \<open>Both differ only inpop_hd how the result pair is destructed: \<open>sepref\<close> binds it as a
  whole and projects with @{term fst} and @{term snd}, while @{term sum_impl} uses a
  pattern binding.  Unfolding @{thm split_def} identifies the two.\<close>
lemma sum_impl_alt_def: \<open>sum_impl = sum_impl'\<close>
  unfolding sum_impl_def sum_impl'_def
  by (auto simp: split_def)


datatype direction = LEFT | RIGHT | BOTH | STOP
fun 
ifoldl :: 
  \<open>('a \<Rightarrow> 'b \<Rightarrow> 'c \<Rightarrow> direction \<Rightarrow> 'a) 
      \<Rightarrow> ('b \<Rightarrow> 'c \<Rightarrow> direction)
      \<Rightarrow> ('a \<Rightarrow> 'b \<Rightarrow> 'a) \<Rightarrow> ('a \<Rightarrow> 'c \<Rightarrow> 'a)
      \<Rightarrow> 'a \<Rightarrow> 'b list \<Rightarrow> 'c list \<Rightarrow> 'a\<close> where
  \<open>ifoldl _ _   _  _  acc [] []             = acc\<close>
| \<open>ifoldl _ _   f1 _  acc xs []             = foldl f1 acc xs\<close>
| \<open>ifoldl _ _   _  f2 acc [] ys             = foldl f2 acc ys\<close>
| \<open>ifoldl f dec f1 f2 acc (x # xs) (y # ys) = (
    case dec x y of
      STOP  \<Rightarrow> (f acc x y STOP)
    | LEFT  \<Rightarrow> ifoldl f dec f1 f2 (f acc x y LEFT)  xs (y # ys)
    | RIGHT \<Rightarrow> ifoldl f dec f1 f2 (f acc x y RIGHT) (x # xs) ys
    | BOTH  \<Rightarrow> ifoldl f dec f1 f2 (f acc x y BOTH)  xs ys
  )\<close>

term  add_poly_l'
type_synonym monomial = \<open>(string list \<times> int)\<close>
type_synonym llist_polynomial = \<open>monomial list\<close>
definition 
add_dec :: \<open>monomial \<Rightarrow> monomial \<Rightarrow> direction\<close> where
\<open>add_dec \<equiv> \<lambda>(xs, n) (ys, m).
  if xs = ys then BOTH
  else if (xs, ys) \<in> term_order_rel then LEFT
  else RIGHT\<close>

definition
add_update :: 
  \<open>llist_polynomial \<Rightarrow> monomial \<Rightarrow> monomial \<Rightarrow> direction \<Rightarrow> llist_polynomial\<close> 
where
\<open>add_update \<equiv> \<lambda>acc (xs, n) (ys, m) dir. 
  if dir = BOTH then
    if n + m = 0 then acc
    else acc @ [(xs, n + m)]
  else if dir = LEFT then
    acc @ [(xs, n)]
  else \<comment> \<open>Here, dir = RIGHT\<close>
    acc @ [(ys, m)]\<close>

definition
add_copy_remainder :: 
  \<open>llist_polynomial \<Rightarrow> monomial \<Rightarrow> llist_polynomial\<close> where
\<open>add_copy_remainder acc m = acc @ [COPY m]\<close>

lemma add_poly_l_alt: \<open>add_poly_l' (p,q) = 
  ifoldl
    add_update
    add_dec
    add_copy_remainder
    add_copy_remainder
    [] p q\<close>
proof -
  have nil_r[simp]: \<open>ifoldl f dec f1 f2 acc xs [] = foldl f1 acc xs\<close> for f dec f1 f2 acc xs
    by (cases xs) auto
  have nil_l[simp]: \<open>ifoldl f dec f1 f2 acc [] ys = foldl f2 acc ys\<close> for f dec f1 f2 acc ys
    by (cases ys) auto
  have copy[simp]: \<open>foldl add_copy_remainder acc xs = acc @ xs\<close> for acc xs
    by (induction xs arbitrary: acc) (auto simp: add_copy_remainder_def COPY_def)
  \<comment> \<open>@{term add_poly_l'} prepends its result, @{term ifoldl} appends to an
      accumulator, so the induction has to be generalised over that accumulator.\<close>
  have \<open>ifoldl add_update add_dec add_copy_remainder add_copy_remainder acc p q
      = acc @ add_poly_l' (p, q)\<close> for acc p q
    by (induction \<open>(p, q)\<close> arbitrary: p q acc rule: add_poly_l'.induct)
       (auto simp: add_update_def add_dec_def add_copy_remainder_def COPY_def Let_def)
  from this[of \<open>[]\<close> p q] show ?thesis by simp
qed


end
