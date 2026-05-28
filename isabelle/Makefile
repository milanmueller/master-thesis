# We use the Isabelle binary from isabelle-emacs
PWD=$(shell pwd)
BIN=$(PWD)/bin
ISABELLE_BIN=$(PWD)/isabelle-emacs/bin/isabelle
AFP=$(PWD)/mirror-afp-2025-1
ISA_FOL=$(PWD)/IsaFoL
ISA_FOL_CUSTOM=$(PWD)/IsaFoL-Pasteque-LLVM
ISABELLE_LLVM=$(PWD)/isabelle_llvm
ISABELLE_BIGINT=$(PWD)/IsabelleBigInteger

all:
	echo "Hello, World!"

build:
	$(ISABELLE_BIN) build

build_devbase:
	$(ISABELLE_BIN) build -b -d . -d $(ISABELLE_LLVM)/thys -d $(AFP)/thys DevBase

build_pasteque_sml:
	ISAFOL=$(ISA_FOL) $(ISABELLE_BIN) build -d $(AFP)/thys -d $(ISABELLE_LLVM)/thys -d $(ISA_FOL)/Weidenbach_Book -b -D $(ISA_FOL)/PAC_Checker2
	mlton -output $(BIN)/pasteque-sml -const 'MLton.safe false' -verbose 1 -default-type int64 -codegen native -inline 700 -cc-opt -O3 $(ISA_FOL)/PAC_Checker2/code/pasteque.mlb

build_bigint:
	$(ISABELLE_BIN) build -d $(ISABELLE_LLVM)/thys -b -D $(ISABELLE_BIGINT)

echo_vars:
	echo "Isabelle binary: $(ISABELLE_BIN)"
	echo "AFP: $(AFP)"
	echo "IsaFoL: $(ISA_FOL)"
	echo "IsaFoL custom: $(ISA_FOL_CUSTOM)"
	echo "Isabelle-LLVM: $(ISABELLE_LLVM)"
	echo "Isabelle-BigInt: $(ISABELLE_BIGINT)"
	echo "Isabelle Home: $(ISABELLE_HOME)"
	echo "Isabelle User Home: $(ISABELLE_HOME_USER)"
	echo "User Home: $(USER_HOME)"

.PHONY: echo_vars build_pasteque_sml build build_devbase all
