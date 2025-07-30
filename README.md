
# Table of Contents

1.  [Quickstart](#org2c8ba82)
    1.  [OAuth Setup](#org7b6cf2b)
2.  [Planned Improvements](#orgf910049)
    1.  [APIs to add](#orgf708a36)
3.  [Limitations](#orge2d82d3)

This package is meant to serve as the plumbing for other packages that want to interact with ServiceNow.  It handles authentication with the instance via OAuth, making REST calls (for which it relies on the plz library), and provides a set of convenience functions to use the Table API.


<a id="org2c8ba82"></a>

# Quickstart

The simplest way to get started is with `use-package`.  Add the following to your Emacs configuration:

    (use-package servicenow
      :straight (:host github :repo "julian-hoch/servicenow.el"
      :custom
      (sn-instance "dev12345")
      (sn-oauth-client-id "your-client-id")
      (sn-oauth-client-secret "your-client-secret")))


<a id="org7b6cf2b"></a>

## OAuth Setup

To set up OAuth in your instance, go to "Application Registry", and create new record for OAuth Client.
Set some client secret and as redirect URL set <https://localhost:8182>.

Then, copy the Client ID and paste into your config.  After you installed the package, you can log in via the Emacs command `sn-login`.  Afterwards, test the connection with `sn-test`.


<a id="orgf910049"></a>

# Planned Improvements

-   Right now the package uses `secrets.el` to store the tokens.  I am looking for a more generic option without external dependencies.
-   True asynchronous processing.  Right now, everything is done synchronously.
-   Better support for Application File tables.


<a id="orgf708a36"></a>

## APIs to add

-   **Aggregate API:** Allows you to compute aggregate statistics about existing table and column data
-   **Attachment API:** Allows you to upload, download, and remove attachments and to retrieve attachment metadata
    
    Code Search:
    <https://dev209562.service-now.com/api/sn_codesearch/code_search/search?term=abc123&limit=500&search_all_scopes=true&search_group=sn_devstudio.Studio> Search Group&table=sys<sub>ui</sub><sub>policy</sub>
    
    Devstudio / VCS


<a id="orge2d82d3"></a>

# Limitations

-   Currently only supports one instance at a time, since I have not found a way to store multiple tokens using `secrets.el`

