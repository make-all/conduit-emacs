# An Elisp Conduit Library

This library provides elisp functions for interfacing to a Phabricator
server via the Conduit API.  It is intended to be used by elisp developers
to develop user facing interfaces to various Phabricator features in Emacs.

To call conduit methods, `conduit-phabricator-server` and `conduit-api-token`
must first be configured.  If you work with multiple phabricator servers,
it is recommended to do this on a per-project basis.

## Available functions

`conduit-call` - this function allows general calls to be made to conduit.
It takes two arguments - the method name (string), and optional
parameters (alist)

`conduit-search` - this is a higher level function to call a search endpoint.
It takes one mandatory argument, which is the object type  to search for
(string), and optional args for queryKey (string), constraints (alist),
attachments (list) and cursor (alist).

`conduit-edit' - this is a higher level function to call an edit endpoint.
It takes two mandatory arguments, the object type to be edited or created,
(string) and the transactions to be performed on the object (alist).
A third optional argument is available to specify an object id (string
or int) of an existing object to edit.
