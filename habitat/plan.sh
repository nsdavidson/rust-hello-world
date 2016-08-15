pkg_origin=nsdavidson
pkg_name=rust-hello-world
pkg_version=0.1.3
pkg_maintainer="Nolan Davidson <ndavidson@chef.io>"
pkg_license=()
pkg_source=things
pkg_shasum=stuff
pkg_deps=(core/coreutils core/gcc-libs core/glibc)
pkg_build_deps=(core/openssl core/rust core/cacerts core/gcc core/gcc-libs core/glibc)
pkg_expose=(8080)
pkg_svc_run='rust-hello-world'

do_download() {
  return 0
}

do_unpack() {
  cp -a ../ ${HAB_CACHE_SRC_PATH}
}

do_verify() {
  return 0
}
do_build() {
  env SSL_CERT_FILE=$(pkg_path_for cacerts)/ssl/cert.pem cargo build
}

do_install() {
  cp ../target/debug/rust-hello-world ${pkg_prefix}
}
