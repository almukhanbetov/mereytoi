import Hero from "@/components/home/Hero";
import Services from "@/components/home/Services";
import PricingPackages from "@/components/home/PricingPackages";
import Clients from "@/components/home/Clients";
import Reviews from "@/components/home/Reviews";
import Contacts from "@/components/home/Contacts";
import { fetchCategories, fetchSiteStatistics } from "@/lib/api";

export default async function HomePage() {
  // Homepage "Услуги" shows category-level cards only, not individual
  // listings — the catalog (/services) is where specific listings live.
  const [categories, statistics] = await Promise.all([fetchCategories(), fetchSiteStatistics()]);

  return (
    <>
      <Hero statistics={statistics} />
      <Services categories={categories} />
      <PricingPackages />
      <Clients />
      <Reviews />
      <Contacts />
    </>
  );
}
