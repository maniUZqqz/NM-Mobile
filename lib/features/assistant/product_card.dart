import 'package:flutter/material.dart';
import 'package:nm_mobile/core/theme/app_theme.dart';
import 'package:nm_mobile/features/assistant/assistant_models.dart';

/// کارت یک محصول برای بازاریاب حینِ تماس: قیمت، موجودی، سود، کمترین قیمتِ بی‌ضرر و
/// حداکثر تخفیف. هر مقدارِ نامعلوم «ثبت نشده» است، هرگز ۰.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.selected = false, this.onTap});

  final ProductInfo product;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (p.brand.isNotEmpty || p.sku.isNotEmpty)
                Text(
                  [if (p.brand.isNotEmpty) p.brand, if (p.sku.isNotEmpty) 'کد ${p.sku}'].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              const SizedBox(height: 8),
              _row('قیمت فروش', p.priceText),
              _row('موجودی', p.stockText),
              _row('قیمت تمام‌شده', p.costText, sensitive: true),
              _row('سود هر عدد', p.unitProfit == null ? kNotRegistered : '${p.profitText}  (${p.marginText})', sensitive: true),
              _row('کمترین قیمتِ بی‌ضرر', p.floorText, sensitive: true, bold: true),
              _row('حداکثر تخفیف', p.maxDiscountText, sensitive: true, bold: true),
              if (p.shortDescription.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(p.shortDescription, style: const TextStyle(fontSize: 12, height: 1.5)),
              ],
              if (p.attributes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  p.attributes.take(6).map((e) => '${e.key}: ${e.value}').join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                ),
              ],
              if (p.variants.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  p.variants
                      .take(6)
                      .map((v) => '${v.name}: ${v.available == null ? kNotRegistered : '${fmtNumber(v.available)} عدد'}')
                      .join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool sensitive = false, bool bold = false}) {
    final missing = v == kNotRegistered || v.startsWith(kNotRegistered);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Row(
              children: [
                Flexible(
                  child: Text(k, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                if (sensitive) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.textSecondary),
                ],
              ],
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: missing ? AppColors.warning : null,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
