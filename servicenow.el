;;; servicenow.el --- integrate with servicenow -*- lexical-binding: t -*-

;; Author: Julian Hoch
;; Maintainer: Julian Hoch
;; Version: 0.1.0
;; Package-Requires: (plz)
;; Homepage: https://github.com/julian-hoch/ServiceNow.el
;; Keywords: servicenow


;; This file is not part of GNU Emacs

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; ServiceNow.el attempts to provide a simple interface to the ServiceNow REST
;; API for Emacs packages.

;; It supports OAuth authentication, and wraps the low-level REST API calls and
;; provides a somewhat simplifid interface.  It also implements the most
;; important parts of the Table API, making it quick and easy to retrieve or
;; modify records in a ServiceNow development instance from inside Emacs.

;;; Code:

(defgroup servicenow ()
  "Integrate with ServiceNow."
  :group 'tools)


;;; Instance Setup

(defcustom sn-instance "SET_YOUR_INSTANCE_HERE" 
  "The ServiceNow instance to connect to."
  :type 'string
  :group 'servicenow)

;;; OAuth Support
;; This section provides OAuth support for ServiceNow, allowing users to authenticate.
;; The application registry needs to be set up in ServiceNow first for this to work.

(defcustom sn-oauth-client-id "SET_YOUR_CLIENT_ID"
  "The OAuth client ID for ServiceNow."
  :type 'string
  :group 'servicenow)

(defcustom sn-oauth-client-secret "SET_YOUR_CLIENT_SECRET"
  "The OAuth client secret for ServiceNow."
  :type 'string
  :group 'servicenow)

(defcustom sn-oauth-redirect-port 38182
"The port to use for the OAuth redirect URI.")

(defvar sn--oauth-state "servicenow.el"
  "The state parameter for OAuth authentication.")

(defvar sn--oauth-code-endpoint-template "https://%s.service-now.com/oauth_auth.do?response_type=code&client_id=%s&state=%s&redirect_uri=%s")

(defvar sn--oauth-token-endpoint-template
  "https://%s.service-now.com/oauth_token.do")

(defvar sn--oauth-access-token nil
  "The OAuth access token for ServiceNow.  This is set after a successful
login or token refresh.  Only kept in memory, not persistent.")

(defvar sn--oauth-refresh-token nil
  "The OAuth refresh token for ServiceNow.  This is set after a successful
login.  This variable is only kept in memory, not persistent.")

(defcustom sn-oauth-token-store 'custom
  "Defines how the OAuth refresh token is stored."
  :type '(choice
          (const :tag "Secrets Manager" secrets)
          (const :tag "Custom Variable" custom))
  :group 'servicenow)

(defcustom sn-oauth-stored-refresh-token nil
  "The stored OAuth refresh token, if `sn-oauth-token-store' is set to
`custom'.  In that case, it will be persistent."
  :type 'string
  :group 'servicenow)

(define-error 'snc-error "ServiceNow.el error")
(define-error 'snc-not-logged-in-error "ServiceNow.el not logged in" 'snc-error)

(defun sn--oauth-redirect-uri ()
  "The redirect URI for OAuth authentication."
  (format "http://localhost:%d" sn-oauth-redirect-port))

(defun sn--oauth-code-endpoint ()
  "Construct the OAuth code endpoint URL."
  (format sn--oauth-code-endpoint-template
          sn-instance
          sn-oauth-client-id
          sn--oauth-state
          (sn--oauth-redirect-uri)))

(defun sn--oauth-token-endpoint ()
  "Construct the OAuth token endpoint URL."
  (format sn--oauth-token-endpoint-template
          sn-instance))

(defun sn--oauth-get-token (code)
  "Exchange the OAuth code for access and refresh tokens."
  (sn--oauth-retrieve-tokens "authorization_code" code))

(defun sn--oauth-refresh-token ()
  "Refresh the OAuth access token using the refresh token."
  (if-let ((refresh-token (or sn--oauth-refresh-token
                              (sn--oauth-get-token-from-secrets "servicenow.el-refresh"))))
      (sn--oauth-retrieve-tokens "refresh_token" refresh-token)
    (message "No refresh token found. Please log in again.")))

(defun sn--oauth-retrieve-tokens (grant secret)
  "Retrieve OAuth tokens using the specified GRANT
type ('authorization_code' or 'refresh_token') and SECRET."
  (message "servicenow: retrieving tokens")
  (let* ((secret-type (if (string= grant "authorization_code")
                          "code"
                        grant))
         (body (plz 'post (sn--oauth-token-endpoint)
                 :headers '(("Content-Type" . "application/x-www-form-urlencoded"))
                 :body (mm-url-encode-www-form-urlencoded
                        `( ("grant_type" . ,grant)
                           ("client_id" . ,sn-oauth-client-id)
                           ("client_secret" . ,sn-oauth-client-secret)
                           (,secret-type . ,secret)
                           ("redirect_uri" . ,(sn--oauth-redirect-uri))))))
         (alist (json-parse-string body :object-type 'alist))
         (access-token (alist-get 'access_token alist))
         (refresh-token (alist-get 'refresh_token alist)))
      (setq sn--oauth-access-token access-token)
      (setq sn--oauth-refresh-token refresh-token)
      (sn--oauth-store-refresh-token refresh-token)
      (message "Token received.")))

(defun sn--oauth-store-refresh-token (token)
  "Store the OAuth refresh TOKEN in the secrets manager."
  (if (eq sn-oauth-token-store 'secrets)
      (progn
        (secrets-delete-item "Login" "servicenow.el-refresh")
        (secrets-create-item "Login" "servicenow.el-refresh" token))
    (customize-save-variable 'sn-oauth-stored-refresh-token token)))

(defun sn--oauth-get-refresh-token-from-store ()
  "Retrieve the OAuth token from the secrets manager.  Also sets the token
in memory."
  (setq sn--oauth-refresh-token
        (if (eq sn-oauth-token-store 'secrets)
            (secrets-get-secret "Login" "servicenow.el-refresh")
          sn-oauth-stored-refresh-token)))

(defun sn--oauth-get-authorization-header ()
  "Get the Authorization header for OAuth requests."
    (if sn--oauth-access-token
        `("Authorization" . ,(format "Bearer %s" sn--oauth-access-token))
      (message "No access token found. Please log in first.")))

;;;###autoload
(defun sn-oauth-login ()
  "Login to ServiceNow using OAuth."
  (interactive)
  (defservlet* /: text/plain (code)
    (message "servicenow: received code %s" code)
    (insert "Code received. You can now close this window.")
    (sn--oauth-get-token code))
  (let ((httpd-serve-files nil)
        (httpd-port sn-oauth-redirect-port))
    (httpd-start))
  (browse-url (sn--oauth-code-endpoint))
  (message "Login request initiated.  Please continue in your browser."))

;;; Making REST Calls
;; Low level functions that allows us to simply make REST calls to arbitrary
;; ServiceNow REST API endpoints.  These functions are very universal, but also 
;; expect you to set up all the parameters yourself, and do not parse the results.

(defvar sn--max-retries 2
  "Maximum number of retries for REST API calls.")

(defvar sn--url-template "https://%s.service-now.com/%s"
  "Template for constructing ServiceNow REST API URLs.")

(defun sn--path-append-params (path &optional params)
  "Append query parameters to PATH.  If PARAMS are provided (list of
pairs), these will be added as query parameters."
  (if params
      (let ((param-string (url-build-query-string params)))
        (if (string-search "?" path)
            (format "%s&%s" path param-string)
          (format "%s?%s" path param-string)))
    path))

(defun sn--rest-endpoint (path &optional params)
  "Construct the ServiceNow REST API endpoint URL for PATH.  If PARAMS are
provided (list of pairs), these will be added as query parameters."
          (format sn--url-template sn-instance 
                  (sn--path-append-params path params)))

(defun sn--get-plz-error-type (err)
  "Figure out the error we got from plz, and return code as string.  Code
is something like \"http-401\" or \"curl-6\", depending of whether the
error was thrown by curl or the http server."
  (cl-case (car err)
    (plz-http-error
     (intern (format "http-%d"
                     (plz-response-status (plz-error-response (caddr err))))))
    (plz-curl-error
     (intern (format "curl-%d"
                     (car (plz-error-curl-error (caddr err))))))
    (t
     'unknown-error)))

(defun sn--get-plz-error-details (err)
  "Return a string with details about the plz error ERR."
  (cl-case (car err)
    (plz-http-error
     (let* ((error-payload (alist-get 'error
                                      (json-parse-string
                                       (plz-response-body (plz-error-response (caddr err)))
                                       :object-type 'alist)))
            (details (alist-get 'detail error-payload))
            (message (alist-get 'message error-payload)))
       (when (eq details :null)
         (setq details nil))
       (when (eq message :null)
         (setq message nil))
       (or details
           message
           "No details available.")))
    (plz-curl-error
     "No details available.")
    (t
     "Unknown error type (not HTTP or curl")))

(defun sn--inject-auth-headers (args)
  "Get the headers from ARGS and add the OAuth Authorization header to
them.  Update ARGS with the new headers."
  (let* ((user-headers (plist-get args :headers))
         (auth-header (sn--oauth-get-authorization-header)))
    (add-to-list 'user-headers auth-header)
    (plist-put args :headers user-headers)))

(defun sn--plz-wrapper (method url &rest args)
  "Wrapper around `plz' to handle ServiceNow REST API calls.  Will make
sure the user is authenticated and handle errors."
  (cl-labels
      ;; Set up loop to retry the request if it fails due to authentication issues.
      ((recursive-call (retry-count)
         (if (>= retry-count sn--max-retries)
             (error "Failed to retrieve data from %s after %d retries" url sn--max-retries)
           (condition-case err
               (progn
                 (let* ((args (sn--inject-auth-headers args)) 
                        (plz-response (apply 'plz method url
                                             :as 'response
                                             args))
                        (status (plz-response-status plz-response))
                        (resp-headers (plz-response-headers plz-response))
                        (is-logged-in
                         (string= (alist-get 'x-is-logged-in resp-headers) "true"))
                        (body (plz-response-body plz-response)))
                   (unless is-logged-in (signal 'snc-not-logged-in-error nil))
                   ;; Return the (raw) response body.
                   body))

             ;; Handle errors that might occur during the request.
             (snc-not-logged-in-error
              (message "Not logged in.  Trying to refresh token.")
              (sn--oauth-refresh-token)
              (sleep-for 2)
              (recursive-call (1+ retry-count)))
             (plz-error
              (setq sn--last-plz-error err)
              (cl-case (sn--get-plz-error-type err)
                (http-401
                 (message "Authentication error (401), refreshing token and retrying (%d/%d)"
                          retry-count sn--max-retries)
                 (sn--oauth-refresh-token)
                 (sleep-for 2)
                 (recursive-call (1+ retry-count)))
                (http-403
                 (error "Access denied (403). Details: %s"
                        (sn--get-plz-error-details err))) 
                (http-404
                 (error "File not found (404). Details: %s"
                        (sn--get-plz-error-details err))) 
                (http-415
                 (error "Unsupported Media Type (415). Details: %s"
                        (sn--get-plz-error-details err)))
                (http-503
                 (error "Service Unavailable (503)."))
                (curl-6
                 (error "Curl error 6 (could not resolve host)."))
                (curl-26
                 (error "Curl error 26 (various reading problems)."))
                (otherwise
                 (error "Unhandled plz error: %s.  Details: %s"
                        (sn--get-plz-error-type err)
                        err))))))))
    (recursive-call 0)))

;;;###autoload
(defun sn-get-sync-json (path &optional params)
  "Make a synchronous GET request to the ServiceNow REST API at PATH.
Result is parsed as JSON."
  (json-parse-string (sn--plz-wrapper 'get (sn--rest-endpoint path params))))

;;;###autoload
(defun sn-get-sync-raw (path &optional params) 
  "Make a synchronous GET request to the ServiceNow REST API at PATH.
Result is return as raw data."
  (sn--plz-wrapper 'get (sn--rest-endpoint path params)))

(defun sn--ppp-sync-json (method path body &optional content-type params)
  "Make a synchronous request of the given METHOD (patch/post/put) to the
ServiceNow REST API at PATH, with BODY (raw data).  Result is parsed as
JSON.  If no other CONTENT-TYPE is specified, `application/json' is used"
  (json-parse-string
   (sn--plz-wrapper method (sn--rest-endpoint path params)
                    :body body
                    :headers `(("Content-Type" .
                                ,(or content-type "application/json"))))))

(defun sn--ppp-sync-raw (method path body &optional content-type params)
  "Make a synchronous request of the given METHOD (patch/post/put) to the
ServiceNow REST API at PATH, with BODY (raw data).  Result is returned
as is.  If no other CONTENT-TYPE is specified, `application/json' is
used"
  (sn--plz-wrapper method (sn--rest-endpoint path params)
                   :body body
                   :headers `(("Content-Type" .
                               ,(or content-type "application/json")))))

;;;###autoload
(defun sn-post-sync-json (path body &optional content-type params)
  "Make a synchronous POST request to the ServiceNow REST API at PATH, with
BODY (raw data).  Result is parsed as JSON.  If no other CONTENT-TYPE is
specified, `application/json' is used"
  (sn--ppp-sync-json 'post path body content-type params))

;;;###autoload
(defun sn-post-sync-raw (path body &optional content-type params)
  "Make a synchronous POST request to the ServiceNow REST API at PATH, with
BODY (raw data).  Result is returned as is.  If no other CONTENT-TYPE is
specified, `application/xml' is used"
  (sn--ppp-sync-raw 'post path body content-type params))

;;;###autoload
(defun sn-put-sync-json (path body &optional content-type params)
  "Make a synchronous PUT request to the ServiceNow REST API at PATH, with
BODY (raw data).  Result is parsed as JSON.  If no other CONTENT-TYPE is
specified, `application/json' is used"
  (sn--ppp-sync-json 'put path body content-type params))

;;;###autoload
(defun sn-patch-sync-raw (path body &optional content-type params)
  "Make a synchronous PATCH request to the ServiceNow REST API at PATH,
with BODY (raw data).  Result is returned as is.  If no other
CONTENT-TYPE is specified, `application/json' is used"
  (sn--ppp-sync-raw 'patch path body content-type params))

;;;###autoload
(defun sn-patch-sync-json (path body &optional content-type params)
  "Make a synchronous PATCH request to the ServiceNow REST API at PATH,
with BODY (raw data).  Result is parsed as JSON.  If no other
CONTENT-TYPE is specified, `application/json' is used"
  (sn--ppp-sync-json 'patch path body content-type params))

;;;###autoload
(defun sn-delete-sync-raw (path &optional params) 
  "Make a synchronous DELETE request to the ServiceNow REST API at PATH.
Result is return as raw data."
  (sn--plz-wrapper 'delete (sn--rest-endpoint path params)))

;;; Testing the Connection

;;;###autoload
(defun sn-test ()
  "Test function to check if the ServiceNow instance is reachable."
  (interactive)
  (if (sn-get-sync-raw "ui_page.do")
      (message "ServiceNow instance %s is reachable." sn-instance)
    (message "Failed to reach ServiceNow instance %s." sn-instance)))

;;; Record API
;; Uses table.do?sys_id=12345... and parses the returned XML.
;; This retrieves just the record and its raw values - basic, but quick.

(defvar sn--record-api-template "%s.do"
  "Template for constructing ServiceNow Record API URLs.")

(defun sn--record-api-endpoint (table sys-id)
  "Construct the ServiceNow Record API endpoint URL for TABLE with SYS-ID."
  (sn--rest-endpoint
   (format sn--record-api-template table)
   `((sys_id ,sys-id)
     (XML true))))

;;;###autoload
(defun sn-get-record-xml (table sys-id)
  "Retrieve a record from the ServiceNow table TABLE with the specified
SYS-ID in XML format."
  (let ((path (sn--record-api-endpoint table sys-id)))
    (sn--plz-wrapper 'get path)))

;;; Table API
;; Uses api/now/table/<table>/<sys_id> and parse returned JSON
;; Allows for more sophisticated access, including access to display values,
;; dot-walking and selecting specific fields.  Also supports all the other CRUD
;; operations.

(defvar sn--table-api-record-template "api/now/table/%s/%s"
  "Template for constructing ServiceNow Table API URLs referencing records.")

(defvar sn--table-api-query-template "api/now/table/%s"
  "Template for constructing ServiceNow Table API URLs referencing records.")

(defun sn--table-api-append-query-params (path &optional fields displayvalues reflinks query)
  "Append common query parameters to the PATH.  If FIELDS are provided, the
parameter `sysparm_fields' is added. If DISPLAYVALUES is set,
`sysparm_display_value' is set.  If REFLINKS is set,
`sysparm_exclude_reference_link' is *not* set."
  (let ((params nil))
    (when fields (push
                  (list 'sysparm_fields (string-join fields ","))
                  params))
    (when displayvalues (push
                         '(sysparm_display_value true)
                         params))
    (when query (push 
                 (list 'sysparm_query query)
                 params))
    (unless reflinks (push
                      '(sysparm_exclude_reference_link true)
                      params))
    (sn--path-append-params path params)))

(defun sn--table-api-record-path (table sys-id &optional fields displayvalues reflinks)
  "Construct the ServiceNow Table API endpoint URL for a record in TABLE
with SYS-ID.  The endpoint will optionally contains common query
parameters.  If FIELDS are provided, the parameter `sysparm_fields' is
added. If DISPLAYVALUES is set, `sysparm_display_value' is set.  If
REFLINKS is set, `sysparm_exclude_reference_link' is *not* set."
  (let ((base-path (format sn--table-api-record-template table sys-id)))
    (sn--table-api-append-query-params
     base-path fields displayvalues reflinks)))

(defun sn--table-api-query-path (table query &optional fields displayvalues reflinks)
  "Construct the ServiceNow Table API endpoint URL for a query in TABLE
with encoded query QUERY.  If no FIELDS are provided, all fields are
retrieved."
  (let ((base-path (format sn--table-api-query-template table)))
    (sn--table-api-append-query-params
     base-path fields displayvalues reflinks query)))

;;;; Getting Records

;;;###autoload
(defun sn-get-record-json (table sys-id &optional fields displayvalues reflinks)
  "Retrieve a record from the ServiceNow table TABLE with the specified SYS-ID.
Will load all given FIELDS or all fields if FIELDS is nil.  If
DISPLAYVALUES is set, will return display values instead of values.  If
REFLINKS is set, references to other records will include links to those
records.  Data is returned as hash table."
  (let* ((path (sn--table-api-record-path table sys-id fields displayvalues reflinks))
         (response (sn-get-sync-json path)))
    (gethash "result" response)))

;;;###autoload
(defun sn-get-field-json (table sys-id field)
  "Retrieve a record from the ServiceNow table TABLE with the specified
SYS-ID.  Will return only a single given FIELD."
  (gethash field
             (sn-get-record-json table sys-id `(,field))))

;;;###autoload
(defun sn-get-records-json (table query &optional fields)
  "Retrieve records from the ServiceNow table TABLE that match the QUERY.
Will load all given FIELDS or all fields if FIELDS is nil."
  (let* ((path (sn--table-api-query-path table query fields))
         (response (sn-get-sync-json path)))
    (gethash "result" response)))

;;;; Creating Records

;;;###autoload
(defun sn-create-record (table fields &optional return-fields)
  "Create a new record in the ServiceNow table TABLE with the specified
FIELDS (alist of field names and values).  Will return the created
record as hashtable, or RETURN-FIELDS (list of field names) if
specified)."
  (let* ((path (sn--table-api-query-path table nil return-fields))
         (body (json-encode fields))
         (response (sn-post-sync-json path body))
         (result (gethash "result" response)))
    result))

;;;; Updating Records

;;;###autoload
(defun sn-update-record (table sys-id fields)
  ;; TODO We should switch to patch at some point to be more in line with REST
  ;; principles.  However, some older versions of plz do not support patch.
  "Update a record in the ServiceNow table TABLE with the specified SYS-ID
and FIELDS (alist of field names and values).  Will return the updated
record as hashtable."
  (let* ((path (sn--table-api-record-path table sys-id))
         (body (json-encode fields))
         (response (sn-put-sync-json path body))
         (result (gethash "result" response)))
  result))

;;;; Deleting Records

;;;###autoload
(defun sn-delete-record (table sys-id)
  "Deletes a record from the ServiceNow table TABLE with the specified
SYS-ID.  Will return `nil' if record could not be deleted."
  (sn-delete-sync-raw (sn--table-api-record-path table sys-id nil nil t)))

(provide 'servicenow)

;;;; Caching

(defcustom sn-record-cache-ttl 300
  "Time to live for record cache in seconds.  After this time, records will
be reloaded from the ServiceNow instance."
  :type 'integer
  :group 'servicenow)

(defvar sn--record-cache (make-hash-table :test 'equal)
  "Cache for records retrieved from ServiceNow.  The key is a composit
string identifying the table, query and retrieved fields, and the value
is a cons cell containing the retrieval time and the records themselves.")

(defun snsync--make-hash-key (table &optional query fields)
  "Create a hash key from TABLE, QUERY and FIELDS."
  (let ((fields-str (mapconcat 'identity (sort fields) ",")))
    (format "%s|%s|%s" table query fields-str)))

;;;###autoload
(defun sn-get-records-json-cached (table query &optional fields)
  "Retrieve records from the ServiceNow, caching the results for a period
of time."
  ;; TODO To implement: Beyond that time, will only retrieve records that were changed since the last retrieval.
  (let* ((cache-key (snsync--make-hash-key table query fields))
        (cached-records (gethash cache-key sn--record-cache)))
    (if (and cached-records
             (time-less-p (time-subtract (current-time) (car cached-records))
                          (seconds-to-time sn-record-cache-ttl)))
        (cdr cached-records)
      ;; If cache is empty or expired, retrieve records from ServiceNow.
      (let ((records (sn-get-records-json table query fields)))
        (puthash cache-key (cons (current-time) records) sn--record-cache)
        records))))


;;;; Helper Functions

(defun sn-get-result-field (data field)
  "Get the value of FIELD from the DATA hash table.  If FIELD is a string,
it will be used as a key to retrieve the value.  If FIELD is a list of
strings, it will return the value of the first (non-empty) field that
exists in DATA.  If FIELD is a function, it will be called with DATA as
argument and the result will be returned.  If FIELD is not found, it
will return nil."
  (cond
   ((stringp field) (gethash field data))
   ((listp field)
    (cl-some (lambda (f) 
               (let ((value (gethash f data)))
                 (and (stringp value)
                      (not (string-empty-p value))
                      value)))
             field))
   ((functionp field) (funcall field data))
   (t (error "Invalid field type: %s" (type-of field)))))

;;; User Interface

(defun sn--complete-reference (table &optional query fields formatter valueparser prompt)
  "Complete a reference to a record in TABLE.  If QUERY is provided, it
will be used to filter the results.  FIELDS is a list of fields to use
for completion.  FORMATTER is a function that takes a record and returns
a string to display in the completion buffer.  If FORMATTER is not
provided, the default formatter will be used, which returns the record's
data.  VALUEPARSER is a function that takes the selected value and
returns a value (defaults to formatter or identity).  PROMPT is the
prompt to use for the completion buffer.

Note: The results are cached for a period of time, so that repeated
calls to this function will not result in multiple requests to the
ServiceNow instance.  The cache is invalidated after
`sn-record-cache-ttl' seconds."
  (let* ((fields (or fields '("sys_id")))
         (formatter (or formatter
                      (lambda (record)
                        (gethash "sys_id" record))))
         (valueparser (or valueparser formatter 'identity))
         (records (sn-get-records-json-cached table query fields))
         (prompt (or prompt (format "Select %s record: " table)))
         (formatted-records
          (mapcar formatter records))
         (selection (completing-read prompt formatted-records nil t))
         (selected-record
          (seq-find (lambda (record)
                      (string= (funcall formatter record) selection))
                    records))
         (value (funcall valueparser selected-record)))
    value))

(defun sn--open-in-browser (table sys-id)
  "Open the record in the browser.  TABLE is the name of the table, and
SYS-ID is the sys_id of the record."
  (let ((url (format "https://%s.service-now.com/%s.do?sys_id=%s"
                     sn-instance
                     table
                     sys-id)))
    (browse-url url)))
                                     
(provide 'servicenow)

;;; servicenow.el ends here
