theory BigIntString_Simplified
  imports BigInt_LLVM.LLVM_CodeGen_Signed
begin

definition 
divmod2by1 :: \<open>64 word \<Rightarrow> 64 word \<Rightarrow> 64 word \<Rightarrow> (64 word \<times> 64 word)\<close> where
  \<open>divmod2by1 hi lo d \<equiv> let cur = unat hi * (2^64) + unat lo in 
    (of_nat (cur div unat d), of_nat (cur mod unat d))\<close>

definition 
bi_div_by_w64 :: \<open>big_int \<Rightarrow> 64 word \<Rightarrow> (big_int \<times> 64 word) nres\<close> where
  \<open>bi_div_by_w64 bi l \<equiv> doN {
    ASSERT (0 < unat l); \<comment> \<open>Divisor must be non-zero\<close>
    (q, r, _) \<leftarrow> WHILET
      (\<lambda>(_, _, i). 0 < i)
      (\<lambda>(q, r, i). doN {
        \<comment> \<open>Compute d  := (r * 2^64 + bi!(i-1)) div l\<close>
        \<comment> \<open>    and r' := (r * 2^64 + bi!(i-1)) mod l\<close>
        let (d, r') = divmod2by1 r (bi ! (i - 1)) l;
        \<comment> \<open>Update quotient\<close>
        let q = q[i - 1 := d];
        RETURN (q, r', i - 1)
      })
      (replicate (length bi) 0, 0, length bi);
    q \<leftarrow> big_int_trim q; \<comment> \<open>Removes trailing zeros\<close>
    RETURN (q, r)
  }\<close>

end