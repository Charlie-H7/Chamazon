"use client"

// import { headers } from "next/headers"

/*
  This component should be client because it has multiple functions that
*/

// export default function Header() {
//   return (
    
//     <header >
//       <div className="bg-gray-800 text-white py-4 mx-auto flex justify-center">
//         <div id="Logo"className="mx-4">Logo</div>
//         <input type="text" className="bg-white mx-auto flex-1"/>
//         <div className="mx-4">Login</div>
//         <div className="mx-4">Cart</div>
//       </div>
//       {/* <div className="bg-gray-700 flex overflow-x-auto lg:overflow-hidden"> */}
//       <div className="bg-gray-700 flex overflow-hidden w-full">
//         {Array.from({ length: 20 }).map((_, i) => (
//           <div key={i} className="shrink-0 px-4">
//             hallo {i}
//           </div>
//         ))}
//       </div>
//     {/* <div className="bg-gray-700 flex overflow-hidden">
//       <div className="pl-4">hallo</div>
//       <div className="pl-4">hallo</div>
//       <div className="pl-4">hallo</div>
//     </div> */}
//     </header>
//     // <footer className="bg-gray-800 text-white py-4">
//     //   <div className="container mx-auto text-center">
//     //     &copy; {new Date().getFullYear()} Your Company. All rights reserved.
//     //   </div>
//     // </footer>
//   );
// }



import { useEffect, useRef, useState } from "react";
import Link from "next/link"

const items = Array.from({ length: 30 }, (_, i) => `hallo ${i + 1}`);

export default function Navbar() {
  const containerRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const [visibleCount, setVisibleCount] = useState(0);

  useEffect(() => {
    const container = containerRef.current;
    const measure = measureRef.current;

    if (!container || !measure) return;

    const updateVisibleCount = () => {
      const availableWidth = container.clientWidth;
      const children = Array.from(measure.children) as HTMLElement[];

      let usedWidth = 0;
      let count = 0;

      for (const child of children) {
        const width = child.getBoundingClientRect().width;

        if (usedWidth + width > availableWidth) break;

        usedWidth += width;
        count++;
      }

      setVisibleCount(count);
    };

    // Observer, watches changes to these ref in the dom. The param is a callback function run when a ref changes
    const observer = new ResizeObserver(updateVisibleCount);

    observer.observe(container);
    observer.observe(measure);

    updateVisibleCount();

    return () => observer.disconnect();
  }, []);

  return (
    <header >
      <div className="bg-gray-800 text-white py-4 mx-auto flex justify-center">
        <div id="Logo"className="mx-4">Logo</div>
        <input type="text" className="bg-white mx-auto flex-1"/>      
        <Link href="/login" className="mx-4">Login</Link>
        <div className="mx-4">Cart</div>
        <Link href="/cart" className="mx-4"></Link>
      </div>
      <div className="relative w-full overflow-hidden">
        {/* Visible navbar */}
        <div
          ref={containerRef}
          className="flex w-full overflow-hidden bg-gray-700"
        >
          {items.slice(0, visibleCount).map((item) => (
            <div key={item} className="shrink-0 px-4 py-2">
              {item}
            </div>
          ))}
        </div>

        {/* Invisible measurement row */}
        <div
          ref={measureRef}
          aria-hidden="true"
          className="pointer-events-none invisible absolute left-0 top-0 flex w-max whitespace-nowrap"
        >
          {items.map((item) => (
            <div key={item} className="shrink-0 px-4 py-2">
              {item}
            </div>
          ))}
        </div>
      </div>
  </header>
);
}