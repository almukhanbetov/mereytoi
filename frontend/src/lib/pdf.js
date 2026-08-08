'use client';

/**
 * Renders the commercial offer as styled HTML off-screen, rasterizes it
 * with html2canvas, and drops the image into a jsPDF page. Going through
 * an image (rather than jsPDF's built-in text) is what makes Cyrillic/Kazakh
 * text render correctly — jsPDF's default fonts have no Cyrillic glyphs.
 */
export async function downloadOfferPdf({ items, total, lang, formatPrice }) {
  if (typeof window === 'undefined' || items.length === 0) return;

  const [{ default: jsPDF }, { default: html2canvas }] = await Promise.all([
    import('jspdf'),
    import('html2canvas'),
  ]);

  const dateStr = new Date().toLocaleDateString('ru-RU', { day: '2-digit', month: 'long', year: 'numeric' });

  const rows = items.map((item, i) => {
    const detail = item.guests
      ? `${item.guests} ${lang === 'kz' ? 'адам' : 'чел.'} × ${formatPrice(item.unitPrice)}`
      : '';
    return `
      <tr>
        <td style="padding:14px 0; border-bottom:1px solid #e5ddd0; vertical-align:top;">
          <div style="font-weight:700; font-size:15px; color:#1a1410;">${i + 1}. ${item.name}</div>
          ${detail ? `<div style="font-size:12px; color:#8a7d6a; margin-top:4px;">${detail}</div>` : ''}
        </td>
        <td style="padding:14px 0; border-bottom:1px solid #e5ddd0; text-align:right; font-weight:700; white-space:nowrap; color:#1a1410;">
          ${formatPrice(item.totalPrice)}
        </td>
      </tr>`;
  }).join('');

  const wrapper = document.createElement('div');
  wrapper.style.cssText = 'position:fixed; left:-9999px; top:0; width:794px; background:#fdfbf8; color:#1a1410; font-family:Georgia, "Times New Roman", serif; padding:56px;';
  wrapper.innerHTML = `
    <div style="text-align:center; margin-bottom:40px;">
      <div style="font-size:28px; font-weight:700; letter-spacing:1px;">MEREY<span style="color:#b8874a;">TOI</span></div>
      <div style="font-size:13px; color:#8a7d6a; margin-top:8px; text-transform:uppercase; letter-spacing:3px;">
        ${lang === 'kz' ? 'Коммерциялық ұсыныс' : 'Коммерческое предложение'}
      </div>
      <div style="font-size:12px; color:#8a7d6a; margin-top:6px;">${dateStr}</div>
    </div>
    <table style="width:100%; border-collapse:collapse;">${rows}</table>
    <div style="display:flex; justify-content:space-between; align-items:center; margin-top:28px; padding-top:20px; border-top:2px solid #1a1410;">
      <span style="font-size:15px; font-weight:700;">${lang === 'kz' ? 'Барлығы' : 'Итого'}</span>
      <span style="font-size:24px; font-weight:700; color:#b8874a;">${formatPrice(total)}</span>
    </div>
    <div style="margin-top:48px; text-align:center; font-size:11px; color:#8a7d6a; letter-spacing:1px;">mereytoi.kz</div>
  `;
  document.body.appendChild(wrapper);

  try {
    const canvas = await html2canvas(wrapper, { scale: 2, backgroundColor: '#fdfbf8' });
    const imgData = canvas.toDataURL('image/png');

    const pdf = new jsPDF({ unit: 'pt', format: 'a4' });
    const pageWidth = pdf.internal.pageSize.getWidth();
    const imgHeight = (canvas.height * pageWidth) / canvas.width;
    pdf.addImage(imgData, 'PNG', 0, 0, pageWidth, imgHeight);
    pdf.save(`mereytoi-offer-${Date.now()}.pdf`);
  } finally {
    document.body.removeChild(wrapper);
  }
}
