/* Regression checks for the read-only fuxi sensor firmware view. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hexagonfs.h"

struct hexagonfs_dirent *construct_root_dir(const char *prefix, const char *dsp);

static void expect_read(struct hexagonfs_fd **fds, int root,
                        const char *path, const char *expected)
{
    char buffer[128] = {0};
    int fd = hexagonfs_openat(fds, root, root, path);
    ssize_t n;

    if (fd < 0) {
        fprintf(stderr, "Cannot open virtual path: %s (%d)\n", path, fd);
        exit(1);
    }
    n = hexagonfs_read(fds, fd, sizeof(buffer) - 1, buffer);
    if (n != (ssize_t)strlen(expected) || strcmp(buffer, expected)) {
        fprintf(stderr, "Unexpected contents at %s\n", path);
        exit(1);
    }
    hexagonfs_close(fds, fd);
}

int main(int argc, char **argv)
{
    struct hexagonfs_fd *fds[HEXAGONFS_MAX_FD] = {0};
    struct hexagonfs_dirent *tree;
    const char *blocked[] = {"/etc/passwd", "/../../etc/passwd",
                             "/mnt/vendor/persist/modemst1"};
    int root;
    int fd;
    struct stat stats;
    size_t i;

    if (argc != 2)
        return 2;
    tree = construct_root_dir(argv[1], "adsp");
    root = hexagonfs_open_root(fds, tree);
    if (root < 0)
        return 1;
    expect_read(fds, root, "/vendor/etc/sensors/config/vendor.json", "vendor\n");
    expect_read(fds, root, "/odm/etc/sensors/config/device.json", "odm\n");
    expect_read(fds, root, "/sys/devices/soc0/soc_id", "519\n");
    expect_read(fds, root, "/persist/sensors/registry/registry/calibration", "cal\n");
    expect_read(fds, root, "/mnt/vendor/persist/sensors/registry/sns_reg_version", "version=14\n");
    expect_read(fds, root, "/mnt/vendor/persist/sensors/registry/registry/../sns_reg_version", "version=14\n");
    fd = hexagonfs_openat(fds, root, root, "/odm/etc/sensors/config/device.json");
    if (fd < 0 || hexagonfs_fstat(fds, fd, &stats) || stats.st_mtime != 1230768000) {
        fputs("Configuration mtime was not preserved\n", stderr);
        return 1;
    }
    hexagonfs_close(fds, fd);
    for (i = 0; i < sizeof(blocked) / sizeof(blocked[0]); i++) {
        if (hexagonfs_openat(fds, root, root, blocked[i]) >= 0) {
            fprintf(stderr, "Unexpected access outside sensor view: %s\n", blocked[i]);
            return 1;
        }
    }
    hexagonfs_close(fds, root);
    puts("PASS sensor paths, parent traversal, aliases and unmapped-path isolation");
    return 0;
}
