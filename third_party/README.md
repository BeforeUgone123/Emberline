# Third-Party Sources

Run `bash tools/fetch-third-party.sh` from the project root to fetch:

- `mbedtls` tag `mbedtls-3.6.6`
- `libssh2` tag `libssh2-1.11.1`

The fetched source directories are ignored by git to avoid committing large
vendor trees into this preview scaffold.

The fetch script clones into a user cache first and exports plain source trees
without `.git` directories. This is intentional: the `/mnt/linux_share` preview
filesystem does not reliably support Git metadata, chmod, or mtime restoration.
