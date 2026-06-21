;;; eglot-csharp.el --- C# metadata URI support for Eglot -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 duli kiles
;;
;; Author: duli kiles <duli4868@gmail.com>
;; Maintainer: duli kiles <duli4868@gmail.com>
;; Version: 1.0.0
;; Keywords: eglot
;; Homepage: https://github.com/kilesduli/eglot-csharp
;; Package-Requires: ((emacs "29.1"))
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; This package adds support for accessing `csharp-ls' metadata URIs through
;; the `csharp/metadata' RPC method, so Eglot features such as xref definition
;; lookup can open generated or decompiled metadata source.
;;
;; To use it, require this package. It intentionally provides no autoloaded
;; commands.
;;
;; To disable metadata URI support:
;;
;;   (setq ec-enable-csharp-metadata-support nil)
;;
;;; Code:
(require 'eglot)
(require 'cl-lib)

(defvar ec-enable-csharp-metadata-support t
  "Whether to enable metadata URI support for csharp-ls.")

(defvar ec-request-table (make-hash-table :test #'equal))

(cl-defmethod eglot-client-capabilities :around (server)
  (let ((capabilities (cl-call-next-method)))
    (when (and ec-enable-csharp-metadata-support
               (cl-find "csharp-ls" (process-command
                                     (jsonrpc--process server))
                        :test #'string-match))
      (let* ((exp (plist-get capabilities :experimental))
             (old (if (eq exp eglot--{}) '() exp))
             (new (plist-put old :csharp '(:metadataUris t))))
        (plist-put capabilities :experimental new)))
    capabilities))

(defun ec-retrival-file-component-from-uri (uri)
  (when (string-match "\\`csharp:\\(.*/\\)[^/]+\\.csproj/\\(decompiled\\|generated\\)/\\(.+\\)\\'" uri)
    (list (match-string 1 uri)
          (match-string 2 uri)
          (match-string 3 uri))))

(defun ec-normalize-file-name (uri)
  (let ((components (ec-retrival-file-component-from-uri uri)))
    (setq components (apply #'list (car components) ".cache" (cdr components)))
    (apply #'file-name-concat components)))

(defun ec-read-uri-file-as-string (filename)
  (with-temp-buffer
    (insert-file-contents (concat filename ".uri"))
    (buffer-string)))

(defun ec-async-request-metadata (uri)
  (let (request-id)
    (setq request-id (eglot--async-request
                      (eglot--current-server-or-lose)
                      :csharp/metadata
                      (list :textDocument `(:uri ,uri))
                      :hint :csharp/metadata ;; must have this
                      :success-fn
                      (eglot--lambda (projectName assemblyName symbolName source)
                        (ignore projectName assemblyName symbolName)
                        (if source
                            (let* ((unhex-uri (decode-coding-string (url-unhex-string uri)
                                                                    'utf-8))
                                   (filename (ec-normalize-file-name unhex-uri))
                                   (urifile (concat filename ".uri"))
                                   (buffer (find-buffer-visiting filename)))
                              (unless (file-directory-p (file-name-directory filename))
                                (make-directory (file-name-directory filename) t))
                              (with-temp-file urifile
                                (insert uri))
                              (with-temp-file filename
                                (insert source))
                              (when buffer
                                (with-current-buffer buffer
                                  (revert-buffer t t)))
                              (remhash uri ec-request-table))
                          (message "no source finded")))
                      :error-fn
                      (lambda (result)
                        (ignore result)
                        (remhash uri ec-request-table)
                        (message "csharp/metadata failed"))))
    request-id))

(defun ec-uri-to-path (uri)
  "Translate csharp metadata URI to a local cache path."
  (if (and ec-enable-csharp-metadata-support
           (string-prefix-p "csharp:" uri))
      (let* ((unhex-uri (decode-coding-string (url-unhex-string uri)
                                              'utf-8))
             (filename (ec-normalize-file-name unhex-uri))
             (urifile (concat filename ".uri")))
        (unless (or (gethash uri ec-request-table)
                    (file-exists-p urifile))
          (puthash uri (ec-async-request-metadata uri) ec-request-table))
        filename)
    uri))

(defun ec-path-to-uri (oldfn &rest args)
  "Return the original metadata URI for cached paths, or call OLDFN with args."
  (if (and ec-enable-csharp-metadata-support
           (file-exists-p (concat (car-safe args) ".uri")))
      (ec-read-uri-file-as-string (car-safe args))
    (apply oldfn args)))

(advice-add #'eglot-uri-to-path :filter-return #'ec-uri-to-path)
(advice-add #'eglot-path-to-uri :around        #'ec-path-to-uri)

(provide 'eglot-csharp)
;;; eglot-csharp.el ends here

;; Local Variables:
;; read-symbol-shorthands: (("ec" . "eglot-csharp"))
;; End:
