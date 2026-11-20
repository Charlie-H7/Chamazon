"use client"
import Link from "next/link";
import React from 'react'
import useEmblaCarousel from "embla-carousel-react";
import { EmblaOptionsType } from 'embla-carousel'

// export default function Product({ product }){
export default function ProductCard(){
  const [emblaRef] = useEmblaCarousel();
  return(
    <div className="embla">
      <div className="embla__viewport" ref={emblaRef}>
        <div className="embla__container">
          <div className="embla__slide">
            <div className="embla__slide__number">
              <span>1</span>
            </div>
          </div>
          <div className="embla__slide">
            <div className="embla__slide__number">
              <span>2</span>
            </div>
          </div>
        </div>
      </div>

      <button className="embla__prev">Scroll to prev</button>
      <button className="embla__next">Scroll to next</button>
    </div>
  )
}

// import {
//   NextButton,
//   PrevButton,
//   usePrevNextButtons
// } from '@/components/carousel/EmblaCarouselArrowButtons'
// import { DotButton, useDotButton } from "@/components/carousel/EmblaCarouselDotButton"

// type PropType = {
//   slides: number[]
//   options?: EmblaOptionsType
// }

// export const EmblaCarousel = (props: PropType) => {
//   const { slides, options } = props
//   const [emblaRef, emblaApi] = useEmblaCarousel(options)

//   const { selectedIndex, scrollSnaps, onDotButtonClick } =
//     useDotButton(emblaApi)

//   const {
//     prevBtnDisabled,
//     nextBtnDisabled,
//     onPrevButtonClick,
//     onNextButtonClick
//   } = usePrevNextButtons(emblaApi)

//   return (
//     <div className="embla">
//       <div className="embla__viewport" ref={emblaRef}>
//         <div className="embla__container">
//           {slides.map((index) => (
//             <div className="embla__slide" key={index}>
//               <div className="embla__slide__number">
//                 <span>{index + 1}</span>
//               </div>
//             </div>
//           ))}
//         </div>
//       </div>

//       <div className="embla__controls">
//         <div className="embla__buttons">
//           <PrevButton onClick={onPrevButtonClick} disabled={prevBtnDisabled} />
//           <NextButton onClick={onNextButtonClick} disabled={nextBtnDisabled} />
//         </div>

//         <div className="embla__dots">
//           {scrollSnaps.map((_, index) => (
//             <DotButton
//               key={index}
//               onClick={() => onDotButtonClick(index)}
//               className={'embla__dot'.concat(
//                 index === selectedIndex ? ' embla__dot--selected' : ''
//               )}
//             />
//           ))}
//         </div>
//       </div>
//     </div>
//   )
// }
