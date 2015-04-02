# We need lua enabled, the rest of the settings match the base configuration
PACKAGECONFIG_virtclass-native = "db bzip2 zlib beecrypt openssl libelf python lua"

FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://rpm2cpio_segfault.patch \
           "

# We have to play games to be sure we use our elf.h for native builds.
#
EXTRA_OECONF_append_class-native = " CPPFLAGS='${CPPFLAGS} -I${S}' CFLAGS='${CFLAGS} -I${S}'"

# Put elf.h into source for a native compile.
#
SRC_URI_append_class-native = " file://elf_h.patch"

# rpm2cpio, when pulled from an sstate cache, might not work,
# so we use this handy script version, instead.
#
do_install_append_virtclass-native() {
        cp ${S}/scripts/rpm2cpio ${D}/${bindir}
}
