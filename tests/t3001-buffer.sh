#!/bin/sh
# Test buffer overflow fix in libparted/fs/r/fat/fat.c

# Copyright (C) 2026 Free Software Foundation, Inc.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

. "${srcdir=.}/init.sh"; path_prepend_ ../parted .
require_root_
require_scsi_debug_module_
require_512_byte_sector_size_


FSTYPES=""

# Is mkfs.vfat available?
mkfs.vfat 2>&1 | grep '^Usage:' && FSTYPES="fat32 fat16"

[ -n "$FSTYPES" ] || skip_ "mkfs.vfat is not installed"


ss=$sector_size_

start=63s
default_end=546147s
    new_end=530144s

# create memory-backed device. Must be > 256MB+8MB
scsi_debug_setup_ dev_size_mb=267 > dev-name ||
  skip_ 'failed to create scsi_debug device'
dev=$(cat dev-name)

fail=0

parted -s $dev mklabel gpt > out 2>&1 || fail=1
# expect no output
compare /dev/null out || fail=1

# ensure that the disk is large enough
dev_n_sectors=$(parted -s $dev u s p|sed -n '2s/.* \([0-9]*\)s$/\1/p')
device_sectors_required=$(echo $default_end | sed 's/s$//')
# Ensure that $dev is large enough for this test
test $device_sectors_required -le $dev_n_sectors || fail=1

# create mount point dir
mount_point="`pwd`/mnt"
mkdir "$mount_point" || fail=1

# be sure to unmount upon interrupt, failure, etc.
cleanup_fn_() { umount "${dev}1" > /dev/null 2>&1; }

for fs_type in $FSTYPES; do
  echo "fs_type=$fs_type"

  # create an empty $fs_type partition, cylinder aligned, size > 256 MB
  parted -a min -s $dev mkpart p1 $start $default_end > out 2>&1 || fail=1
  compare /dev/null out || fail=1

  # print partition table
  parted -m -s $dev u s p > out 2>&1 || fail=1

  # wait for new partition device to appear
  wait_for_dev_to_appear_ ${dev}1

  case $fs_type in
    fat16) mkfs_cmd='mkfs.vfat -F 16'; fsck='fsck.vfat -v';;
    fat32) mkfs_cmd='mkfs.vfat -F 32'; fsck='fsck.vfat -v';;
    *) error "internal error: unhandled fs type: $fs_type";;
  esac

  # create the file system
  $mkfs_cmd ${dev}1 || fail=1

  # Set a very large dir_entries value
  # This triggeres different failures in FAT16 and FAT32, see expected output below
  printf '\xff\xff' | dd of=${dev}1 bs=1 seek=$((0x11)) conv=notrunc

  # NOTE: shrinking is the only type of resizing that works.
  # resize that file system to be one cylinder (8MiB) smaller
  # NOTE: A core dump is expected here, check output to determine if it is the correct failure
  fs-resize ${dev}1 0 $new_end > out 2>&1

  # Include full output for debugging
  cat out

  # FAT16 exepcts an Assert in duplicate_legacy_root_dir
  # FAT32 expects an Assert in ped_malloc
  case $fs_type in
    fat16) grep "Assertion.*duplicate_legacy_root_dir" out || fail=1;;
    fat32) grep "Assertion.*ped_malloc" out || fail=1;;
  esac

  # create a clean file system
  $mkfs_cmd ${dev}1 || fail=1

  # create 500 deep directory tree that overflows the 4096 byte tmp_buffer
  # to catch core dump in libparted/fs/r/fat/count.c flag_traverse_dir()
  mount "${dev}1" "$mount_point" || fail=1
  cat /dev/null > exp
  ( cd "$mount_point"; for d in `seq 500`; do mkdir TESTDIRR.DIR; cd TESTDIRR.DIR; done ) > out
  compare exp out || fail=1   # Ensure no errors creating directory tree
  umount "${dev}1" || fail=1

  # Make sure that buffer overflow is caught
  fs-resize ${dev}1 0 $new_end > out 2>&1

  # Include full output for debugging
  cat out

  # Confirm that the large dir_name was caught
  grep "Assertion.*strlen.*flag_traverse_dir" out || fail=1

  # Remove the partition explicitly, so that mklabel doesn't evoke a warning.
  parted -s $dev rm 1 || fail=1

  # Create a clean partition table for the next iteration.
  parted -s $dev mklabel gpt > out 2>&1 || fail=1
  # expect no output
  compare /dev/null out || fail=1

done

Exit $fail
