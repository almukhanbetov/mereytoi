import { Suspense } from "react";
import ServicesClient from "@/components/services/ServicesClient";
import { fetchCategories, fetchListings } from "@/lib/api";

export const metadata = {
  title: "Организация той и мероприятий в Алматы | MEREYTOI",
  description:
    "Организация той, свадеб, юбилеев и корпоративов в Алматы. Ведущие, декор, фото и видео, шоу-программы и полная координация мероприятия от MEREYTOI.",
};

export default async function ServicesPage() {
  const [categories, listings] = await Promise.all([fetchCategories(), fetchListings()]);
  return (
    <Suspense>
      <ServicesClient categories={categories} listings={listings} />
    </Suspense>
  );
}
