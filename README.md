# صيّاد التخفيضات · Sale Hunter

تطبيق آيفون (ويب) يتابع تخفيضات **أُناس البحرين** للرجال، يتحدث تلقائيًا كل 6 ساعات، ويقدر يرسل لك إشعار لما تنزل قطع جديدة أو ينزل سعر قطعة.

**التطبيق:** https://husain-313.github.io/sale-hunter/

## كيف يشتغل
1. **GitHub Actions** يشغّل `scraper/fetch_sales.py` كل 6 ساعات، يسحب كل قطع التخفيضات من أُناس البحرين، ويحفظها في `docs/data/sales.json`.
2. السكربت يتذكر متى ظهرت كل قطعة لأول مرة، ويكشف إذا نزل سعرها.
3. **GitHub Pages** ينشر مجلد `docs/` كتطبيق ويب تقدر تضيفه للشاشة الرئيسية في الآيفون.

## تثبيته على الآيفون
افتح الرابط في **Safari** ← زر المشاركة ← **إضافة إلى الشاشة الرئيسية**.

## الإشعارات (اختياري)
1. نزّل تطبيق **ntfy** من App Store.
2. اشترك في اسم موضوع سري وصعب التخمين، مثل `sale-hunter-husain-8x2k`.
3. في GitHub: Settings ← Secrets and variables ← Actions ← New repository secret، الاسم `NTFY_TOPIC` والقيمة اسم الموضوع.

اللي ينبّهك عليه تتحكم فيه من `config.json` تحت `watch`:

| الإعداد | المعنى |
|---|---|
| `min_discount` | أقل نسبة خصم (مثلًا 50) |
| `max_price` | أعلى سعر بالدينار (`null` = بدون حد) |
| `brands` | ماركات محددة، مثل `["Nike", "Fear of God Essentials"]` |
| `categories` | `Clothing` / `Shoes` / `Accessories` … |
| `sizes` / `shoe_sizes` | مثل `["M","L"]` و `["42","43"]` |

القائمة الفاضية `[]` تعني الكل.

## تشغيل يدوي
Actions ← **Update sales** ← **Run workflow**.
