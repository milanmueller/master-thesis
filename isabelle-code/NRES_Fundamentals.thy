theory NRES_Fundamentals
  imports Main
begin

datatype 'a nres = FAIL | RES \<open>'a set\<close>

definition
RETURN :: \<open>'a \<Rightarrow> 'a nres\<close> 
where \<open>RETURN a = RES {a}\<close>

definition
sum :: \<open>nat \<Rightarrow> nat \<Rightarrow> nat nres\<close>
where \<open>sum a b = RETURN (a + b)\<close>

definition
SPEC :: \<open>('a \<Rightarrow> bool) \<Rightarrow> 'a nres\<close>
where \<open>SPEC \<Phi> = RES { a::'a. \<Phi> a }\<close>

definition
add_spec :: \<open>nat \<Rightarrow> nat \<Rightarrow> nat nres\<close>
where \<open>add_spec a b = SPEC (\<lambda>r. r = a + b)\<close>

fun
nres_le :: \<open>'a nres \<Rightarrow> 'a nres \<Rightarrow> bool\<close> (infix \<open>\<le>\<close> 50)
where 
  \<open>_     \<le> FAIL  \<longleftrightarrow> True\<close>
| \<open>FAIL  \<le> RES X \<longleftrightarrow> False\<close>
| \<open>RES X \<le> RES Y \<longleftrightarrow> X \<subseteq> Y\<close>

end