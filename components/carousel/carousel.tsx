
"use client";

import useEmblaCarousel from "embla-carousel-react";

export default function Carousel() {
  const [emblaRef, emblaApi] = useEmblaCarousel({
    loop: false,
    align: "start",
  });

  return (
    <div className="w-full">
      {/* Viewport */}
      {/* <div ref={emblaRef} className="overflow-hidden"> */}
      <div ref={emblaRef} className="overflow-hidden">
        {/* Container */}
        <div className="flex touch-pan-y">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((num) => (
            <div
              key={num}
              className="min-w-0 flex-[0_0_50%] p-2 md:flex-[0_0_25%]"
            >
              <div className="flex h-48 items-center justify-center rounded-lg bg-gray-200 text-3xl text-black">
                {num}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Navigation */}
      <div className="mt-4 flex gap-2">
        <button
          onClick={() => emblaApi?.scrollPrev()}
          className="rounded bg-gray-800 px-4 py-2 text-white"
        >
          Previous
        </button>

        <button
          onClick={() => emblaApi?.scrollNext()}
          className="rounded bg-gray-800 px-4 py-2 text-white"
        >
          Next
        </button>
      </div>
    </div>
  );
}
