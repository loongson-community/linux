/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2022 Loongson Technology Corporation Limited
 */
#ifndef _ASM_TIMEX_H
#define _ASM_TIMEX_H

#ifdef __KERNEL__

#include <linux/compiler.h>

#include <asm/cpu.h>
#include <asm/cpu-features.h>

typedef unsigned int cycles_t;

static inline cycles_t get_cycles(void)
{
#ifdef CONFIG_64BIT
	return drdtime();
#else
	return rdtimel();
#endif
}
#define get_cycles get_cycles

static inline u32 get_cycles_hi(void)
{
	return rdtimeh();
}
#define get_cycles_hi get_cycles_hi

#ifdef CONFIG_64BIT
static inline u64 get_cycles64(void)
{
	return get_cycles();
}
#else /* CONFIG_64BIT */
static inline u64 get_cycles64(void)
{
	u32 hi, lo;

	do {
		hi = get_cycles_hi();
		lo = get_cycles();
	} while (hi != get_cycles_hi());

	return ((u64)hi << 32) | lo;
}
#endif /* CONFIG_64BIT */

#endif /* __KERNEL__ */

#endif /*  _ASM_TIMEX_H */
