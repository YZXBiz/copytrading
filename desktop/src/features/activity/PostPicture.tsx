import { useState } from "react"
import { PaperclipIcon } from "lucide-react"
import type { SourceAttachmentEvidence } from "../../../shared/contract"
import { cn } from "@/lib/utils"
import { codeWords } from "./reasons"

const size = (bytes: number) => (bytes >= 1_000_000 ? `${(bytes / 1_000_000).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1000))} KB`)

/**
 * A captured picture, read by the main process from the engine's own folder and shown only when its size and
 * SHA-256 match the record (ct-picture://). When it cannot be shown, the file's name and state say so.
 */
export function PostPicture({ attachment, className }: { attachment: SourceAttachmentEvidence; className?: string }) {
  const [failed, setFailed] = useState(false)
  if (attachment.status === "available" && !failed) {
    return (
      <img
        src={`ct-picture://${attachment.evidence_id}`}
        alt={attachment.filename || "A picture the guru posted"}
        onError={() => setFailed(true)}
        className={cn("max-h-80 w-auto max-w-full self-start rounded-lg border", className)}
      />
    )
  }
  const known = attachment.byte_size ?? (attachment.declared_size > 0 ? attachment.declared_size : null)
  const state = failed ? "Could not be shown" : codeWords(attachment.status)
  return (
    <div className="flex items-start gap-2 text-sm">
      <PaperclipIcon aria-hidden className="text-muted-foreground mt-0.5 size-4 shrink-0" />
      <div className="min-w-0">
        {attachment.filename && <div className="break-words">{attachment.filename}</div>}
        <div className="text-muted-foreground text-xs">{known === null ? state : `${size(known)} · ${state}`}</div>
      </div>
    </div>
  )
}
