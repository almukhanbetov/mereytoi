import { Suspense } from "react";
import ServicesClient from "@/components/services/ServicesClient";
import { fetchCategories, fetchFeed } from "@/lib/api";

export const metadata = {
  title: "Организация той и мероприятий в Алматы | MEREYTOI",
  description:
    "Организация той, свадеб, юбилеев и корпоративов в Алматы. Ведущие, декор, фото и видео, шоу-программы и полная координация мероприятия от MEREYTOI.",
};

export default async function ServicesPage({ searchParams }) {
  const category = (await searchParams)?.category || "all";
  const [categories, firstPage] = await Promise.all([
    fetchCategories(),
    fetchFeed({ category: typeof category === "string" ? category : "all" }),
  ]);
  return (
    <Suspense>
      <ServicesClient categories={categories} initialPage={firstPage} />
    </Suspense>
  );
}
