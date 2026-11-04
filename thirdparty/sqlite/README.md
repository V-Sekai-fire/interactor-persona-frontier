# SQLite amalgamation 3.54.1

Vendored from https://sqlite.org/2026/sqlite-amalgamation-3540100.zip (public domain), compiled into the shim's static library so the node links no system SQLite: Lean's bundled lld pairs an older `Scrt1.o` with whatever libc a `-L/usr/lib64` drags in, and AlmaLinux 10's glibc no longer carries `__libc_csu_init`. The same move the store made in its rung 10.
