"use client"

import type { HTMLAttributes } from "react"
import { forwardRef, useCallback, useImperativeHandle, useRef } from "react"
import { cn } from "cn"
import type { Variants } from "motion/react"
import { motion, useAnimation } from "motion/react"

export interface SquareInCircleIconHandle {
  startAnimation: () => void
  stopAnimation: () => void
}

interface SquareInCircleIconProps extends HTMLAttributes<HTMLDivElement> {}

const GROUP_VARIANTS: Variants = {
  normal: { scale: 1, y: 0, transition: { duration: 0.3, ease: "easeOut" } },
  animate: {
    scale: [1, 0.8, 1.1, 0.96, 1],
    y: [0, 2, -0.5, 0, 0],
    transition: {
      duration: 0.5,
      ease: "easeOut",
      times: [0, 0.25, 0.55, 0.78, 1],
    },
  },
}

const SquareInCircleIcon = forwardRef<
  SquareInCircleIconHandle,
  SquareInCircleIconProps
>(({ onMouseEnter, onMouseLeave, className, ...props }, ref) => {
  const controls = useAnimation()
  const isControlledRef = useRef(false)

  useImperativeHandle(ref, () => {
    isControlledRef.current = true
    return {
      startAnimation: () => controls.start("animate"),
      stopAnimation: () => {},
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
        // no reset on leave; the cycle completes on its own
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
      <svg
        width="100%"
        height="100%"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        overflow="visible"
      >
        <motion.g variants={GROUP_VARIANTS} animate={controls}>
          <path
            opacity="0.3"
            d="M 12 22.339C 17.71 22.339 22.339 17.71 22.339 12C 22.339 6.29 17.71 1.661 12 1.661C 6.29 1.661 1.661 6.29 1.661 12C 1.661 17.71 6.29 22.339 12 22.339Z"
            fill="currentColor"
          />
          <path
            d="M 16.136 15.102V 8.898C 16.136 8.328 15.673 7.864 15.102 7.864L 8.898 7.864C 8.328 7.864 7.864 8.328 7.864 8.898V 15.102C 7.864 15.673 8.328 16.136 8.898 16.136H 15.102C 15.673 16.136 16.136 15.673 16.136 15.102Z"
            fill="currentColor"
          />
        </motion.g>
      </svg>
    </div>
  )
})

SquareInCircleIcon.displayName = "SquareInCircleIcon"

export { SquareInCircleIcon }
export default SquareInCircleIcon
