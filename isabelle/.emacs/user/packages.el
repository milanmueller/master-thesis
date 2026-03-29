;; -*- no-byte-compile: t; -*-
;;; packages.el

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect.
;;
;; (package! some-package)
;; (package! some-package :recipe (:host github :repo "username/repo"))
;; (package! built-in-package :disable t)

(package! isar-mode
   :recipe (:host github :repo "m-fleury/isar-mode"))

(package! isar-goal-mode
   :recipe (:host github :repo "m-fleury/isar-mode"))

(package! lsp-isar
   :recipe (:local-repo "../../isabelle-emacs/src/Tools/emacs-lsp/lsp-isar/"))

(package! lsp-isar-parse-args
   :recipe (:local-repo "../../isabelle-emacs/src/Tools/emacs-lsp/lsp-isar/"))

(package! session-async)
(package! catppuccin-theme)
