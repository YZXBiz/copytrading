import { useState } from "react"
import { PaperclipIcon } from "lucide-react"
import type { SourceAttachmentEvidence } from "../../../shared/contract"
import { Attachment, AttachmentContent, AttachmentDescription, AttachmentMedia, AttachmentTitle } from "@/components/ui/attachment"
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
    <Attachment size="sm" className="self-start">
      <AttachmentMedia>
        <PaperclipIcon aria-hidden />
      </AttachmentMedia>
      <AttachmentContent>
        {attachment.filename && <AttachmentTitle>{attachment.filename}</AttachmentTitle>}
        <AttachmentDescription>{known === null ? state : `${size(known)} · ${state}`}</AttachmentDescription>
      </AttachmentContent>
    </Attachment>
  )
}
