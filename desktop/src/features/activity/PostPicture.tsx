import { useState } from "react"
import { AttachmentIcon } from "@/components/icons/AttachmentIcon"
import type { SourceAttachmentEvidence } from "../../../shared/contract"
import { codeWords } from "@/lib/reasons"
import { cn } from "@/lib/utils"

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
    <div className="flex items-center gap-2 self-start rounded-lg border px-3 py-2 text-sm">
      <AttachmentIcon width={16} height={16} aria-hidden className="shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        {attachment.filename && <div className="truncate">{attachment.filename}</div>}
        <div className="text-muted-foreground">{known === null ? state : `${state} (${size(known)})`}</div>
      </div>
    </div>
  )
}
