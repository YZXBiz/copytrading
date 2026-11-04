import { FillAlerts } from "./FillAlerts"
import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { TimeZoneField } from "./TimeZoneField"

/** The time zone the app shows times in, and whether trades are announced. The other General rows of the SwiftUI app are listed in the PR as not ported. */
export function GeneralPage() {
  return (
<<<<<<< HEAD
    <div className="flex flex-col gap-6">
      <SettingsSection title="Time Zone">
        <SettingsRow title="Show times in" description="Post times, deadlines, and market hours use this zone.">
          <TimeZoneField />
        </SettingsRow>
      </SettingsSection>
      <FillAlerts />
    </div>
=======
    <SettingsSection>
      <SettingsRow title="Show times in">
        <TimeZoneField />
      </SettingsRow>
    </SettingsSection>
>>>>>>> a3473fc2 (React visual polish: ReUI house layout, no secondary labels, Hallmark floor)
  )
}
