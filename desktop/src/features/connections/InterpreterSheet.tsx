import { SparklesIcon } from "@/components/icons/SparklesIcon"
import { Button } from "@/components/ui/button"
import { FieldGroup } from "@/components/ui/field"
import { Spinner } from "@/components/ui/spinner"
import { PROVIDER_GROUPS, PROVIDER_TITLES, acceptsBaseUrl, baseUrlProblem, requiresApiKey } from "../../../shared/providers"
import type { ProviderName } from "../../../shared/contract"
import { CheckNotice } from "./CheckNotice"
import { EditorSheet } from "./EditorSheet"
import { SelectField } from "./SelectField"
import { TextField } from "./TextField"
import { connect, edit, keysOf, pickProvider, useSetup } from "./setup-store"
import { resultFor } from "./state"

/** The AI model that reads each post: its service, model name, and key. */
export function InterpreterSheet({ onClose }: { onClose: () => void }) {
  const s = useSetup()
  const { draft } = s
  const keySaved = keysOf(s)?.providerKey
  const result = resultFor(s.checks, draft, "interpreter")
  const address = draft.base_url ? baseUrlProblem(draft.provider, draft.base_url) : null
  return (
    <EditorSheet
      icon={SparklesIcon}
      title="Interpreter"
      description="A service uses your own key and bills you for what it reads; a model on this Mac costs nothing."
      onClose={onClose}
      footer={
        <>
          <Button size="sm" type="button" variant="outline" disabled={result?.check === null} onClick={() => void connect("interpreter")}>
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
        <SelectField
          label="Service"
          value={draft.provider}
          groups={PROVIDER_GROUPS.map((g) => ({ title: g.title, choices: g.providers.map((p) => ({ value: p, label: PROVIDER_TITLES[p] })) }))}
          onChange={(provider) => pickProvider(provider as ProviderName)}        />
        <TextField
          label="Model"
          hint="The model's name, as the service writes it."
          value={draft.model}
          onChange={(model) => edit((d) => ({ ...d, model }))}        />
        {acceptsBaseUrl(draft.provider) && (
          <TextField
            label="Base URL"
            hint={draft.provider === "ollama" ? "Optional. Where Ollama listens; blank uses this Mac's default." : "Where your model is served."}
            error={address}
            value={draft.base_url}
            onChange={(base_url) => edit((d) => ({ ...d, base_url }))}
            placeholder="http://localhost:11434"          />
        )}
        {requiresApiKey(draft.provider) && (
          <TextField
            label="API key"
            hint={keySaved ? "Kept encrypted on this Mac. Leave blank to keep the saved key." : "Kept encrypted on this Mac, never in the setup file."}
            value={draft.provider_api_key}
            onChange={(provider_api_key) => edit((d) => ({ ...d, provider_api_key }))}
            type="password"
            placeholder={keySaved ? "Saved" : "Required"}          />
        )}
      </FieldGroup>
      <CheckNotice
        subject="interpreter"
        result={result}
        notice={s.notices.interpreter}
        modelName={draft.model}
        useModel={(model) => edit((d) => ({ ...d, model }))}
      />
    </EditorSheet>
  )
}
