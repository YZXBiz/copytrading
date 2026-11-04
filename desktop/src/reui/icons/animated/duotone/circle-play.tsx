import type { HTMLAttributes } from "react"
import { forwardRef, useCallback, useImperativeHandle, useRef } from "react"
import { cn } from "cn"
import type { Variants } from "motion/react"
import { motion, useAnimation } from "motion/react"

export interface CirclePlayIconHandle {
  startAnimation: () => void
  stopAnimation: () => void
}

interface CirclePlayIconProps extends HTMLAttributes<HTMLDivElement> {}

const PRESS_VARIANTS: Variants = {
  // Tactile press: the disc compresses inward (the click), springs back past
  // rest with a small pop, then settles. Pure scale about center. Returns to
  // rest (scale 1) and normal carries its own transition, so a hover-out eases home.
  normal: {
    scale: 1,
    transition: { duration: 0.3, ease: "easeOut" },
  },
  animate: {
    scale: [1, 0.9, 1.06, 0.98, 1],
    transition: {
      duration: 0.5,
      ease: "easeOut",
      times: [0, 0.22, 0.5, 0.76, 1],
    },
  },
}

const CirclePlayIcon = forwardRef<CirclePlayIconHandle, CirclePlayIconProps>(
  ({ onMouseEnter, onMouseLeave, className, ...props }, ref) => {
    const controls = useAnimation()
    const isControlledRef = useRef(false)

    useImperativeHandle(ref, () => {
      isControlledRef.current = true
      return {
        startAnimation: () => controls.start("animate"),
        stopAnimation: () => controls.start("normal"),
      }
    })

    const handleMouseEnter = useCallback(
      (e: React.MouseEvent<HTMLDivElement>) => {
        if (isControlledRef.current) {
          onMouseEnter?.(e)
        } else {
          controls.start("animate")
        }
      },
      [controls, onMouseEnter]
    )

    const handleMouseLeave = useCallback(
      (e: React.MouseEvent<HTMLDivElement>) => {
        if (isControlledRef.current) {
          onMouseLeave?.(e)
        } else {
          controls.start("normal")
        }
      },
      [controls, onMouseLeave]
    )

    return (
      <div
        className={cn(className)}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        {...props}
      >
        <motion.svg
          width="100%"
          height="100%"
          viewBox="0 0 24 24"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          overflow="visible"
          variants={PRESS_VARIANTS}
          animate={controls}
          style={{ transformOrigin: "50% 50%" }}
        >
          <path
            d="M 22.543 11.975C 22.543 12.891 22.422 13.801 22.184 14.684L 4.624 4.502C 6.102 3.052 7.976 2.07 10.01 1.679C 12.044 1.287 14.148 1.504 16.059 2.301C 17.971 3.098 19.605 4.442 20.759 6.162C 21.912 7.883 22.532 9.904 22.543 11.975Z"
            fill="currentColor"
          />
          <path
            opacity="0.3"
            d="M 3.222 17.794C 1.884 15.758 1.291 13.321 1.547 10.897C 1.802 8.474 2.89 6.214 4.624 4.503L 9.156 7.158V 14.369L 3.222 17.794ZM 17.505 11.976L 4.624 19.45C 5.935 20.752 7.566 21.686 9.353 22.159C 11.14 22.633 13.02 22.629 14.805 22.146C 16.589 21.663 18.215 20.719 19.519 19.41C 20.825 18.1 21.761 16.471 22.238 14.685L 17.505 11.976Z"
            fill="currentColor"
          />
        </motion.svg>
      </div>
    )
  }
)

CirclePlayIcon.displayName = "CirclePlayIcon"

export { CirclePlayIcon }
export default CirclePlayIcon
