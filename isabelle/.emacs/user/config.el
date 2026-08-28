;;; config.el -*- lexical-binding: t; -*-

;; Toggle comment on region or current line
(defun my/toggle-comment ()
  (interactive)
  (if (use-region-p)
      (comment-or-uncomment-region (region-beginning) (region-end))
    (comment-line 1)))
(global-set-key (kbd "C-/") #'my/toggle-comment)

;; Remove window titlebar/decorations
(add-to-list 'default-frame-alist '(undecorated . t))

;; General Config
;; Parse OSC 4 color definitions from ~/.zshrc and populate Emacs's color table,
;; so base16-theme 'colors source works in GUI Emacs.
(defun my/load-terminal-colors-from-zshrc ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "~/.zshrc"))
    (goto-char (point-min))
    (while (re-search-forward
            (rx "\\033]4;" (group (+ digit)) ";rgb:"
                (group (= 2 hex)) "/" (group (= 2 hex)) "/" (group (= 2 hex)))
            nil t)
      (let* ((slot (string-to-number (match-string 1)))
             (r    (* (string-to-number (match-string 2) 16) 257))
             (g    (* (string-to-number (match-string 3) 16) 257))
             (b    (* (string-to-number (match-string 4) 16) 257)))
        (tty-color-define (format "color-%d" slot) slot (list r g b))))))
(my/load-terminal-colors-from-zshrc)
(add-hook 'after-make-frame-functions (lambda (_) (my/load-terminal-colors-from-zshrc)))

(setq base16-theme-256-color-source 'colors)
(use-package doom-themes
  :ensure t
  :custom
  ;; Global settings (defaults)
  (doom-themes-enable-bold t)   ; if nil, bold is universally disabled
  (doom-themes-enable-italic t) ; if nil, italics is universally disabled
  ;; for treemacs users
  (doom-themes-treemacs-theme "doom-atom") ; use "doom-colors" for less minimal icon theme
  :config
  (load-theme 'doom-one-light t)

  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)
  ;; Enable custom neotree theme (nerd-icons must be installed!)
  (doom-themes-neotree-config)
  ;; or for treemacs users
  (doom-themes-treemacs-config)
  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config)
)
(solaire-global-mode +1)
; (setq doom-theme 'catppuccin)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode t)
(setq shell-file-name (executable-find "bash"))
; (setq catppuccin-flavor 'latte)
; (setq catppuccin-flavor 'frappe)
(setq-default tab-width 2)
(setq window-divider-default-right-width 4
      window-divider-default-bottom-width 4)
;; Use Helix Mode
(use-package helix :ensure t :config (helix-mode))
(helix-mode)

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

  (push (expand-file-name "isabelle-emacs/src/Tools/emacs-lsp/yasnippet" (getenv "USER_HOME"))
   yas-snippet-dirs)
  (setq lsp-isar-path-to-isabelle (expand-file-name "isabelle-emacs" (getenv "USER_HOME")))
  (setq lsp-isabelle-options (list "-l" "PAC_Checker_LLVM"))
)
(after! lsp-isar-decorations
  (custom-set-faces
   '(lsp-isar-font-background-quoted ((t (:inherit font-lock-comment-face))))
   '(lsp-isar-font-foreground-quoted ((t (:inherit font-lock-doc-face))))))
;; https://github.com/m-fleury/isabelle-release/issues/21
(defun ~/evil-motion-range--wrapper (fn &rest args)
  "Like `evil-motion-range', but override field-beginning for performance.
     See URL `https://github.com/ProofGeneral/PG/issues/427'."
          (cl-letf (((symbol-function 'field-beginning)
                                  (lambda (&rest args) 1)))
                       (apply fn args)))

            (advice-add #'evil-motion-range :around #'~/evil-motion-range--wrapper)

