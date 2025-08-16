# Table of Contents

1.  [Quickstart](#orgf51a91a)
2.  [Planned Improvements](#org4d1d605)
3.  [Limitations](#org11f7f13)

This package is meant to serve as the plumbing for other packages that want to interact with ServiceNow. It handles authentication with the instance via OAuth, making REST calls (for which it relies on the plz library), and provides a set of convenience functions to use the Table API.


<a id="orgf51a91a"></a>

# Quickstart

The simplest way to get started is with `use-package`. If you use `straight` like me, add the following to your Emacs configuration (for other package managers, I am sure you will know how to adapt this):

```emacs-lisp
(use-package servicenow
  :straight (:host github :repo "julian-hoch/servicenow.el"
  :custom
  (sn-instance "dev12345")
  (sn-oauth-client-id "your-client-id")
  (sn-oauth-client-secret "your-client-secret")
  (sn-oauth-token-store 'custom)))
```


## OAuth Setup

Just one step is necessary in your Instance to be able to connect to it via OAuth. Simply go to the *Application Registry*, and create a new client record. There, select “Create an OAuth API endpoint for external clients”.

Set some client secret (or leave empty to generated one), and set <http://localhost:38182> as redirect URL. The port can be customized, if needed.

Copy the Client ID and paste into your Emacs config. Now, you can do the initial log in via the Emacs command `sn-oauth-login`. This will store the OAuth token locally into your Emacs configuration (or secret manager, see below). This only needs to be done whenever the refresh token expires. Set this suitably high, e.g. to 30 days, so you do not have to log in too often.

Finally, test the connection with `sn-test`.


## Secret Manager

On Linux, you can set the variable `sn-oauth-token-store` to `'secrets`, which is more secure (it uses the `secrets.el` package). On Windows, you will have to fall back to using `'custom`, which will store the token as part of your emacs customization.


<a id="org4d1d605"></a>

# Planned Improvements

Thing I want to improve in the future:

-   True asynchronous processing. Right now, everything is done synchronously.
-   Better support for Application File tables. This could be useful for example for a potential VC backend I would like to implement.
-   **Support for Aggregate API:** This could be use to quickly compute aggregate statistics about existing table and column data
-   **Support for Attachment API:** Allows you to upload, download, and remove attachments and to retrieve attachment metadata
-   **Support for Code Search:** Allows you to search for code in the ServiceNow instance


<a id="org11f7f13"></a>

# Limitations

ServiceNow.el currently only supports one instance at a time, since I have not found a way to store multiple tokens using `secrets.el`. I guess one could work around that with dynamic let bindings, but I have not yet had the chance to test this approach.
