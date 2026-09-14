/*
libparted
    Copyright (C) 1998-2000, 2002, 2004, 2007, 2009-2014, 2019-2023, 2026 Free
    Software Foundation, Inc.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see<http://www.gnu.org/licenses/>.
*/

#include <config.h>

#include <parted/parted.h>
#include <parted/endian.h>

#include <unistd.h>

#define EXFAT_SIGNATURE "EXFAT   "

PedGeometry* exfat_probe (PedGeometry* geom)
{
    uint8_t *buf = alloca(geom->dev->sector_size);

    if (!ped_geometry_read(geom, buf, 0, 1)) {
        return NULL;
    }
    if (strncmp (EXFAT_SIGNATURE, ((char *)buf + 3), strlen (EXFAT_SIGNATURE)) == 0) {
        uint64_t sector_count;
        unsigned char bytes_per_sector_shift;
        uint64_t fs_size;
        PedGeometry *newg = NULL;

        memcpy(&sector_count, buf + 0x48, sizeof(uint64_t));
        memcpy(&bytes_per_sector_shift, buf + 0x6c, sizeof(unsigned char));
        if (bytes_per_sector_shift < 9 || bytes_per_sector_shift > 12) {
            return NULL;
        }
        fs_size = sector_count * (1ULL << bytes_per_sector_shift);
        newg = ped_geometry_new(geom->dev, geom->start, fs_size);

        return newg;
    }

    return NULL;
}

static PedFileSystemOps exfat_ops = {
    probe: exfat_probe,
};

static PedFileSystemType exfat_type = {
    next: NULL,
    ops: &exfat_ops,
    name: "exfat",
};

void ped_file_system_exfat_init()
{
    ped_file_system_type_register (&exfat_type);
}

void ped_file_system_exfat_done ()
{
    ped_file_system_type_unregister (&exfat_type);
}
