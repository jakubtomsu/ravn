# Contributors guidelines

It is recommended to use [Discord](https://discord.com/invite/wn5jMMMYe4) for discussing new potential features or bug fixes, or other communication with the developers.

## Reporting Bugs

If you've discovered a bug, please open a new Github Issue.
Please make sure you've tested it on the latest version or a stable release.

Please add the following information to the bug report if possible:
- Setup you're running on (`odin report` output)
- A small code/asset sample to reproduce the bug
- `platform` and `GPU` backends, if you aren't using the default config

## Contributing Pull Requests

Contributions are very welcome!
Please submit a pull request from a branch with the changes from your fork.
Make sure to document the code in case it's doing something non-obvious.
The PR will be reviewed when possible and merged if it meets the contributing standards.

For small stupid things like typos, prefer posting it on Discord over a PR.

If you implement a large feature, consider the **maintenance cost**.

Before submitting the PR, please run `check_all.cmd` script (Windows only).

### Bug Fixes

Bug fixes are the most preferred type of contributions. Please make sure the "fix" doesn't accidentally break other features, especially on other platforms.

### New Features

It is **strongly recommended to discuss new features on Discord**. If a feature doesn't align with the project direction, it might be rejected.

Small additions or tweaks are fine, but also may be rejected if it's something too specific, not useful for most users, that would just bloat the project.

### Documentation

You can contribute docs (in markdown form) or code examples.
> This isn't something beginners should do, since it requires a certain level of insight into both the Odin language and the engine internals.

### Style

Please try to follow the style of the rest of the codebase.
Use the default Odin [naming conventions](https://github.com/odin-lang/Odin/wiki/Naming-Convention).

Don't import needles dependencies if possible.

Keep it simple, stupid.
