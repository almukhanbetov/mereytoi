import Hero from "@/components/home/Hero";
import Services from "@/components/home/Services";
import PricingPackages from "@/components/home/PricingPackages";
import Clients from "@/components/home/Clients";
import Reviews from "@/components/home/Reviews";
import Contacts from "@/components/home/Contacts";
import { fetchCategories, fetchListings } from "@/lib/api";

const FEATURED_COUNT = 6;

export default async function HomePage() {
  const [categories, listings] = await Promise.all([fetchCategories(), fetchListings()]);
  // fetchListings() already returns only is_active listings, sorted by
  // rating desc (see backend ListingHandler.List) — no featured/sort_order
  // field exists on the model, so the top N of that stable order is the
  // homepage's "featured" selection.
  const featured = listings.slice(0, FEATURED_COUNT);

  return (
    <>
      <Hero />
      <Services listings={featured} categories={categories} />
      <PricingPackages />
      <Clients />
      <Reviews />
      <Contacts />
    </>
  );
}
