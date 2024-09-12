/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2020-2022 Loongson Technology Corporation Limited
 */
#include <asm/asm.h>
#include <asm/loongarch.h>
#include <asm/page.h>
#include <asm/pgtable.h>
#include <asm/regdef.h>
#include <asm/stackframe.h>

#define INVTLB_ADDR_GFALSE_AND_ASID	5

#define PTRS_PER_PGD_BITS	(PAGE_SHIFT - PTRLOG)
#define PTRS_PER_PUD_BITS	(PAGE_SHIFT - PTRLOG)
#define PTRS_PER_PMD_BITS	(PAGE_SHIFT - PTRLOG)
#define PTRS_PER_PTE_BITS	(PAGE_SHIFT - PTRLOG)

#ifdef CONFIG_64BIT
#define PTE_LL	ll.d
#define PTE_SC	sc.d
#else
#define PTE_LL	ll.w
#define PTE_SC	sc.w
#endif

	.macro tlb_do_page_fault, write
	SYM_CODE_START(tlb_do_page_fault_\write)
	UNWIND_HINT_UNDEFINED
	SAVE_ALL
	csrrd		a2, LOONGARCH_CSR_BADV
	move		a0, sp
	REG_S		a2, sp, PT_BVADDR
	li.w		a1, \write
	bl		do_page_fault
	RESTORE_ALL_AND_RET
	SYM_CODE_END(tlb_do_page_fault_\write)
	.endm

	tlb_do_page_fault 0
	tlb_do_page_fault 1

	/*
	 * dir_to_vaddr: Convert directory pointer to virtual address
	 *
	 * @da_mode: Data address mode
	 * @addr: Address register
	 * @tmp: Temporary register
	 */
	.macro dir_to_vaddr, da_mode, addr, tmp
#ifndef CONFIG_64BIT
	.if \da_mode == 0
	PTR_LI	\tmp, CACHE_BASE
	PTR_BSTRINS  \addr, \tmp, (BITS_PER_LONG - 1), DMW_PABITS
	.else
	PTR_BSTRINS  \addr, zero, (BITS_PER_LONG - 1), DMW_PABITS
	.endif
#endif
	.endm

	/*
	 * walk_ptep: Get PTE entry and pointer from PGD pointer
	 *
	 * @da_mode: Direct access mode
	 * @entryp:
	 *	- In: PGD pointer register
	 *	- Out: PTE pointer register
	 * @va: Virtual address (clobbered)
	 * @tmp: Temporary register (clobbered)
	 * @huge_lable: Label to jump if PTE is huge
	 */
	.macro walk_ptep, da_mode, entryp, va, tmp, huge_label
	/* Get PGD offset in bytes */
	PTR_BSTRPICK	\tmp, \va, PTRS_PER_PGD_BITS + PGDIR_SHIFT - 1, PGDIR_SHIFT
	PTR_ALSL	\entryp, \tmp, \entryp, _PGD_T_LOG2
	dir_to_vaddr	\da_mode, \entryp, \tmp
#if CONFIG_PGTABLE_LEVELS > 3
	PTR_L		\entryp, \entryp, 0
	PTR_BSTRPICK	\tmp, \va, PTRS_PER_PUD_BITS + PUD_SHIFT - 1, PUD_SHIFT
	PTR_ALSL	\entryp, \tmp, \entryp, _PMD_T_LOG2
	dir_to_vaddr	\da_mode, \entryp, \tmp
#endif
#if CONFIG_PGTABLE_LEVELS > 2
	PTR_L		\entryp, \entryp, 0
	PTR_BSTRPICK	\tmp, \va, PTRS_PER_PMD_BITS + PMD_SHIFT - 1, PMD_SHIFT
	PTR_ALSL	\entryp, \tmp, \entryp, _PMD_T_LOG2
	dir_to_vaddr	\da_mode, \entryp, \tmp
#endif

	PTR_L		\tmp, \entryp, 0

	/*
	 * For huge tlb entries, pmde doesn't contain an address but
	 * instead contains the tlb pte. Check the PAGE_HUGE bit and
	 * see if we need to jump to huge tlb processing.
	 */
#if 1
	PTR_ROTRI	\tmp, \tmp, _PAGE_HUGE_SHIFT + 1
	bltz		\tmp, tlb_huge_update_store

	PTR_ROTRI	\entryp, \tmp, (BITS_PER_LONG - (_PAGE_HUGE_SHIFT + 1))
#else
	move		\entryp, \tmp
#endif
	PTR_BSTRPICK	\tmp, \va, PTRS_PER_PTE_BITS + PAGE_SHIFT - 1, PAGE_SHIFT
	PTR_ALSL	\entryp, \tmp, \entryp, _PTE_T_LOG2
	dir_to_vaddr	\da_mode, \entryp, \tmp

	.endm

	/*
	 * ptep_update: Update PTE entry
	 *
	 * @ptep: PTE pointer register
	 * @tmp0: Temporary register (clobbered)
	 * @tmp1: Temporary register (clobbered)
	 * @set: Bitmask to set in PTE (imm)
	 * @nopage_bit: Bitmask to check
	 * @nopage_lable: Label to jump if PTE is not present
	 */

	.macro ptep_update, ptep, tmp0, tmp1, set, nopage_bit, nopage_label
1:
#ifdef CONFIG_SMP
	PTE_LL		\tmp0, \ptep, 0
#else
	PTR_L		\tmp0, \ptep, 0
#endif
.if (\nopage_bit & 0xfff) || (\set & 0xfff)
	andi		\tmp1, \tmp0, (\nopage_bit && 0xfff)
	xori		\tmp1, \tmp1, (\nopage_bit && 0xfff)
	beqz		\tmp1, \nopage_label
	ori		\tmp0, \tmp0, (\set && 0xfff)
.endif

.if (\nopage_bit & 0xfff000) || (\set & 0xfff000)
	.error "PTE change bits from 12 to 23 are not supported"
.endif

.if (\nopage_bit >> 24) != 0 || (\set >> 24) != 0
	PTR_ROTRI	\tmp0, \tmp0, 24
	andi		\tmp1, \tmp0, (\nopage_bit >> 24)
	xori		\tmp1, \tmp1, (\nopage_bit >> 24)
	beqz		\tmp1, \nopage_label
	ori		\tmp0, \tmp0, (\set >> 24)
	PTR_ROTRI	\tmp0, \tmp0, (BITS_PER_LONG - 24)
.endif

#ifdef CONFIG_SMP
	PTE_SC		\tmp0, \ptep, 0
	beqz		\tmp0, 1b
#else
	PTR_S		\tmp0, \ptep, 0
#endif
	.endm

	/*
	 * ptep_tlb_update: Load TLB entry CSRs with PTEP (regular page)
	 *
	 * @ptep: PTE pointer register (clobbered)
	 * @tmp0: Temporary register (clobbered)
	 */
	.macro ptep_tlb_update, ptep, tmp0
	tlbsrch
	PTR_BSTRINS	\ptep, zero, _PTE_T_LOG2, _PTE_T_LOG2
	PTR_L		\tmp0, \ptep, 0
	PTR_L		\ptep, \ptep, _PTE_T_SIZE
	csrwr		\tmp0, LOONGARCH_CSR_TLBELO0
	csrwr		\ptep, LOONGARCH_CSR_TLBELO1
	tlbwr
	.endm

	/*
	 * ptep_tlb_fill: Fill TLB entry with PTEP (regular page)
	 *
	 * @ptep: PTE pointer register (clobbered)
	 * @tmp0: Temporary register (clobbered)
	 */
	.macro ptep_tlb_fill, ptep, tmp0
	PTR_BSTRINS	\ptep, zero, _PTE_T_LOG2, _PTE_T_LOG2
	PTR_L		\tmp0, \ptep, 0
	PTR_L		\ptep, \ptep, _PTE_T_SIZE
#ifndef CONFIG_64BIT
	/* Filter out higher software bits for 32-bit */
	PTR_BSTRINS	\tmp0, zero, (BITS_PER_LONG - 1), (_PAGE_PFN_END_SHIFT + 1)
	PTR_BSTRINS	\ptep, zero, (BITS_PER_LONG - 1), (_PAGE_PFN_END_SHIFT + 1)
#endif
	csrwr		\tmp0, LOONGARCH_CSR_TLBRELO0
	csrwr		\ptep, LOONGARCH_CSR_TLBRELO1
	tlbfill
	.endm


	/*
	 * ptep_huge_tlb_update: Load TLB entry CSRs with PTEP (huge page)
	 *
	 * @ptep: PTE pointer register (clobbered)
	 * @tmp0: Temporary register (clobbered)
	 * @tmp1: Temporary register (clobbered)
	 */
	.macro ptep_huge_tlb_update, ptep, tmp0, tmp1
	/* Invalidate entry */
	csrrd		\tmp0, LOONGARCH_CSR_ASID
	csrrd		\tmp1, LOONGARCH_CSR_BADV
	andi		\tmp0, \tmp0, CSR_ASID_ASID
	invtlb		INVTLB_ADDR_GFALSE_AND_ASID, \tmp0, \tmp1

	/*
	 * A huge PTE describes an area the size of the
	 * configured huge page size. This is twice the
	 * of the large TLB entry size we intend to use.
	 * A TLB entry half the size of the configured
	 * huge page size is configured into entrylo0
	 * and entrylo1 to cover the contiguous huge PTE
	 * address space.
	 */
	PTR_L		\ptep, \ptep, 0
	/* Huge page: Move Global bit */
	xori		\ptep, \ptep, _PAGE_HUGE
	lu12i.w		\tmp1, _PAGE_HGLOBAL >> 12
	and		\tmp1, \tmp0, \tmp1
	PTR_SRL		\tmp1, \tmp1, (_PAGE_HGLOBAL_SHIFT - _PAGE_GLOBAL_SHIFT)
	or		\ptep, \ptep, \tmp1

	move		\tmp0, \ptep
	csrwr		\tmp0, LOONGARCH_CSR_TLBELO0

	/* Convert to entrylo1 */
	PTR_ADDI	\tmp1, zero, 1
	PTR_SLL		\tmp1, \tmp1, (HPAGE_SHIFT - 1)
	PTR_ADD		\ptep, \ptep, \tmp1
	csrwr		\ptep, LOONGARCH_CSR_TLBELO1

	/* Set huge page tlb entry size */
	PTR_LI		\ptep, (CSR_TLBIDX_PS >> 16)
	PTR_LI		\tmp1, (PS_HUGE_SIZE << (CSR_TLBIDX_PS_SHIFT - 16))
	csrxchg		\tmp1, \ptep, LOONGARCH_CSR_TLBIDX

	tlbfill

	/* Reset default page size */
	PTR_LI		\ptep, (CSR_TLBIDX_PS >> 16)
	PTR_LI		\tmp1, (PS_DEFAULT_SIZE << (CSR_TLBIDX_PS_SHIFT - 16))
	csrxchg		\tmp1, \ptep, LOONGARCH_CSR_TLBIDX
	.endm

	/*
	 * ptep_huge_tlb_fill: Fill TLB entry with PTEP (huge page)
	 *
	 * @ptep: PTE pointer register (clobbered)
	 * @tmp0: Temporary register (clobbered)
	 * @tmp1: Temporary register (clobbered)
	 */
	.macro ptep_huge_tlb_fill, ptep, tmp0, tmp1
	PTR_L		\ptep, \ptep, 0
	/* Huge page: Move Global bit */
	xori		\ptep, \ptep, _PAGE_HUGE
	lu12i.w		\tmp1, _PAGE_HGLOBAL >> 12
	and		\tmp1, \tmp0, \tmp1
	PTR_SRL		\tmp1, \tmp1, (_PAGE_HGLOBAL_SHIFT - _PAGE_GLOBAL_SHIFT)
	or		\ptep, \ptep, \tmp1

	move		\tmp0, \ptep
	csrwr		\tmp0, LOONGARCH_CSR_TLBRELO0

	/* Convert to entrylo1 */
	PTR_ADDI	\tmp1, zero, 1
	PTR_SLL		\tmp1, \tmp1, (HPAGE_SHIFT - 1)
	PTR_ADD		\ptep, \ptep, \tmp1
	csrwr		\ptep, LOONGARCH_CSR_TLBRELO1

	/* Set huge page tlb entry size */
	PTR_LI		\ptep, CSR_TLBREHI_PS
	PTR_LI		\tmp1, PS_HUGE_SIZE << CSR_TLBREHI_PS_SHIFT
	csrxchg		\tmp1, \ptep, LOONGARCH_CSR_TLBREHI

	tlbfill
	.endm

SYM_CODE_START(handle_tlb_protect)
	UNWIND_HINT_UNDEFINED
	BACKUP_T0T1
	SAVE_ALL
	move		a0, sp
	move		a1, zero
	csrrd		a2, LOONGARCH_CSR_BADV
	REG_S		a2, sp, PT_BVADDR
	la_abs		t0, do_page_fault
	jirl		ra, t0, 0
	RESTORE_ALL_AND_RET
SYM_CODE_END(handle_tlb_protect)

SYM_CODE_START(handle_tlb_load)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, EXCEPTION_KS0
	csrwr		t1, EXCEPTION_KS1
	csrwr		ra, EXCEPTION_KS2

	/*
	 * The vmalloc handling is not in the hotpath.
	 */
	csrrd		t0, LOONGARCH_CSR_BADV
	bltz		t0, vmalloc_load
	csrrd		t1, LOONGARCH_CSR_PGDL

vmalloc_done_load:
	/* Work out PTE pointer */
	walk_ptep	0, t1, t0, ra, tlb_huge_update_load

	ptep_update	t1, t0, ra, _PAGE_VALID, _PAGE_PRESENT, nopage_tlb_load
	ptep_tlb_update	t1, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

vmalloc_load:
	la_abs		t1, swapper_pg_dir
	b		vmalloc_done_load

	/* This is the entry point of a huge page. */
tlb_huge_update_load:
	ptep_update		t1, t0, ra, _PAGE_VALID, _PAGE_PRESENT, nopage_tlb_load
	ptep_huge_tlb_update	t1, t0, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

nopage_tlb_load:
	dbar		0x700
	csrrd		ra, EXCEPTION_KS2
	la_abs		t0, tlb_do_page_fault_0
	jr		t0
SYM_CODE_END(handle_tlb_load)

SYM_CODE_START(handle_tlb_load_ptw)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, LOONGARCH_CSR_KS0
	csrwr		t1, LOONGARCH_CSR_KS1
	la_abs		t0, tlb_do_page_fault_0
	jr		t0
SYM_CODE_END(handle_tlb_load_ptw)

SYM_CODE_START(handle_tlb_store)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, EXCEPTION_KS0
	csrwr		t1, EXCEPTION_KS1
	csrwr		ra, EXCEPTION_KS2

	/*
	 * The vmalloc handling is not in the hotpath.
	 */
	csrrd		t0, LOONGARCH_CSR_BADV
	bltz		t0, vmalloc_load
	csrrd		t1, LOONGARCH_CSR_PGDL

vmalloc_done_store:
	walk_ptep	0, t1, t0, ra, tlb_huge_update_store

	ptep_update	t1, t0, ra, _PAGE_VALID | _PAGE_DIRTY | _PAGE_MODIFIED, \
			_PAGE_PRESENT | _PAGE_WRITE, nopage_tlb_store
	ptep_tlb_update	t1, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

#ifdef CONFIG_64BIT
vmalloc_store:
	la_abs		t1, swapper_pg_dir
	b		vmalloc_done_store
#endif

	/* This is the entry point of a huge page. */
tlb_huge_update_store:
	ptep_update		t1, t0, ra, _PAGE_VALID | _PAGE_DIRTY | _PAGE_MODIFIED, \
				_PAGE_PRESENT | _PAGE_WRITE, nopage_tlb_store
	ptep_huge_tlb_update	t1, t0, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

nopage_tlb_store:
	dbar		0x700
	csrrd		ra, EXCEPTION_KS2
	la_abs		t0, tlb_do_page_fault_1
	jr		t0
SYM_CODE_END(handle_tlb_store)

SYM_CODE_START(handle_tlb_store_ptw)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, LOONGARCH_CSR_KS0
	csrwr		t1, LOONGARCH_CSR_KS1
	la_abs		t0, tlb_do_page_fault_1
	jr		t0
SYM_CODE_END(handle_tlb_store_ptw)

SYM_CODE_START(handle_tlb_modify)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, EXCEPTION_KS0
	csrwr		t1, EXCEPTION_KS1
	csrwr		ra, EXCEPTION_KS2

	/*
	 * The vmalloc handling is not in the hotpath.
	 */
	csrrd		t0, LOONGARCH_CSR_BADV
	bltz		t0, vmalloc_modify
	csrrd		t1, LOONGARCH_CSR_PGDL

vmalloc_done_modify:
	walk_ptep	0, t1, t0, ra, tlb_huge_update_modify

	ptep_update	t1, t0, ra, _PAGE_VALID | _PAGE_DIRTY | _PAGE_MODIFIED, \
			_PAGE_WRITE, nopage_tlb_modify
	ptep_tlb_update	t1, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

vmalloc_modify:
	la_abs		t1, swapper_pg_dir
	b		vmalloc_done_modify

	/* This is the entry point of a huge page. */
tlb_huge_update_modify:
	ptep_update	t1, t0, ra, _PAGE_VALID | _PAGE_DIRTY | _PAGE_MODIFIED, \
			_PAGE_WRITE, nopage_tlb_modify
	ptep_huge_tlb_update	t1, t0, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

nopage_tlb_modify:
	dbar		0x700
	csrrd		ra, EXCEPTION_KS2
	la_abs		t0, tlb_do_page_fault_1
	jr		t0
SYM_CODE_END(handle_tlb_modify)

SYM_CODE_START(handle_tlb_modify_ptw)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, LOONGARCH_CSR_KS0
	csrwr		t1, LOONGARCH_CSR_KS1
	la_abs		t0, tlb_do_page_fault_1
	jr		t0
SYM_CODE_END(handle_tlb_modify_ptw)

SYM_CODE_START(handle_tlb_refill_lspw)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, LOONGARCH_CSR_TLBRSAVE
	csrrd		t0, LOONGARCH_CSR_PGD
	lddir		t0, t0, 3
#if CONFIG_PGTABLE_LEVELS > 3
	lddir		t0, t0, 2
#endif
#if CONFIG_PGTABLE_LEVELS > 2
	lddir		t0, t0, 1
#endif
	ldpte		t0, 0
	ldpte		t0, 1
	tlbfill
	csrrd		t0, LOONGARCH_CSR_TLBRSAVE
	ertn
SYM_CODE_END(handle_tlb_refill_lspw)

SYM_CODE_START(handle_tlb_refill)
	UNWIND_HINT_UNDEFINED
	csrwr		t0, EXCEPTION_KS0
	csrwr		t1, EXCEPTION_KS1
	csrwr		ra, EXCEPTION_KS2

	csrrd		t1, LOONGARCH_CSR_PGD
	csrrd		t0, LOONGARCH_CSR_TLBRBADV

	walk_ptep	1, t1, t0, ra, tlb_huge_refill
	ptep_tlb_fill	t1, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn

tlb_huge_refill:
	ptep_huge_tlb_fill	t1, t0, ra

	csrrd		t0, EXCEPTION_KS0
	csrrd		t1, EXCEPTION_KS1
	csrrd		ra, EXCEPTION_KS2
	ertn
SYM_CODE_END(handle_tlb_refill)
