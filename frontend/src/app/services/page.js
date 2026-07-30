import ServicesClient from "@/components/services/ServicesClient";
import { fetchCategories, fetchListings } from "@/lib/api";

export const metadata = {
  title: "Каталог услуг — MEREYTOI",
  description: "Рестораны и локации, ведущие, шоу-программы, артисты и звёзды эстрады для вашего тоя.",
};

export default async function ServicesPage() {
  const [categories, listings] = await Promise.all([fetchCategories(), fetchListings()]);
  return <ServicesClient categories={categories} listings={listings} />;
}
