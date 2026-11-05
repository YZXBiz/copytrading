import { Tick02Icon } from "@/components/icons/Tick02Icon"
import { Stepper, StepperDescription, StepperIndicator, StepperItem, StepperNav, StepperSeparator, StepperTitle, StepperTrigger } from "@/components/reui/stepper"

// The vertical rail of ReUI's onboarding-2 (Sidebar Stepper Wizard), classes as shipped. Its compact rail for phones is
// left out: the window never gets that narrow.
const INDICATOR_CLASSNAME =
  "bg-foreground text-background ring-border/60 data-[state=active]:bg-foreground data-[state=active]:text-background data-[state=inactive]:bg-muted-foreground/8 data-[state=inactive]:text-muted-foreground data-[state=inactive]:ring-muted-foreground/12 data-[state=completed]:bg-success dark:bg-foreground dark:data-[state=completed]:bg-success dark:text-background dark:ring-border/70 dark:data-[state=active]:bg-foreground dark:data-[state=active]:text-background dark:data-[state=inactive]:bg-muted-foreground/14 dark:data-[state=inactive]:text-muted-foreground dark:data-[state=inactive]:ring-muted-foreground/12 size-5 text-[0.6875rem] ring-1 data-[state=completed]:text-white"

const SEPARATOR_COLOR_CLASSNAME =
  "bg-muted-foreground/12 group-data-[state=active]/step:bg-muted-foreground/12 group-data-[state=inactive]/step:bg-muted-foreground/12 group-data-[state=completed]/step:bg-success dark:bg-muted-foreground/18 dark:group-data-[state=active]/step:bg-muted-foreground/18 dark:group-data-[state=inactive]/step:bg-muted-foreground/18"

const COMPLETED_INDICATOR = <Tick02Icon className="size-3" aria-hidden="true" />

/** One setup step. A step is done when its own work is, so steps need not finish in order. */
export interface OnboardingStep {
  id: string
  value: number
  label: string
  description: string
  done: boolean
}

export function OnboardingStepper({
  currentStep,
  onStepChange,
  steps,
  panelId,
}: {
  currentStep: number
  onStepChange: (step: number) => void
  steps: OnboardingStep[]
  /** The panel the selected step shows, for `aria-controls`. */
  panelId: string
}) {
  return (
    <Stepper
      value={currentStep}
      onValueChange={onStepChange}
      orientation="vertical"
      className="flex w-full flex-col items-start justify-center gap-0"
      indicators={{ completed: COMPLETED_INDICATOR }}
    >
      <StepperNav aria-label="Setup steps" className="w-full">
        {steps.map((step) => (
          <StepperItem key={step.id} step={step.value} completed={step.done} className="relative items-start not-last:flex-1">
            <StepperTrigger aria-controls={panelId} className="w-full items-start gap-2.5 pb-4 text-left last:pb-0">
              <StepperIndicator className={INDICATOR_CLASSNAME}>{step.value}</StepperIndicator>
              <div className="mt-0.5 min-w-0 flex-1 text-left">
                <StepperTitle className="!text-[0.8125rem] !leading-4">{step.label}</StepperTitle>
                <StepperDescription className="mt-0.5 max-w-none !text-xs !leading-4">{step.description}</StepperDescription>
              </div>
              {step.done && <span className="sr-only">Done</span>}
            </StepperTrigger>
            {step.value < steps.length ? (
              <StepperSeparator className={`${SEPARATOR_COLOR_CLASSNAME} absolute inset-y-0 top-6 left-2.5 -order-1 m-0 !h-[calc(100%-1.75rem)] -translate-x-1/2`} />
            ) : null}
          </StepperItem>
        ))}
      </StepperNav>
    </Stepper>
  )
}
