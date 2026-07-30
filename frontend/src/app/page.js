import Hero from "@/components/home/Hero";
import Services from "@/components/home/Services";
import Gallery from "@/components/home/Gallery";
import Reviews from "@/components/home/Reviews";
import Contacts from "@/components/home/Contacts";

export default function HomePage() {
  return (
    <>
      <Hero />
      <Services />
      <Gallery />
      <Reviews />
      <Contacts />
    </>
  );
}
