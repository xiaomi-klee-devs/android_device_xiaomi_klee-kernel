# OSS Kernel for POCO X8 Pro / REDMI Turbo 5 (klee)

```
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
```

## Layout
    images/    Image.lz4, mt6899.dtb, dtbo.img
    headers/   kernel-uapi-headers.tar.gz
    modules/   *.ko + modules.load.*

## Generate
    ./extract-files.sh /path/to/kernel
