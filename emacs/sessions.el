;;; sessions.el --- Every Mac's Claude Code sessions, in one list -*- lexical-binding: t; -*-

;; M-x sessions lists what `sessions --json' (hosts/mac.nix) finds on every
;; Mac. RET opens a background session (claude --bg) in a vterm buffer,
;; attached over ssh when it runs on another Mac; c starts a background
;; session on a Mac; b moves a session started in a terminal to the
;; background once you've quit it there (claude --bg --resume), so it opens
;; from here; g refreshes.

(require 'tabulated-list)
(defvar vterm-shell)  ; vterm's, bound around (vterm) below

(defvar sessions--here nil
  "The Macs the last refresh found to be this one.")

(defun sessions--parse ()
  "The JSON from `sessions --json' in the current buffer."
  (goto-char (point-min))
  (json-parse-buffer :object-type 'alist :array-type 'list
                     :null-object nil :false-object nil))

;; Nothing here waits on another Mac: the daemon serves every emacsclient, so
;; a synchronous call to one that's asleep (ssh waits on it) would freeze
;; them all. Each runs as a process, and its sentinel carries on.

(defun sessions--run (command done)
  "Run the shell COMMAND in the background; then call DONE.
DONE gets the exit status and the output, trimmed."
  (let ((out (generate-new-buffer " *sessions-run*")))
    (make-process
     :name "sessions" :buffer out :noquery t :connection-type 'pipe
     :command (list "sh" "-c" command)
     :sentinel
     (lambda (proc _event)
       (unless (process-live-p proc)
         (let ((status (process-exit-status proc))
               (text (with-current-buffer out (string-trim (buffer-string)))))
           (kill-buffer out)
           (funcall done status text)))))))

(defun sessions--fetch (done)
  "Ask every Mac in the background, with `sessions --json'; then call DONE.
DONE gets the list of Macs, or nil if `sessions --json' failed."
  (sessions--run "exec sessions --json 2>/dev/null"
                 (lambda (status text)
                   (if (zerop status)
                       (funcall done (with-temp-buffer
                                       (insert text)
                                       (sessions--parse)))
                     (message "sessions --json failed (exit %d)" status)
                     (funcall done nil)))))

(defun sessions--entries (macs)
  "Rows for `tabulated-list-entries', one per session (or unreachable Mac).
MACS is the list from `sessions --json'."
  (let (rows)
    (setq sessions--here nil)
    (dolist (m macs)
      (let ((host (alist-get 'host m)))
        (when (alist-get 'here m) (push host sessions--here))
        (if (not (alist-get 'reachable m))
            (push (list (list host nil nil nil nil) (vector host "" "unreachable" "" "")) rows)
          (dolist (a (alist-get 'agents m))
            (let ((name (or (alist-get 'name a) ""))
                  (kind (or (alist-get 'kind a) "")))
              (push (list (list host name kind (alist-get 'sessionId a) (alist-get 'cwd a))
                          (vector host name (format "%s" (or (alist-get 'status a) ""))
                                  kind
                                  (replace-regexp-in-string
                                   "\\`/Users/[^/]+" "~" (or (alist-get 'cwd a) ""))))
                    rows))))))
    (nreverse rows)))

(defvar-local sessions--refreshing 0
  "Counts this buffer's refreshes; only the latest one's answer is shown.")

(defun sessions--refresh ()
  "Refresh the list in the background, so Emacs isn't held up meanwhile."
  (let* ((buf (current-buffer))
         (n (setq sessions--refreshing (1+ sessions--refreshing))))
    (setq mode-line-process ":refreshing")
    (sessions--fetch
     (lambda (macs)
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (when (= n sessions--refreshing)
             (setq mode-line-process nil)
             (when macs
               (setq tabulated-list-entries (sessions--entries macs))
               (tabulated-list-print t))
             (force-mode-line-update))))))))

(defun sessions--refresh-list ()
  "Refresh the *sessions* buffer, if it's open."
  (let ((buf (get-buffer "*sessions*")))
    (when buf (with-current-buffer buf (sessions--refresh)))))

(defun sessions--command (host cmd)
  "CMD as a shell command run on HOST: here, or over ssh with a terminal."
  (if (member host sessions--here)
      cmd
    (format "ssh -t %s %s" (shell-quote-argument host)
            (shell-quote-argument (format "zsh -lc %s" (shell-quote-argument cmd))))))

(defun sessions-open ()
  "Open the background session on this line in a vterm buffer."
  (interactive)
  (pcase-let ((`(,host ,name ,kind . ,_) (tabulated-list-get-id)))
    (cond
     ((not name) (user-error "%s can't be reached" host))
     ((not (equal kind "background"))
      (user-error "%s was started in a terminal: quit it there, then press b to move it to the background" name))
     (t
      (require 'vterm)
      (let ((buf (format "*session: %s/%s*" host name)))
        ;; One whose attach has ended (the session stopped, or the
        ;; connection dropped) is started again rather than shown dead.
        (when (and (get-buffer buf) (not (process-live-p (get-buffer-process buf))))
          (let ((kill-buffer-query-functions nil)) (kill-buffer buf)))
        (if (get-buffer buf)
            (pop-to-buffer-same-window buf)
          (let ((vterm-shell (sessions--command
                              host (format "claude attach %s" (shell-quote-argument name)))))
            (vterm buf))))))))

(defun sessions-start (host dir prompt)
  "Start a background Claude Code session on HOST in DIR with PROMPT."
  (interactive
   (list (completing-read "Mac: " (delete-dups (mapcar (lambda (e) (car (car e)))
                                                        tabulated-list-entries))
                          nil t)
         (read-string "Folder on that Mac: " "~/repos/")
         (read-string "First prompt: ")))
  (message "Starting a session on %s..." host)
  (sessions--run (sessions--command
                  host (format "cd %s && claude --bg %s" dir (shell-quote-argument prompt)))
                 (lambda (_status text)
                   (message "%s: %s" host text)
                   (sessions--refresh-list))))

(defun sessions-background ()
  "Continue the terminal session on this line in the background, once quit.
Claude Code can resume a session in the background under the same ID only
after it has stopped in its terminal (otherwise it starts a copy)."
  (interactive)
  (pcase-let ((`(,host ,name ,kind ,id ,cwd) (tabulated-list-get-id)))
    (cond
     ((not name) (user-error "%s can't be reached" host))
     ((equal kind "background") (user-error "%s already runs in the background: RET opens it" name))
     ((not (y-or-n-p (format "Have you quit %s in its terminal (/exit)? " name)))
      (message "Quit it there first, then press b again"))
     (t
      (message "Checking %s has stopped on %s..." name host)
      (sessions--fetch
       (lambda (macs)
         (cond
          ((null macs))
          ((seq-some (lambda (e) (equal (nth 3 (car e)) id)) (sessions--entries macs))
           (message "%s is still running on %s: quit it in its terminal first" name host))
          (t
           (sessions--run (sessions--command
                           host (format "cd %s && claude --bg --resume %s"
                                        (shell-quote-argument cwd)
                                        (shell-quote-argument id)))
                          (lambda (_status text)
                            (message "%s: %s" host text)
                            (sessions--refresh-list)))))))))))

(defvar sessions-mode-map (make-sparse-keymap)
  "Keys of `sessions-mode'; set each load, so reloading updates them.")
(set-keymap-parent sessions-mode-map tabulated-list-mode-map)
(keymap-set sessions-mode-map "RET" #'sessions-open)
(keymap-set sessions-mode-map "b" #'sessions-background)
(keymap-set sessions-mode-map "c" #'sessions-start)

(define-derived-mode sessions-mode tabulated-list-mode "Sessions"
  "Every Mac's Claude Code sessions."
  (setq tabulated-list-format
        [("Mac" 6 t) ("Session" 36 t) ("Status" 9 t) ("Kind" 12 t) ("Folder" 0 t)])
  (setq tabulated-list-padding 1)
  (add-hook 'tabulated-list-revert-hook #'sessions--refresh nil t)
  (tabulated-list-init-header))

(defun sessions ()
  "List every Mac's Claude Code sessions."
  (interactive)
  (let ((buf (get-buffer-create "*sessions*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'sessions-mode) (sessions-mode))
      (tabulated-list-print t)
      (sessions--refresh))
    (pop-to-buffer-same-window buf)))

(provide 'sessions)
;;; sessions.el ends here
