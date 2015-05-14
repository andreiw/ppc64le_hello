/*
 * KPCR and accessors.
 *
 * Copyright (C) 2015 Andrei Warkentin <andrey.warkentin@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#ifndef KPCR_H
#define KPCR_H

#include <types.h>
#include <defs.h>

/*
 * Must match kpcr in entry.S.
 */
typedef struct {
	uint64_t toc;
	uint64_t opal_base;
	uint64_t opal_entry;
} kpcr_t;


static inline kpcr_t *
kpcr_get(void)
{
	register kpcr_t *kpcr asm("r13");
	return kpcr;
}
#endif /* KPCR_H */