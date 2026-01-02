# VST3 SDK Submodules in Yabridge

## The Problem

The yabridge build system uses Meson wraps to manage its dependencies. One of these dependencies is the VST3 SDK, which uses git submodules. When downloading source archives from GitHub (using `https://github.com/user/repo/archive/refs/tags/VERSION.tar.gz`), git submodules are **not included** in the tarball.

This creates a problem for Gentoo ebuilds, which:
1. Must download all sources upfront (no network access during build)
2. Use `--wrap-mode nodownload` to prevent Meson from downloading dependencies

## The Solution

This ebuild manually fetches the VST3 SDK submodules during the `src_prepare()` phase using git commands. While this requires network access during the prepare phase (which is technically allowed but not ideal), it's the most practical solution given the constraints.

### How It Works

1. The main VST3 SDK tarball is downloaded as part of SRC_URI (without submodules)
2. During `src_prepare()`, git is used to initialize the directory and fetch the specific submodule commits
3. The submodule commits are pinned to specific hashes that match yabridge's requirements

### The Code

```bash
cd "${WORKDIR}/vst3sdk-3.7.7_build_19-patched" || die
git init || die
git submodule add --depth 1 https://github.com/steinbergmedia/vst3_base.git base || die
git submodule add --depth 1 https://github.com/steinbergmedia/vst3_pluginterfaces.git pluginterfaces || die
git submodule add --depth 1 https://github.com/steinbergmedia/vst3_public_sdk.git public.sdk || die
(cd base && git checkout ea2bac9a109cce69ced21833fa6ff873dd6e368a) || die
(cd pluginterfaces && git checkout bc5ff0f87aaa3cd28c114810f4f03c384421ad2c) || die
(cd public.sdk && git checkout bbb0538535b171e805c8a8b612c2cd8a5f95738b) || die
```

## Maintenance

When updating yabridge to a new version:

1. Check if `subprojects/vst3.wrap` has changed
2. If the `revision` (git tag) has changed, update the SRC_URI
3. If the wrap file references different submodule commits, update the git checkout commands

### Finding Submodule Commits

To determine which commits should be used for the submodules:

```bash
# Clone with submodules
git clone --depth=1 --recurse-submodules --branch v3.7.7_build_19-patched \
    https://github.com/robbert-vdh/vst3sdk.git vst3-temp

# Check submodule commits
cd vst3-temp
git submodule status
```

Output will show:
```
 ea2bac9a109cce69ced21833fa6ff873dd6e368a base (heads/master)
 bc5ff0f87aaa3cd28c114810f4f03c384421ad2c pluginterfaces (heads/master)
 bbb0538535b171e805c8a8b612c2cd8a5f95738b public.sdk (heads/master)
```

These are the commit hashes to use in the ebuild.

### Using the Helper Script

A helper script is provided to check all dependencies:

```bash
./check-dependencies.sh yabridge-X.Y.Z.tar.gz
```

This will:
- Extract and parse all `.wrap` files
- Display URLs and revision hashes
- Warn about dependencies that use submodules
- Provide instructions for updating the ebuild

## Alternative Solutions Considered

### 1. Pre-built Tarball with Submodules
**Rejected**: Would require hosting the tarball ourselves or uploading to a service. Creates a maintenance burden and trust issue.

### 2. System VST3 SDK Package
**Rejected**: Yabridge uses a patched version of the VST3 SDK specifically prepared for Wine/winelib compilation. The system package wouldn't have these patches.

### 3. Vendoring Submodules in the Ebuild
**Rejected**: Would require adding three additional SRC_URI entries and manually copying files into place. The current solution is cleaner.

### 4. Using Meson's wrap-mode=nofallback
**Rejected**: Still requires network access during configure phase and doesn't give us control over which commits are used.

## Trade-offs

**Pros:**
- Simple and maintainable
- Uses exact commits specified by yabridge upstream
- Clear error messages if something goes wrong

**Cons:**
- Requires network access during src_prepare()
- Not strictly following Gentoo's "no network during build" principle
- Adds git as a build dependency

## Future Improvements

If Gentoo's infrastructure or Meson's capabilities change, consider:
- Pre-downloading submodules in a SRC_URI if hosting becomes available
- Using a live ebuild approach if appropriate
- Upstream changes to eliminate the need for git submodules

## See Also

- Yabridge's build instructions: https://github.com/robbert-vdh/yabridge#building
- Meson subprojects documentation: https://mesonbuild.com/Subprojects.html
- VST3 SDK repository: https://github.com/steinbergmedia/vst3sdk