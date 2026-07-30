'use client';

import Link from "next/link";
import { T } from "@/context/AppProviders";

export default function ServiceNotFound() {
  return (
    <section className="product-detail">
      <div className="container" style={{ textAlign: "center", padding: "60px 0" }}>
        <p className="section-title"><T ru="Услуга не найдена" kz="Қызмет табылмады" /></p>
        <Link href="/services" className="btn btn--gold" style={{ marginTop: 20, display: "inline-flex" }}>
          <T ru="Вернуться в каталог" kz="Каталогқа оралу" />
        </Link>
      </div>
    </section>
  );
}
