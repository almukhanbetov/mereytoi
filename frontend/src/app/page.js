import Hero from "@/components/home/Hero";
import Services from "@/components/home/Services";
import PricingPackages from "@/components/home/PricingPackages";
import Clients from "@/components/home/Clients";
import Reviews from "@/components/home/Reviews";
import Contacts from "@/components/home/Contacts";

export default function HomePage() {
  return (
    <>
      <Hero />
      <Services />
      <PricingPackages />
      <Clients />
      <Reviews />
      <Contacts />
    </>
  );
}
