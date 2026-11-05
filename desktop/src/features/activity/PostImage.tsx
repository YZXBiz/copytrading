import { useState } from "react"
import { AttachmentIcon } from "@/components/icons/AttachmentIcon"
import type { SourceAttachmentEvidence } from "../../../shared/contract"
import { codeWords } from "@/lib/reasons"
import styles from "./post-image.module.css"

const size = (bytes: number) => (bytes >= 1_000_000 ? `${(bytes / 1_000_000).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1000))} KB`)

/**
 * A captured picture, read by the main process from the engine's own folder and shown only when its size and
 * SHA-256 match the record (ct-picture://). When it cannot be shown, the file's name and state say so.
 */
export function PostImage({ attachment, compact = false }: { attachment: SourceAttachmentEvidence; compact?: boolean }) {
  const [failed, setFailed] = useState(false)
  if (attachment.status === "available" && !failed) {
    return (
      <img
        src={`ct-picture://${attachment.evidence_id}`}
        alt={attachment.filename || "A picture the guru posted"}
        onError={() => setFailed(true)}
        className={compact ? styles.compact : styles.picture}
      />
    )
  }
  const known = attachment.byte_size ?? (attachment.declared_size > 0 ? attachment.declared_size : null)
  const state = failed ? "Could not be shown" : codeWords(attachment.status)
  return (
    <span className={styles.missing}>
      <AttachmentIcon width={20} height={20} aria-hidden="true" />
      <span>
        {attachment.filename && <strong>{attachment.filename}</strong>}
        <span>{known === null ? state : `${state} (${size(known)})`}</span>
      </span>
    </span>
  )
}
