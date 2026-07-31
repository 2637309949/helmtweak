#ifndef HAD_CONFIG_H
#define HAD_CONFIG_H

#ifndef _HAD_ZIPCONF_H
#include "zipconf.h"
#endif

/* iOS rootless / roothide config — minimal read-only build, deflate only, no crypto */

#define ENABLE_FDOPEN
#define HAVE_FILENO
#define HAVE_OPEN
#define HAVE_CLOSE
#define HAVE_READ
#define HAVE_WRITE
#define HAVE_LSEEK
#define HAVE_FSTAT
#define HAVE_STAT
#define HAVE_FTELLO
#define HAVE_FSEEKO
#define HAVE_FTELL
#define HAVE_FSEEK
#define HAVE_FILENO
#define HAVE_DUP
#define HAVE_STRDUP
#define HAVE_SNPRINTF
#define HAVE_VSNPRINTF
#define HAVE_UNISTD_H
#define HAVE_INTTYPES_H
#define HAVE_STDINT_H
#define HAVE_FCNTL_H
#define HAVE_SYS_TYPES_H
#define HAVE_SYS_STAT_H
#define HAVE_LIMITS_H
#define HAVE_TIME_H
#define HAVE_STRINGS_H
#define HAVE_STRING_H
#define HAVE_LOCALE_H
#define HAVE_SETLOCALE
#define HAVE_LOCALTIME_R
#define HAVE_GMTIME_R
#define HAVE_MKSTEMP
#define HAVE_MKTEMP
#define HAVE_STDBOOL_H
#define HAVE_RANDOM
#define HAVE_ARC4RANDOM
#define HAVE_SNPRINTF
#define HAVE_STRCASECMP
#define HAVE_STRICMP
#define HAVE_PROGNAME
#define HAVE___PROGNAME

#define HAVE_ZLIB 1
#define HAVE_ZLIB_COMPAT 1

/* explicitly NOT defined: HAVE_CRYPTO, HAVE_COMMONCRYPTO, HAVE_OPENSSL,
   HAVE_GNUTLS, HAVE_MBEDTLS, HAVE_BZIP2, HAVE_LIBLZMA, HAVE_ZSTD */

#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_LONG_LONG 8
#define SIZEOF_OFF_T 8
#define SIZEOF_SIZE_T 8
#define SIZEOF_SSIZE_T 8
#define SIZEOF_VOIDP 8

#define HAVE_PROTOTYPES
#define STDC_HEADERS

#endif /* HAD_CONFIG_H */
