;;; init.el --- Emacs configuration -*- lexical-binding: t; -*-

;; An Emacs opened from the Dock or Finder gets launchd's PATH, without the
;; Nix profiles or ~/.local/bin (claude, sessions); give it a terminal's, as
;; the daemon's launchd agent does (hosts/mac.nix).
(when (eq system-type 'darwin)
  (dolist (d (reverse (list "~/.local/bin" "~/.nix-profile/bin"
                            (format "/etc/profiles/per-user/%s/bin" user-login-name)
                            "/run/current-system/sw/bin"
                            "/nix/var/nix/profiles/default/bin")))
    (let ((d (expand-file-name d)))
      (when (and (file-directory-p d) (not (member d exec-path)))
        (push d exec-path)
        (setenv "PATH" (concat d ":" (getenv "PATH")))))))


;; The daemon is terminal-only (emacs-nox, hosts/mac.nix), without the tool
;; bar or scroll bars.
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(menu-bar-mode -1)

;; The mouse in terminal frames (emacsclient -t, from Ghostty or over ssh):
;; the touchpad scrolls the window under it and clicks move point. Without
;; it, Ghostty turns scrolling into arrow keys, as for any full-screen
;; program that doesn't ask for the mouse.
(xterm-mouse-mode 1)

;; Built-in dark theme (Modus, since Emacs 28): high contrast.
(load-theme 'modus-vivendi t)


(use-package nix-mode
  :mode "\\.nix\\'")

(use-package magit
  :commands magit-status)

(require 'server)

;; The daemon (hosts/mac.nix) starts its own server; a GUI Emacs started
;; beside it leaves the server to it.
(unless (or (daemonp) (server-running-p))
  (server-start))

;; A terminal in Emacs (M-x vterm), for Claude Code or anything else.
;; Claude Code redraws all the time, and vterm snaps back to the cursor on
;; every redraw, so scrolling back freezes the buffer first: the wheel (or
;; C-c C-t) enters copy mode, where the buffer holds still to scroll, search
;; and copy; RET or C-c C-t again returns to the live terminal. A long
;; conversation needs far more than the default 1000 lines of scrollback.
;; (Scrolls by lines: mwheel-scroll isn't loaded in a terminal frame.)
(defun tt-vterm-scroll-back (_event)
  "Freeze this vterm buffer (copy mode) and scroll back."
  (interactive "e")
  (unless vterm-copy-mode (vterm-copy-mode 1))
  (scroll-down 3))
(defun tt-vterm-scroll-forward (_event)
  "In copy mode, scroll forward."
  (interactive "e")
  (when vterm-copy-mode (scroll-up 3)))
(use-package vterm
  :commands vterm
  :custom (vterm-max-scrollback 100000)
  :bind ((:map vterm-mode-map
          ("<wheel-up>" . tt-vterm-scroll-back)
          ("<mouse-4>" . tt-vterm-scroll-back)
          ("<wheel-down>" . tt-vterm-scroll-forward)
          ("<mouse-5>" . tt-vterm-scroll-forward))
         (:map vterm-copy-mode-map
          ("<wheel-up>" . tt-vterm-scroll-back)
          ("<wheel-down>" . tt-vterm-scroll-forward))))

;; M-x sessions: every Mac's Claude Code sessions (sessions.el).
(load (expand-file-name "sessions" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(use-package markdown-mode
  :mode "\\.md\\'")

(use-package gptel
  :commands (gptel gptel-send gptel-menu))

(use-package rust-mode
  :mode "\\.rs\\'")

;; TRAMP: a GUI Emacs here editing another Mac's files, e.g.
;; C-x C-f /ssh:m4:~/repos/tinytrader-ops/research/foo.py
;; ssh/config's ControlMaster already shares one connection per Mac, so
;; TRAMP uses it rather than opening its own. Remote commands get that Mac's
;; login PATH (Nix's git, uv), backups, auto-saves and lock files stay out
;; of the remote folders, and version control isn't asked about remote
;; files (a round trip per file shown; magit still works there).
(with-eval-after-load 'tramp
  (setq tramp-default-method "ssh"
        tramp-use-connection-share nil   ; ssh/config's ControlMaster
        tramp-verbose 1
        remote-file-name-inhibit-locks t
        remote-file-name-inhibit-auto-save-visited t
        tramp-auto-save-directory (locate-user-emacs-file "tramp-auto-save/"))
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path)
  (add-to-list 'backup-directory-alist
               (cons tramp-file-name-regexp
                     (locate-user-emacs-file "tramp-backups/")))
  (setq vc-ignore-dir-regexp
        (format "\\(?:%s\\)\\|\\(?:%s\\)"
                vc-ignore-dir-regexp tramp-file-name-regexp))
  ;; Run remote processes (compile, magit's git) directly over ssh.
  (connection-local-set-profile-variables
   'remote-direct-async-process '((tramp-direct-async-process . t)))
  (connection-local-set-profiles
   '(:application tramp :protocol "ssh") 'remote-direct-async-process))

;; Org as a notebook (emacs-jupyter): `python' src blocks run in a Jupyter
;; kernel, one per :session, like a notebook's cells. The default kernel is
;; tinytrader-ops' venv, registered with
;;   ~/repos/tinytrader-ops/.venv/bin/python -m ipykernel install --user --name tinytrader-ops
;; and a file can pick another with `#+PROPERTY: header-args:python :kernel NAME'.
;; The daemon is terminal-only, so plots are written to files (`:file
;; plot.png', or the [[file:...]] links a block returns) and opened outside
;; Emacs (C-c C-o), not shown inline.
(use-package jupyter
  :after org
  :config
  (setq org-babel-default-header-args:jupyter-python
        '((:kernel . "tinytrader-ops")
          (:session . "py")
          (:async . "yes")))
  (org-babel-do-load-languages
   'org-babel-load-languages
   (append org-babel-load-languages '((python . t) (jupyter . t))))
  (org-babel-jupyter-override-src-block "python")
  (add-hook 'org-babel-after-execute-hook #'org-redisplay-inline-images)
  ;; Org 9.8 needs a drawer's :pre-blank, which emacs-jupyter's results
  ;; drawer (a block with several outputs, e.g. text and a plot) leaves nil:
  ;; inserting it fails with (wrong-type-argument wholenump nil).
  (define-advice jupyter-org-results-drawer (:filter-return (drawer) pre-blank)
    (unless (org-element-property :pre-blank drawer)
      (org-element-put-property drawer :pre-blank 0))
    drawer))

;; (use-package gptel
;;   :config
;;   (require 'gptel-openai-oauth)
;;   (setq gptel-openai-oauth-login-method 'device
;;         gptel-model 'gpt-5.6-luna
;;         gptel-backend
;;         (gptel-make-openai-oauth "OpenAI-sub")))

;; (use-package gptel
;;   :demand t
;;   :commands (gptel gptel-send gptel-menu)
;;   :config
;;   (require 'gptel-openai-oauth)
;;   (setq gptel-model 'gpt-5.6-luna
;;         gptel-openai-oauth-login-method 'device
;;         gptel-backend
;;         (gptel-make-openai-oauth "OpenAI-sub")))

(use-package gptel
  :ensure nil
  :demand t
  :config
  (require 'gptel-openai-oauth)
  (setq gptel--openai-oauth-token-file
        (expand-file-name
         "gptel-openai"
         (or (getenv "XDG_DATA_HOME")
             (expand-file-name "~/.local/share"))))
  (setq gptel-model 'gpt-5.6-luna
        gptel-openai-oauth-login-method 'device
        gptel-backend
        (gptel-make-openai-oauth "OpenAI-sub")))


(use-package gptel-agent
  :ensure nil
  :after gptel)


;; Platform-specific code
;; Probably refactored out to ~/repos/nix-config/hosts/ once warranted
(when (eq system-type 'darwin)
  (setq mac-command-modifier 'meta))

(when (eq system-type 'gnu/linux)
  ;; Linux-specific settings
  )
