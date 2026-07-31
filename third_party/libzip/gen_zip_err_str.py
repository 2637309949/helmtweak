#!/usr/bin/env python3
"""Generate third_party/libzip/zip_err_str.c from zip.h + zipint.h.

Mirrors cmake/GenerateZipErrorStrings.cmake from upstream libzip.
Run once after vendoring new libzip source: `python3 gen_zip_err_str.py`.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "zip.h"), encoding="utf-8") as f:
    zip_h = f.read()
with open(os.path.join(HERE, "zipint.h"), encoding="utf-8") as f:
    zipint_h = f.read()

# `#define ZIP_ER_OK 0               /* N No error */`
err_re = re.compile(r"^#define\s+ZIP_ER_([A-Z0-9_]+)\s+(\d+)\s+/\*\s*([LNSZ])\s+(.*?)\s*\*/", re.M)
# `#define ZIP_ER_DETAIL_CDIR_OVERLAPS_EOCD 1   /* G central directory overlaps EOCD, or there is space between them */`
detail_re = re.compile(r"^#define\s+ZIP_ER_DETAIL_([A-Z0-9_]+)\s+(\d+)\s+/\*\s*([EG])\s+(.*?)\s*\*/", re.M)

out = []
out.append("/*\n  This file was generated automatically by gen_zip_err_str.py\n  from zip.h and zipint.h; make changes there.\n*/\n\n")
out.append('#include "zipint.h"\n\n')
out.append("#define L ZIP_ET_LIBZIP\n#define N ZIP_ET_NONE\n#define S ZIP_ET_SYS\n#define Z ZIP_ET_ZLIB\n\n")
out.append("#define E ZIP_DETAIL_ET_ENTRY\n#define G ZIP_DETAIL_ET_GLOBAL\n\n")
out.append("const struct _zip_err_info _zip_err_str[] = {\n")
for m in err_re.finditer(zip_h):
    name, num, t, desc = m.group(1), m.group(2), m.group(3), m.group(4)
    desc = desc.replace('"', '\\"')
    out.append(f'    {{ {t}, "{desc}" }},\n')
out.append("};\n\n")
out.append("const int _zip_err_str_count = sizeof(_zip_err_str)/sizeof(_zip_err_str[0]);\n\n")
out.append("const struct _zip_err_info _zip_err_details[] = {\n")
for m in detail_re.finditer(zipint_h):
    name, num, t, desc = m.group(1), m.group(2), m.group(3), m.group(4)
    desc = desc.replace('"', '\\"')
    out.append(f'    {{ {t}, "{desc}" }},\n')
out.append("};\n\n")
out.append("const int _zip_err_details_count = sizeof(_zip_err_details)/sizeof(_zip_err_details[0]);\n")

with open(os.path.join(HERE, "zip_err_str.c"), "w", encoding="utf-8") as f:
    f.write("".join(out))
print(f"Generated zip_err_str.c ({len(err_re.findall(zip_h))} errors, {len(detail_re.findall(zipint_h))} details)")
