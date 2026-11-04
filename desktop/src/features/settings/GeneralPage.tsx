import type { MenuBarMode, Theme } from "../../../shared/contract"
import { ChoiceField } from "./ChoiceField"
import { FillAlerts } from "./FillAlerts"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { TimeZoneField } from "./TimeZoneField"

/** The time zone the app shows times in, and whether trades are announced. The other General rows of the SwiftUI app are listed in the PR as not ported. */
const THEMES: { value: Theme; label: string }[] = [
  { value: "dark", label: "Dark" },
  { value: "light", label: "Light" },
  { value: "system", label: "System" },
]
const MENU_BAR: { value: MenuBarMode; label: string }[] = [
  { value: "balance", label: "Balance and dot" },
  { value: "dot", label: "Dot only" },
  { value: "off", label: "Off" },
]

export function GeneralPage() {
  return (
    <div className="flex flex-col gap-5">
      <SettingsSection title="Display">
        <ChoiceField title="Theme" items={THEMES} read={() => window.copytrading.read.getTheme()} write={(theme) => window.copytrading.act.setTheme({ theme })} />
        <ChoiceField title="Menu bar" items={MENU_BAR} read={() => window.copytrading.read.getMenuBar()} write={(mode) => window.copytrading.act.setMenuBar({ mode })} />
        <SettingsRow title="Show times in">
          <TimeZoneField />
        </SettingsRow>
      </SettingsSection>
      <FillAlerts />
    </div>
  )
}
