theory SortingSimplified
  imports Isabelle_LLVM.IICF
begin

context
  fixes dummy :: \<open>'a::linorder itself\<close>
begin

definition merge_list :: \<open>'a list \<Rightarrow> 'a list \<Rightarrow> 'a list nres\<close> where
\<open>merge_list xs0 ys0 \<equiv> doN {
  (r, xs, ys) \<leftarrow> WHILET
    (\<lambda>(r,xs,ys). xs\<noteq>[] \<and> ys\<noteq>[])
    (\<lambda>(r,xs,ys). doN {
      let (x,xs) = (hd xs, tl xs);
      let (y,ys) = (hd ys, tl ys);
      if x < y then
        RETURN (r @ [x], xs, y#ys)
      else
        RETURN (r @ [y], x#xs, ys)
    }) ([],xs0,ys0);
  RETURN (r @ xs @ ys)
}\<close>

end

end
