# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Match upstream's native release builds, without downloading a toolchain.
export CGO_ENABLED=0
export GOPROXY=off
export GOTOOLCHAIN=local
export GOENV=off
export GOWORK=off

inherit go-module

DESCRIPTION="Detect and prevent hardcoded secrets in git repos, files, and stdin"
HOMEPAGE="https://gitleaks.io https://github.com/gitleaks/gitleaks"
# v8.30.1: 83d9cd684c87d95d656c1458ef04895a7f1cbd8e
SRC_URI="
	https://github.com/gitleaks/gitleaks/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/Faraclas/adaptive-overlay/releases/download/gitleaks-deps-${PV}/${P}-go-deps.tar.xz
"

LICENSE="Apache-2.0 BSD BSD-2 CC-BY-4.0 CC0-1.0 ISC MIT MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

RDEPEND="
	dev-vcs/git
"
BDEPEND="
	>=dev-lang/go-1.24.11:=
	test? ( dev-vcs/git )
"

src_compile() {
	ego build -mod=readonly -trimpath \
		-ldflags "-X=github.com/zricethezav/gitleaks/v8/version.Version=${PV}" \
		-o gitleaks .
}

src_test() {
	ego test -mod=readonly -count=1 ./...
}

src_install() {
	dobin gitleaks
	dodoc README.md

	docinto licenses/gitleaks
	dodoc LICENSE

	# Read extracted sources, not proxy-cache archives; retain nested notices
	# without name collisions.
	find "${GOMODCACHE}" -path "${GOMODCACHE}/cache" -prune -o \
		-type f \( -iname '*license*' -o -iname '*copying*' \
		-o -iname '*copyright*' -o -iname '*notice*' \
		-o -path '*/LICENSES/*' \) -print0 > "${T}/module-notices" || die
	local notice relative
	while IFS= read -r -d '' notice; do
		relative=${notice#"${GOMODCACHE}/"}
		docinto "licenses/go-mod/${relative%/*}"
		dodoc "${notice}"
	done < "${T}/module-notices"

	docompress -x "/usr/share/doc/${PF}/licenses"
}
