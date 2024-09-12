// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2020-2022 Loongson Technology Corporation Limited
 */
#include <linux/export.h>
#include <linux/types.h>
#include <linux/io.h>

/*
 * Copy data from IO memory space to "real" memory space.
 */
void __memcpy_fromio(void *to, const volatile void __iomem *from, size_t count)
{
	while (count && !IS_ALIGNED((unsigned long)from, 8)) {
		*(u8 *)to = __raw_readb(from);
		from++;
		to++;
		count--;
	}

#ifdef __raw_readq
	while (count >= 8) {
		*(u64 *)to = __raw_readq(from);
		from += 8;
		to += 8;
		count -= 8;
	}
#else
	while (count >= 4) {
		*(u64 *)to = __raw_readl(from);
		from += 4;
		to += 4;
		count -= 4;
	}
#endif

	while (count) {
		*(u8 *)to = __raw_readb(from);
		from++;
		to++;
		count--;
	}
}
EXPORT_SYMBOL(__memcpy_fromio);

/*
 * Copy data from "real" memory space to IO memory space.
 */
void __memcpy_toio(volatile void __iomem *to, const void *from, size_t count)
{
	while (count && !IS_ALIGNED((unsigned long)to, 8)) {
		__raw_writeb(*(u8 *)from, to);
		from++;
		to++;
		count--;
	}

#ifdef __raw_writeq
	while (count >= 8) {
		__raw_writeq(*(u64 *)from, to);
		from += 8;
		to += 8;
		count -= 8;
	}
#else
	while (count >= 4) {
		__raw_writel(*(u32 *)from, to);
		from += 4;
		to += 4;
		count -= 4;
	}
#endif

	while (count) {
		__raw_writeb(*(u8 *)from, to);
		from++;
		to++;
		count--;
	}
}
EXPORT_SYMBOL(__memcpy_toio);

/*
 * "memset" on IO memory space.
 */
void __memset_io(volatile void __iomem *dst, int c, size_t count)
{
	u32 lc = (u8)c;
	u64 qc;

	lc |= lc << 8;
	lc |= lc << 16;
	qc = lc | ((u64)lc << 32);

	while (count && !IS_ALIGNED((unsigned long)dst, 8)) {
		__raw_writeb(c, dst);
		dst++;
		count--;
	}

#ifdef __raw_writeq
	while (count >= 8) {
		__raw_writeq(qc, dst);
		dst += 8;
		count -= 8;
	}
#else
	while (count >= 4) {
		__raw_writel(lc, dst);
		dst += 4;
		count -= 4;
	}
#endif

	while (count) {
		__raw_writeb(c, dst);
		dst++;
		count--;
	}
}
EXPORT_SYMBOL(__memset_io);
