import { SettingsRow } from "./SettingsRow"
import { SettingsSection } from "./SettingsSection"
import { TimeZoneField } from "./TimeZoneField"

/** The time zone the app shows times in. The other General rows of the SwiftUI app are listed in the PR as not ported. */
export function GeneralPage() {
  return (
    <SettingsSection title="Time Zone">
      <SettingsRow title="Show times in" description="Post times, deadlines, and market hours use this zone.">
        <TimeZoneField />
      </SettingsRow>
    </SettingsSection>
  )
}
