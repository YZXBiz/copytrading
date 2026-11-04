import { MessageSquareIcon } from "lucide-react"
import { Button } from "@/components/ui/button"
import { FieldGroup } from "@/components/ui/field"
import { Spinner } from "@/components/ui/spinner"
import { CheckNotice } from "./CheckNotice"
import { EditorSheet } from "./EditorSheet"
import { TextField } from "./TextField"
import { connect, edit, keysOf, useSetup } from "./setup-store"
import { resultFor } from "./state"

/** The channels the gurus post in and the token CopyTrading reads them with. */
export function DiscordSheet({ onClose }: { onClose: () => void }) {
  const s = useSetup()
  const { draft } = s
  const saved = keysOf(s)?.discord
  const result = resultFor(s.checks, draft, "discord")
  return (
    <EditorSheet
      icon={MessageSquareIcon}
      title="Discord"
      description="Where your gurus post their calls. CopyTrading reads the channels as you."
      onClose={onClose}
      footer={
        <>
          <Button size="sm" type="button" variant="outline" disabled={result?.check === null} onClick={() => void connect("discord")}>
            {result?.check === null && <Spinner />}
            Connect
          </Button>
          <Button size="sm" type="button" onClick={onClose}>
            Done
          </Button>
        </>
      }
    >
      <FieldGroup>
        <TextField
          label="Channel IDs"
          hint="The channel each guru posts in. Separate several with commas."
          value={draft.channels}
          onChange={(channels) => edit((d) => ({ ...d, channels }))}
          placeholder="1517754775674949742"
          inputMode="numeric"        />
        <TextField
          label="Discord token"
          hint={saved ? "Kept encrypted on this Mac. Leave blank to keep the saved token." : "Kept encrypted on this Mac, never in the setup file."}
          value={draft.discord_token}
          onChange={(discord_token) => edit((d) => ({ ...d, discord_token }))}
          type="password"
          placeholder={saved ? "Saved" : "Required"}        />
        <TextField
          label="Only these users"
          hint="Optional. User IDs to read, when others post in the channel too."
          value={draft.authors}
          onChange={(authors) => edit((d) => ({ ...d, authors }))}
          placeholder="Anyone who posts"
          inputMode="numeric"        />
      </FieldGroup>
      <CheckNotice subject="discord" result={result} notice={s.notices.discord} />
    </EditorSheet>
  )
}
