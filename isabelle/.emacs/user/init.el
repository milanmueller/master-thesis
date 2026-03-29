;;; init.el -*- lexical-binding: t; -*-

;; This file controls which Doom modules are enabled and their order.
;; Press 'K' on a module to view its documentation, and 'gd' to browse its directory.

(doom! :input
       ;;bidi              ; (not included in defaults)
       ;;chinese
       ;;japanese
       ;;layout            ; aufteilung für andere tastaturen

       :completion
       company             ; code completion backend
       vertico             ; minibuffer completion

       :ui
       doom                ; Doom look & feel
       doom-dashboard      ; splash screen
       hl-todo             ; highlight TODO/FIXME/NOTE
       modeline            ; statusleiste
       (popup +defaults)   ; popup-window-management
       (vc-gutter +pretty) ; vcs-diff im fringe
       vi-tilde-fringe     ; tilden am zeilenende
       workspaces          ; tab-emulation

       :editor
       (evil +everywhere)  ; vim-keybindings
       file-templates      ; snippets für leere dateien
       fold                ; code-folding
       snippets            ; snippets
       undo                ; undo-tree

       :emacs
       dired               ; datei-browser
       electric            ; auto-indent
       undo                ; undo-verlauf
       vc                  ; git-integration

       :term
       ;;vterm

       :checkers
       syntax              ; on-the-fly syntax-check
       ;;spell

       :tools
       (eval +overlay)     ; code ausführen
       lookup              ; dokumentation & code-navigation
       lsp                 ; language server protocol
       magit               ; git porcelain
       tree-sitter         ; syntax-highlighting via tree-sitter

       :os
       (:if (featurep :system 'macos) macos)
       tty                 ; terminal-emacs verbesserungen

       :lang
       emacs-lisp          ; elisp
       json                ; json
       latex               ; latex (für isabelle-papiere)
       markdown            ; markdown
       nix                 ; nix
       (org +roam2)        ; org-mode
       sh                  ; shell-scripting
       yaml                ; yaml

       :config
       (default +bindings +smartparens)
)
