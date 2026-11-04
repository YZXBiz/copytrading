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
            d="M 22.17 14.662C 22.612 12.967 22.625 11.189 22.205 9.488C 21.786 7.786 20.949 6.217 19.77 4.922C 18.59 3.627 17.106 2.648 15.452 2.072C 13.798 1.497 12.027 1.344 10.299 1.627C 8.571 1.911 6.941 2.622 5.558 3.696C 4.174 4.769 3.081 6.172 2.377 7.776C 1.672 9.38 1.38 11.135 1.525 12.881C 1.671 14.627 2.25 16.309 3.211 17.773C 3.281 17.873 3.372 17.954 3.479 18.01C 3.586 18.066 3.706 18.095 3.827 18.096C 3.954 18.098 4.079 18.064 4.188 17.998L 9.704 14.819C 9.813 14.752 9.904 14.659 9.967 14.548C 10.03 14.437 10.064 14.311 10.065 14.182V 8.754L 15.648 11.963L 4.746 18.263C 4.651 18.319 4.569 18.397 4.508 18.491C 4.447 18.584 4.408 18.69 4.394 18.801C 4.379 18.912 4.39 19.025 4.426 19.132C 4.462 19.239 4.521 19.336 4.599 19.417C 5.905 20.728 7.533 21.672 9.32 22.152C 11.107 22.632 12.988 22.631 14.774 22.149C 16.561 21.667 18.188 20.722 19.492 19.409C 20.796 18.096 21.729 16.462 22.2 14.672L 22.17 14.662ZM 12.011 2.914C 13.315 2.911 14.605 3.191 15.79 3.734C 16.976 4.278 18.03 5.072 18.879 6.062C 19.729 7.052 20.353 8.215 20.71 9.47C 21.067 10.725 21.148 12.043 20.948 13.332L 17.487 11.326L 6.359 4.899C 7.959 3.607 9.955 2.906 12.011 2.914ZM 8.637 13.752L 4.12 16.375C 3.201 14.736 2.816 12.851 3.02 10.983C 3.223 9.115 4.005 7.358 5.255 5.956L 8.637 7.912V 13.752ZM 12.011 21.011C 9.959 21.027 7.963 20.336 6.359 19.055L 17.115 12.843L 20.586 14.849C 19.985 16.646 18.832 18.209 17.294 19.315C 15.754 20.421 13.906 21.015 12.011 21.011Z"
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
