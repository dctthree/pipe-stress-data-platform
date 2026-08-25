# Security and data disclosure

Do not open a public issue containing raw experiment paths, sensor serial numbers, proprietary pipeline geometry, credentials or blind labels. Report sensitive problems to the repository owner through a private GitHub security advisory.

Before publishing a release:

- verify repository visibility;
- inspect staged files with `git status`;
- scan for absolute user paths and tokens;
- keep raw/full data in a private release or controlled object store;
- validate release SHA-256 and access permissions.

