# Build vendored libzip source into a static libzip.a for iOS.
# CMake normally generates config.h + zipconf.h; we provide them by hand.
# Deflate-only build (skip bzip2/xz/zstd/crypto backends) — IPA files only use deflate.

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
    export TARGET = iphone:clang:latest:15.0
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
    export TARGET = iphone:clang:latest:15.0
else
    export TARGET = iphone:clang:latest:13.0
endif
export ARCHS = arm64 arm64e
export DEBUG = 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = zip

EXCLUDED := zip_algorithm_bzip2.c zip_algorithm_xz.c zip_algorithm_zstd.c \
            zip_crypto_commoncrypto.c zip_crypto_gnutls.c zip_crypto_openssl.c zip_crypto_win.c

zip_FILES = $(filter-out $(EXCLUDED), $(wildcard *.c))
zip_CFLAGS = -DHAVE_CONFIG_H -I. -fvisibility=hidden -Wno-everything -Wno-error
zip_CCFLAGS = -DHAVE_CONFIG_H -I. -fvisibility=hidden -Wno-everything -Wno-error
zip_LIBRARIES = z

include $(THEOS_MAKE_PATH)/library.mk
