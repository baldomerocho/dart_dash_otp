# Publishing

Maintainer guide for cutting and publishing a new release of `dart_dash_otp`
to [pub.dev](https://pub.dev/packages/dart_dash_otp). For an overview of all
documentation pages, see [index.md](index.md).

## Versioning policy

The package follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`):

- **MAJOR** — incompatible public API changes (e.g. the 1.x to 2.0.0 rewrite).
- **MINOR** — new, backward-compatible functionality.
- **PATCH** — backward-compatible bug fixes.

Pre-release builds use suffixes such as `-rc.1` or `-beta.1`
(for example `2.1.0-rc.1`). The publish workflow tag pattern accepts these.

The `version:` field in `pubspec.yaml` is the single source of truth and must
match the git tag (without the leading `v`).

## Release checklist

1. Update [`../CHANGELOG.md`](../CHANGELOG.md) with a new section for the
   release. Describe additions, changes, fixes, and any breaking changes.
2. Bump the `version:` field in `pubspec.yaml` to the new `X.Y.Z`.
3. Run the local checks and a dry run:

   ```bash
   fvm dart pub get
   fvm dart format --output=none --set-exit-if-changed .
   fvm dart analyze --fatal-infos
   fvm dart test
   ./tool/coverage.sh
   fvm dart pub publish --dry-run
   ```

4. Open a pull request, get it reviewed, and merge it to `master`.
5. From an up-to-date `master`, create and push the tag:

   ```bash
   git checkout master
   git pull
   git tag vX.Y.Z      # e.g. v2.0.0 — must match pubspec version
   git push origin vX.Y.Z
   ```

6. Pushing the tag triggers the
   [`Publish to pub.dev`](../.github/workflows/publish.yaml) workflow, which
   publishes the package automatically via OIDC. No tokens are stored in the
   repository.

## One-time setup: automated publishing with OIDC

Automated publishing must be enabled once for the package before the first
tag-triggered release works. This uses OpenID Connect (OIDC) so that pub.dev
trusts releases coming from this repository's GitHub Actions without any
long-lived credentials.

1. Sign in to pub.dev as a package uploader.
2. Go to the package Admin tab:
   <https://pub.dev/packages/dart_dash_otp/admin>
3. In the **Automated publishing** section, enable
   **Publishing from GitHub Actions**.
4. Set the repository to:

   ```
   baldomerocho/dart_dash_otp
   ```

5. Set the **Tag pattern** to:

   ```
   v{{version}}
   ```

   This means a tag like `v2.0.0` is expected to publish version `2.0.0`.
6. (Optional) Restrict publishing to a protected
   [GitHub environment](https://docs.github.com/actions/deployment/targeting-different-environments)
   named `pub.dev`. If you do this, create that environment in the repository
   settings and add required reviewers so a human must approve each publish
   run. When using an environment, add `environment: pub.dev` to the publish
   job and configure the same name in the pub.dev Admin tab.

Reference: <https://dart.dev/tools/pub/automated-publishing>

## Verifying a publish run

1. Open the **Actions** tab on GitHub and find the `Publish to pub.dev` run
   triggered by your tag.
2. Confirm the run succeeded. If a `pub.dev` environment with reviewers is
   configured, approve the deployment when prompted.
3. Confirm the new version appears on
   <https://pub.dev/packages/dart_dash_otp/versions>.

## Manual fallback

If automated publishing is unavailable, an authorized uploader can publish
from a clean checkout of the tagged commit:

```bash
fvm dart pub get
fvm dart pub publish --dry-run   # sanity check first
fvm dart pub publish
```

This requires interactive pub.dev authentication on the machine running the
command.

## CI overview

Every push and pull request to `master` runs
[`.github/workflows/ci.yaml`](../.github/workflows/ci.yaml) (workflow name
**CI**), which gates merges with the following jobs:

- **verify** — runs on Dart `3.6` and `stable`; checks `dart pub get`,
  `dart format` (no changes allowed), `dart analyze --fatal-infos`, and
  `dart test`.
- **coverage** — runs the suite with coverage on `stable`, generates an LCOV
  report, and fails if total line coverage drops below 90%. The report is
  uploaded as a build artifact.
- **publish-dry-run** — runs `dart pub publish --dry-run` to catch packaging
  problems before a real release.

> The `3.6` floor exists because the `lints` dev dependency requires
> Dart >= 3.6. Consumers of the package are still supported on Dart >= 3.0.0,
> as declared in `pubspec.yaml`.
