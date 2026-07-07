# Homebrew Tools

[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/10697/badge)](https://bestpractices.coreinfrastructure.org/projects/10697)
[![License](https://img.shields.io/badge/license-apache2-blue.svg)](LICENSE)

## How to install Solo using Brew
Install the latest version of Solo using Homebrew:
```
brew install hiero-ledger/tools/solo
```

Install a specific version of Solo using Homebrew:
```
brew install hiero-ledger/tools/solo@<version>
```

## Try the local checkout of this tap
Use the helper script in this repo to copy the current local `Formula/solo.rb` into a custom tap
and reinstall from source:

```
./scripts/reinstall-local-solo.sh [tap-name]
```

Example:

```
./scripts/reinstall-local-solo.sh "$(whoami)/tools"
```

The script derives the repository path from its own location, taps the local checkout with
`brew tap --custom-remote`, defaults the tap name to `<current-user>/tools`, refreshes the tapped
`solo.rb`, and runs a source reinstall.

## Contribute

- To contribute, please refer to the **[Hiero-Ledger's contribution guidelines](https://github.com/hiero-ledger/.github/blob/main/CONTRIBUTING.md)**

<!---
Help and Community includes discord channels, meeting information or references where new members can ask questions. 
Links to issues and discussions.
-->

## About Users and Maintainers

- Users and Maintainers guidelines are located in **[Hiero-Ledger's CONTRIBUTING.md file](https://github.com/hiero-ledger/.github/blob/main/CONTRIBUTING.md#about-users-and-maintainers)** under the "About-Users-and-Maintainers" section.

<!---
Recognition to past contributors or mentions of collaborating companies.
-->

## License

- Hiero's source code is available under the **Apache License, Version 2.0 (Apache-2.0)**
