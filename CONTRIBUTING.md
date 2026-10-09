# Contributing

SAVISUL is primarily maintained by its creator, but contributions are welcome.

Good first contributions:

- Bug fixes
- Documentation
- Translations
- Tests
- Small isolated features

Please open an issue before working on major architectural changes.

## How a change gets in

Only the maintainer can change this repository. Everyone else proposes:

- **A bug or an idea:** open an [issue](https://github.com/mouldloft/SAVISUL/issues/new/choose) with one of the templates.
- **A fix:** fork the repository, make the change on a branch, and open a pull request. The maintainer reviews every pull request and decides whether it is merged.

## Local check

The build uses the Command Line Tools for Xcode 16.2 (Swift 6.0.3), the same toolchain as CI.

```sh
zsh ./build.sh --no-install
zsh ./scripts/test.sh
node --test Extension/test/urlclean.test.mjs
```

Do not commit `.signing/`, `.build/`, `dist/` or `node_modules/`.
