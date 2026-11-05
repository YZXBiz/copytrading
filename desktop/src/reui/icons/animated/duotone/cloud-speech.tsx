import type { HTMLAttributes } from "react"
import { forwardRef, useCallback, useImperativeHandle, useRef } from "react"
import type { Variants } from "motion/react"
import { motion, useAnimation } from "motion/react"

import { cn } from "cn"

export interface CloudSpeechIconHandle {
  startAnimation: () => void
  stopAnimation: () => void
}

interface CloudSpeechIconProps extends HTMLAttributes<HTMLDivElement> {}

const CLOUD_TOP_JELLY_VARIANTS: Variants = {
  normal: {
    x: 0,
    y: 0,
    scaleX: 1,
    scaleY: 1,
    skewX: 0,
    rotate: 0,
    transition: { duration: 0.22, ease: "easeOut" },
  },
  animate: {
    x: [0, -0.75, 1.15, -0.7, 0.28, 0],
    y: [0, 0.28, -0.18, 0.12, -0.05, 0],
    scaleX: [1, 1.08, 0.93, 1.05, 0.985, 1],
    scaleY: [1, 0.92, 1.08, 0.965, 1.018, 1],
    skewX: [0, -9.5, 7, -4.2, 1.5, 0],
    rotate: [0, -2.8, 2.2, -1.1, 0.35, 0],
    transition: {
      duration: 0.58,
      ease: "easeInOut",
      times: [0, 0.16, 0.34, 0.56, 0.78, 1],
    },
  },
}

const CloudSpeechIcon = forwardRef<CloudSpeechIconHandle, CloudSpeechIconProps>(
  ({ onMouseEnter, onMouseLeave, className, ...props }, ref) => {
    const controls = useAnimation()
    const isControlledRef = useRef(false)

    useImperativeHandle(ref, () => {
      isControlledRef.current = true
      return {
        startAnimation: () => controls.start("animate"),
        // Each hover fires ONE complete cycle that runs start-to-finish and
        // returns to rest on its own; the gallery calls stopAnimation() on
        // mouse-leave, so a no-op here keeps that cycle from being
        // interrupted or reversed. The "animate" variant must end at rest.
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
          // no reset on leave; the in-flight cycle completes on its own
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
          <motion.path
            opacity="0.3"
            d="M20.05 9.22258H19.8315C19.9718 8.84901 20.0458 8.45309 20.05 8.05323C20.05 7.12284 19.6865 6.23055 19.0395 5.57266C18.3925 4.91478 17.515 4.54518 16.6 4.54518C15.9107 4.54707 15.2378 4.75886 14.668 5.15324C14.0336 4.04612 13.0591 3.18157 11.8943 2.69255C10.7295 2.20353 9.43902 2.11712 8.22125 2.44661C7.00348 2.77611 5.92587 3.50326 5.15417 4.51623C4.38246 5.52921 3.95938 6.77191 3.95 8.05323C3.95366 8.44574 3.99215 8.83711 4.065 9.22258H3.95C3.035 9.22258 2.15748 9.59218 1.51048 10.2501C0.863481 10.908 0.5 11.8002 0.5 12.7306C0.5 13.661 0.863481 14.5533 1.51048 15.2112C2.15748 15.8691 3.035 16.2387 3.95 16.2387H8.55L13.656 21.4306C13.8017 21.5818 13.9885 21.6854 14.1924 21.7281C14.3963 21.7708 14.6081 21.7507 14.8007 21.6704C14.9933 21.59 15.158 21.4531 15.2737 21.277C15.3893 21.101 15.4507 20.8939 15.45 20.6822V16.2387H20.05C20.965 16.2387 21.8425 15.8691 22.4895 15.2112C23.1365 14.5533 23.5 13.661 23.5 12.7306C23.5 11.8002 23.1365 10.908 22.4895 10.2501C21.8425 9.59218 20.965 9.22258 20.05 9.22258Z"
            fill="currentColor"
            variants={CLOUD_TOP_JELLY_VARIANTS}
            animate={controls}
            style={{
              transformBox: "view-box",
              transformOrigin: "12px 21.7px",
              originX: 0.5,
              originY: 0.904,
            }}
          />
        </svg>
      </div>
    )
  }
)

CloudSpeechIcon.displayName = "CloudSpeechIcon"

export { CloudSpeechIcon }
export default CloudSpeechIcon
