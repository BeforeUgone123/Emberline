# Third-Party Sources

Run `bash tools/fetch-third-party.sh` from the project root to fetch:

- `mbedtls` tag `mbedtls-3.6.6`
- `libssh2` tag `libssh2-1.11.1`

`libssh2-1.11.1` is retained only to reproduce the current development build.
It is a release blocker documented in
[`docs/code-review-2026-07-10.md`](../docs/code-review-2026-07-10.md): do not
ship it. Release must compile SSH/SFTP out or pin a verified patched revision,
then apply one shared host-key verifier to both SSH and SFTP.
Until then, use the fetched code only with isolated disposable test endpoints
and no valuable credentials.

The fetched source directories are ignored by git to avoid committing large
vendor trees into this preview scaffold.

The fetch script clones into a user cache first and exports plain source trees
without `.git` directories. This is intentional: the `/mnt/linux_share` preview
filesystem does not reliably support Git metadata, chmod, or mtime restoration.
