import { notFound } from "next/navigation";
import ServiceDetail from "@/components/services/ServiceDetail";
import { fetchListing, fetchListingsByCategory } from "@/lib/api";

export async function generateMetadata({ params }) {
  const { id } = await params;
  const listing = await fetchListing(id);
  if (!listing) return { title: "Услуга не найдена — MEREYTOI" };
  return {
    title: `${listing.name_ru} — MEREYTOI`,
    description: listing.description_ru,
  };
}

export default async function ServicePage({ params }) {
  const { id } = await params;
  const listing = await fetchListing(id);
  if (!listing) notFound();

  const sameCategory = listing.category
    ? await fetchListingsByCategory(listing.category.slug)
    : [];
  // The API lists newest first; «related» stays the best rated of the category.
  const related = sameCategory
    .filter((l) => l.id !== listing.id)
    .sort((a, b) => b.rating - a.rating)
    .slice(0, 4);

  return <ServiceDetail listing={listing} related={related} />;
}
