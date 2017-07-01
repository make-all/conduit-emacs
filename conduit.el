;;; conduit.el --- Interface to Phabricator via the Conduit API  -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Mr Maker

;; Author: Mr Maker <make-all@users.github.com>
;; Version: 0.1.0
;; URL: https://github.com/make-all/conduit-emacs#readme
;; Package-Requires:

;; Keywords: tools, comm

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library provides elisp functions for interfacing to a Phabricator
;; server via the Conduit API.  It is intended to be used by elisp developers
;; to develop user facing interfaces to various Phabricator features.

;; To call conduit methods, `conduit-phabricator-server' and
;; `conduit-api-token' must first be configured.  If you work with
;; multiple phabricator servers, it is recommended to do this on a
;; per-project basis.

;; Current implemented functions;

;; `conduit-call'
;;     - this function allows general calls to be made to conduit.
;; It takes two arguments - the method name (string), and optional
;; parameters (alist)

;; `conduit-search'
;;     - this is a higher level function to call a search endpoint.
;; It takes one mandatory argument, which is the object type to search
;; for (string), and optional args for queryKey (string), constraints
;; (alist), attachments (list) and cursor (alist).

;; `conduit-edit'
;;     - this is a higher level function to call an edit endpoint.
;; It takes two mandatory arguments, the object type to be edited or
;; created, (string) and the transactions to be performed on the
;; object (alist).  A third optional argument is available to specify
;; an object id (string or int) of an existing object to edit.

;;; Code:

(require 'json)
(require 'subr-x)

(defgroup phabricator nil
  "Options for configuring access to a Phabricator server." :group 'external)

(defcustom conduit-phabricator-url nil
  "The base URL of the Phabricator instance to connect to.
For example \"https://example.phacility.com/\"." :type '(string) :group 'phabricator)

(defcustom conduit-api-token nil
  "An API token to be used to access Phabricator as `conduit-user`.
A token can be obtained under Settings / Conduit API Tokens in the Phabricator
web UI.  For your own user account, Settings can be accessed by clicking on
your profile picture, for Bot users, Settings are under Manage User."
  :type '(string) :group 'phabricator)

(defun conduit-call (method &optional args)
  "Call a conduit METHOD with ARGS.
ARGS are converted to JSON using json-encode, so should generally
be an alist.  This is the basic function for making conduit calls,
used by other higher level functions.  It may be useful in
calling other conduit methods that do not have specific higher-level
functions available.

Example Usage:
(conduit-call \"user.whoami\")
(conduit-call \"differential.createinline\"
              '((\"revisionID\" . 1) (\"filePath\" . \"README.txt\")
		(\"isNewFile\" . t) (\"lineNumber\" . 1)
		(\"content\" . \"Test comment\")))"
  ;; Dynamic bindings for url library
  (defvar url-request-method)
  (defvar url-request-extra-headers)
  (defvar url-request-data)
  (or conduit-phabricator-url (error "`conduit-phabricator-url' is not set"))
  (or conduit-api-token (error "`conduit-api-token' is not set"))
  (let ((url (concat (string-remove-suffix "/" conduit-phabricator-url) "/api/" method))
	(url-request-method "POST")
	(url-request-extra-headers '(("Content-type" . "application/x-form-urlencoded")))
        (params (concat "output=json&params="
		      (json-encode
			 (push `("__conduit__" . (("token" . ,conduit-api-token))) args)))))
      (message "Calling %s with params %s" url params)
      (let* ((url-request-data params)
	   (result-buffer (url-retrieve-synchronously url))
	   (result-json (and (bufferp result-buffer)
			     (with-temp-buffer
			       (url-insert result-buffer)
			       (goto-char (point-min))
			       (json-read)))))
      (and (bufferp result-buffer) (kill-buffer result-buffer))
      (if result-json
	  (let ((result (cdr (assoc 'result result-json)))
		(err-msg (cdr (assoc 'error_info result-json)))
		(err-code (cdr (assoc 'error_code result-json))))
	    (if err-code
		(error "Error %s in %s: %s" err-code method err-msg)
	      (kill-buffer result-buffer)
	      result))
	(error "No result returned for %s" method)))))

(defun conduit-search (object-type &optional query constraints attachments cursor)
  "Call the search endpoint for OBJECT-TYPE.

A string QUERY can be supplied to select a query other than all
visible objects.

An alist of CONSTRAINTS can be supplied to further filter the results.

A list of object types for ATTACHMENTS can be supplied to fetch
associated attachments with the results.

An alist CURSOR can be supplied to specify after, before order
and limit criteria.  The after and before parameters should come
from a previous query to page through results.

See https://secure.phabricator.com/book/phabricator/article/conduit_search/
in addition to the Conduit API documentation for the specific search
method for more information.

Example Usage:
(conduit-search \"project\" \"active\")
(conduit-search \"differential.revision\" nil
		'((\"projects\" . (\"MyProject\")))
		'(\"reviewers\")
		'((\"limit\" . 10)))"
  (let ((conduit-method (concat object-type ".search"))
	(args nil))
    (and query (push `("queryKey" . ,query) args))
    (and constraints (push `("constraints" . ,constraints) args))
    (and attachments (push `("attachments" . ,(mapcar (lambda (x) (cons x t)) attachments)) args))
    (and cursor
	(let ((order (cdr (assoc "order" cursor)))
	      (after (cdr (assoc "after" cursor)))
	      (before (cdr (assoc "before" cursor)))
	      (limit (cdr (assoc "limit" cursor))))
	  (and order (push `("order" . ,order) args))
	  (and after (push `("after" . ,(format "%s" after)) args)
	    (and before (push `("before" . ,(format "%s" before)) args)))
	  (and limit (push `(limit . ,limit) args))))
    (conduit-call conduit-method args)))

(defun conduit-edit (object-type transactions &optional object-id)
  "Call the edit endpoint for OBJECT-TYPE with TRANSACTIONS.

An optional string or integer OBJECT-ID can be supplied to identify an
existing object to edit.  Otherwise a new object will be created.

OBJECT-TYPE should be a string identifying the type of object.

TRANSACTIONS should be an alist of transaction types with their values.

See https://secure.phabricator.com/book/phabricator/article/conduit_edit/
in addition to the Conduit API documentation for the specific
edit method for more information.

Example Usage:
(conduit-edit \"paste\" '((\"title\" . \"Example\")
                        (\"text\" . \"Hello World\")))
(conduit-edit \"paste\" '((\"comment\" . \"Nice work!\")) 1)"
  (let ((conduit-method (concat object-type ".edit"))
	(args `(("transactions" . ,(mapcar (lambda (x)
					     (list (cons "type" (car x))
						   (cons "value" (cdr x))))
					   transactions)))))
    (and object-id (push `("objectIdentifier" . ,object-id) args))
    (conduit-call conduit-method args)))

(provide 'conduit)
;;; conduit.el ends here
