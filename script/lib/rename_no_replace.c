#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s SOURCE DESTINATION\n", argv[0]);
        return 2;
    }

    if (renameatx_np(AT_FDCWD, argv[1], AT_FDCWD, argv[2], RENAME_EXCL) != 0) {
        fprintf(stderr, "exclusive rename rejected %s -> %s: %s\n",
                argv[1], argv[2], strerror(errno));
        return 1;
    }
    return 0;
}
