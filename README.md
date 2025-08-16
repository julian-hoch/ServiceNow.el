- [Quickstart](#org907f342)
    - [Planned Improvements](#orga60cbbd)
    - [Limitations](#org23701f0)

This package is meant to serve as the plumbing for other packages that want to interact with ServiceNow. It handles authentication with the instance via OAuth, making REST calls (for which it relies on the plz library), and provides a set of convenience functions to use the Table API.


<a id="org907f342"></a>

# Quickstart

The simplest way to get started is with `use-package`. Add the following to your Emacs configuration:

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

To set up OAuth in your instance, go to "Application Registry", and create a new client record ("Create an OAuth API endpoint for external clients").

Set some client secret (or leave empty to get a generated one), and as redirect URL, set <http://localhost:38182> (the port can be customized, if needed).

Then, copy the Client ID and paste into your config. After you installed the package, you can log in via the Emacs command `sn-oauth-login`. Afterwards, test the connection with `sn-test`.

**NOTE**: On Linux, you can set the variable `sn-oauth-token-store` probably to `'secrets`, which is more secure (it uses the `secrets.el` package). On Windows, you will have to fall back to using `'custom`, which will store the token as part of your emacs customization.


<a id="orga60cbbd"></a>

# Planned Improvements

-   True asynchronous processing. Right now, everything is done synchronously.
-   Better support for Application File tables.


## APIs to add

-   **Aggregate API:** Allows you to compute aggregate statistics about existing table and column data
-   **Attachment API:** Allows you to upload, download, and remove attachments and to retrieve attachment metadata
-   **Code Search:** Allows you to search for code in the ServiceNow instance


<a id="org23701f0"></a>

# Limitations

-   Currently only supports one instance at a time, since I have not found a way to store multiple tokens using `secrets.el`
