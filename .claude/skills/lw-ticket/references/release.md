# Release - questions and body

Matches the GitHub form `release.yml` (template `release`, type label `release`, title prefix `[Release] `).
For maintainers tracking a release. If the user is not a maintainer, suggest they ask one.

| # | Heading (field id) | Ask | Notes |
|---|---|---|---|
| 1 | Version (`version`) | "Which version is this release? (e.g. 1.2.0+16)" | Must be the version in `pubspec.yaml` after the bump PR; format `x.y.z+build`. Title: `[Release] 1.2.0+16`. |

The checklist is fixed; do not ask about it. Boxes start unticked - humans tick them as each step is done.
No priority suggestion and no area label other than `area:release`.

## Body template (headings exact)

```markdown
### Version

1.2.0+16

### Release checklist

- [ ] CI green on develop (analyze and tests within budget)
- [ ] Version bumped in pubspec.yaml
- [ ] Training build verified on a device
- [ ] Release notes written
- [ ] Prod APK built from the tagged commit and checksum recorded
```
