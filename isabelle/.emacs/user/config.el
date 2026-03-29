;;; config.el -*- lexical-binding: t; -*-

;; General Config
(setq doom-theme 'doom-one)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode t)
(setq shell-file-name (executable-find "bash"))
(setq doom-theme 'catppuccin)
(setq catppuccin-flavor 'latte)
(setq-default tab-width 2)
(setq window-divider-default-right-width 4
      window-divider-default-bottom-width 4)

;; Isabelle Setup
(use-package! isar-mode
  :mode "\\.thy\\'"
  :config
  ;; (add-hook 'isar-mode-hook 'turn-on-highlight-indentation-mode)
  ;; (add-hook 'isar-mode-hook 'flycheck-mode)
  (add-hook 'isar-mode-hook 'company-mode)
  (add-hook 'isar-mode-hook
            (lambda ()
              (set (make-local-variable 'company-backends)
                   '((company-dabbrev-code company-yasnippet)))))
  (add-hook 'isar-mode-hook
            (lambda ()
              (set (make-local-variable 'indent-tabs-mode) nil)))
  (add-hook 'isar-mode-hook
            (lambda ()
              (yas-minor-mode)))
  )

(use-package! lsp-isar-parse-args
  :custom
  (lsp-isar-parse-args-nollvm nil))

(use-package! lsp-isar
  :commands lsp-isar-define-client-and-start
  :custom
  (lsp-isar-output-use-async t)
  (lsp-isar-experimental t)
  (lsp-isar-split-pattern 'lsp-isar-split-pattern-three-columns)
  (lsp-isar-decorations-delayed-printing t)
  :init
  (add-hook 'lsp-isar-init-hook 'lsp-isar-open-output-and-progress-right-two-columns)
  (add-hook 'isar-mode-hook #'lsp-isar-define-client-and-start)

  (push (concat "/home/milan/git/isabelle-big-numbers/isabelle-emacs/src/Tools/emacs-lsp/yasnippet")
   yas-snippet-dirs)
  (setq lsp-isar-path-to-isabelle "/home/milan/git/isabelle-big-numbers/isabelle-emacs")
  (setq lsp-isabelle-options (list "-l" "Isabelle_LLVM"))
)
;; https://github.com/m-fleury/isabelle-release/issues/21
(defun ~/evil-motion-range--wrapper (fn &rest args)
  "Like `evil-motion-range', but override field-beginning for performance.
     See URL `https://github.com/ProofGeneral/PG/issues/427'."
          (cl-letf (((symbol-function 'field-beginning)
                                  (lambda (&rest args) 1)))
                       (apply fn args)))

            (advice-add #'evil-motion-range :around #'~/evil-motion-range--wrapper)

