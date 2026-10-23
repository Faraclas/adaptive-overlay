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

DESCRIPTION="Declarative diagramming language with native SVG, PNG, and PDF export"
HOMEPAGE="https://d2lang.com https://github.com/d2lang/d2"
# v0.9.0: d5a51743b6d5c00f1ec6f8340003f5d5a6ba4eda
SRC_URI="
	https://github.com/d2lang/d2/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/Faraclas/adaptive-overlay/releases/download/d2-deps-${PV}/${P}-go-deps.tar.xz
"

LICENSE="Apache-2.0 BSD BSD-2 EPL-2.0 ISC MIT MPL-2.0 OFL-1.1
	SunSoft Unicode-3.0 Unicode-DFS-2016"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+mcp test"
RESTRICT="!test? ( test )"

BDEPEND="
	>=dev-lang/go-1.27.0:=
	test? ( dev-vcs/git )
"
PDEPEND="mcp? ( >=media-gfx/d2-mcp-0.1.0 )"

src_compile() {
	ego build -mod=readonly -trimpath \
		-ldflags "-X github.com/d2lang/d2/lib/version.Version=v${PV}" \
		-o d2 .
}

src_test() {
	# The make target requires upstream's CI formatting helpers. These units
	# use bundled fixtures, unlike the socket-based and release/tooling suites.
	# util-go/diff treats any nonempty acceptance variable as permission to
	# replace golden files, even "0"; always compare against the shipped data.
	local -x CI=1 TESTDATA_ACCEPT= TA=

	ego test -mod=readonly -count=1 -timeout=5m \
		./d2ast ./d2parser ./d2format ./d2ir ./d2compiler \
		./d2graph ./d2oracle \
		./d2layouts/d2dagrelayout ./d2layouts/d2elklayout \
		./d2layouts/d2grid ./d2layouts/d2sequence \
		./lib/color ./lib/font ./lib/geo ./lib/shape ./lib/urlenc
}

src_install() {
	dobin d2
	doman ci/release/template/man/d2.1
	dodoc README.md

	docinto licenses
	dodoc "${FILESDIR}/${P}-bundled-notices.txt" \
		"${FILESDIR}/${P}-runtime-notices.txt" \
		"${FILESDIR}/${P}-module-sources.txt"
	docinto licenses/d2
	dodoc LICENSE.txt THIRD_PARTY_NOTICES.txt

	local notice relative
	for notice in \
		d2layouts/d2dagrelayout/NOTICE.txt \
		d2layouts/d2elklayout/NOTICE.txt \
		d2renderers/d2fonts/NOTICE.txt \
		d2renderers/d2fonts/NotoColorEmoji-OFL.txt \
		d2renderers/d2sketch/NOTICE.txt \
		d2renderers/d2svg/NOTICE.txt \
		lib/textmeasure/NOTICE.txt
	do
		docinto "licenses/d2/${notice%/*}"
		dodoc "${notice}"
	done

	# Read extracted sources, not proxy-cache archives; retain nested notices
	# such as mathjax-go's LICENSES/MIT-Luo-Studio.txt without name collisions.
	find "${GOMODCACHE}" -path "${GOMODCACHE}/cache" -prune -o \
		-type f \( -iname '*license*' -o -iname '*copying*' \
		-o -iname '*copyright*' -o -iname '*notice*' \
		-o -path '*/LICENSES/*' \) -print0 > "${T}/module-notices" || die
	while IFS= read -r -d '' notice; do
		relative=${notice#"${GOMODCACHE}/"}
		docinto "licenses/go-mod/${relative%/*}"
		dodoc "${notice}"
	done < "${T}/module-notices"

	docompress -x "/usr/share/doc/${PF}/licenses"
}
