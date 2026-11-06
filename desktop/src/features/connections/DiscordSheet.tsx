import { Message01Icon } from "@/components/icons/Message01Icon"
import { Button } from "@/components/arc/button/button"
import { ConnectionCheck } from "./ConnectionCheck"
import { EditorSheet } from "./EditorSheet"
import { TextField } from "./TextField"
import { edit, keysOf, useSetup } from "./setup-store"
import styles from "./connections.module.css"

/** The channels the gurus post in and the token CopyTrading reads them with. */
export function DiscordSheet({ onClose }: { onClose: () => void }) {
  const s = useSetup()
  const { draft } = s
  const saved = keysOf(s)?.discord
  return (
    <EditorSheet
      title="Discord"
      description="Where your gurus post their calls. CopyTrading reads the channels as you."
      onClose={onClose}
      footer={
        <div className={styles.footerEnd}>
          <Button size="sm" type="button" onClick={onClose}>
            Done
          </Button>
        </div>
      }
    >
      <div className={styles.fields}>
        <TextField
          label="Channel IDs"
          hint="The channel each guru posts in. Separate several with commas."
          value={draft.channels}
          onChange={(channels) => edit((d) => ({ ...d, channels }))}
          placeholder="1517754775674949742"
          inputMode="numeric"
        />
        <TextField
          label="Discord token"
          hint={saved ? "Kept encrypted on this Mac. Leave blank to keep the saved token." : "Kept encrypted on this Mac, never in the setup file."}
          value={draft.discord_token}
          onChange={(discord_token) => edit((d) => ({ ...d, discord_token }))}
          type="password"
          placeholder={saved ? "Saved" : "Required"}
        />
        <TextField
          label="Only these users"
          hint="Optional. User IDs to read, when others post in the channel too."
          value={draft.authors}
          onChange={(authors) => edit((d) => ({ ...d, authors }))}
          placeholder="Anyone who posts"
          inputMode="numeric"
        />
      </div>
      <ConnectionCheck subject="discord" name="Discord" icon={Message01Icon} description="Signs in with your token and reads the channels above." />
    </EditorSheet>
  )
}
