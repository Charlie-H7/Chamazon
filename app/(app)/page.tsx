import Image from "next/image";
// import ProductCard from "@/components/carousel/ProductCard";
// import Carousel from "@/components/carousel/carousel";
import Carousel from "@/components/carousel/Carousel";




export default function Home() {
  return (
    <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      {/* <main className="flex flex-1 w-full max-w-6xl flex-col items-center justify-center py-32 px-16 bg-white dark:bg-black sm:items-start"> */}
        {/* <main className="flex flex-1 w-full flex-col items-center justify-start py-32 px-16 bg-white dark:bg-black sm:items-start"> */}
        {/* <ProductCard /> */}
        <div className="flex flex-1 w-full max-w-[1600px] flex-col items-center justify-center py-12 bg-white dark:bg-black sm:items-start">
          <Carousel />
        </div>
      {/* </main> */}
    </div>
  );
}
