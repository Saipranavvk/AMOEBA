# gen_init_cpio spec, consumed directly by the kernel's CONFIG_INITRAMFS_SOURCE.
#
# Using the spec-file form rather than a directory is deliberate: it lets the
# kernel build create /dev/console -- a character device node -- without the
# image build ever needing root.  Without that node the kernel cannot open a
# console for init and the boot string never appears.
#
# @INIT@ is substituted by testcode/linux/Makefile with the built init binary.

dir  /dev 0755 0 0
nod  /dev/console 0600 0 0 c 5 1
file /init @INIT@ 0755 0 0
