/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2024 Loongson Technology Corporation Limited
 */

#ifndef _DRIVERS_IRQCHIP_IRQ_LOONGSON_H
#define _DRIVERS_IRQCHIP_IRQ_LOONGSON_H

int find_pch_pic(u32 gsi);

#ifdef CONFIG_LOONGSON_LIOINTC
int liointc_acpi_init(struct irq_domain *parent,
					struct acpi_madt_lio_pic *acpi_liointc);
#else
static inline int liointc_acpi_init(struct irq_domain *parent,
					struct acpi_madt_lio_pic *acpi_liointc)
{
	return -ENOSYS;
}
#endif

#ifdef CONFIG_LOONGSON_EIOINTC
int eiointc_acpi_init(struct irq_domain *parent,
					struct acpi_madt_eio_pic *acpi_eiointc);
#else
static inline int eiointc_acpi_init(struct irq_domain *parent,
					struct acpi_madt_eio_pic *acpi_eiointc)
{
	return -ENOSYS;
}
#endif

#ifdef CONFIG_LOONGARCH_AVEC
int avecintc_acpi_init(struct irq_domain *parent);
#else
static inline int avecintc_acpi_init(struct irq_domain *parent)
{
	return -ENOSYS;
}
#endif

#ifdef CONFIG_LOONGSON_HTVEC
int htvec_acpi_init(struct irq_domain *parent,
					struct acpi_madt_ht_pic *acpi_htvec);
#else
static inline int htvec_acpi_init(struct irq_domain *parent,
					struct acpi_madt_ht_pic *acpi_htvec)
{
	return -ENOSYS;
}
#endif

#ifdef CONFIG_LOONGSON_PCH_LPC
int pch_lpc_acpi_init(struct irq_domain *parent,
					struct acpi_madt_lpc_pic *acpi_pchlpc);
#else
static inline int pch_lpc_acpi_init(struct irq_domain *parent,
					struct acpi_madt_lpc_pic *acpi_pchlpc)
{
	return -ENOSYS;
}
#endif

#ifdef CONFIG_LOONGSON_PCH_PIC
int pch_pic_acpi_init(struct irq_domain *parent,
					struct acpi_madt_bio_pic *acpi_pchpic);
#else
static inline int pch_pic_acpi_init(struct irq_domain *parent,
					struct acpi_madt_bio_pic *acpi_pchpic)
{
	return -ENOSYS;
}
#endif

#ifdef CONFIG_LOONGSON_PCH_MSI
int pch_msi_acpi_init(struct irq_domain *parent,
					struct acpi_madt_msi_pic *acpi_pchmsi);
int pch_msi_acpi_init_avec(struct irq_domain *parent);
#else
static inline int pch_msi_acpi_init(struct irq_domain *parent,
					struct acpi_madt_msi_pic *acpi_pchmsi)
{
	return -ENOSYS;
}

static inline int pch_msi_acpi_init_avec(struct irq_domain *parent)
{
	return -ENOSYS;
}
#endif

#endif /* _DRIVERS_IRQCHIP_IRQ_LOONGSON_H */
