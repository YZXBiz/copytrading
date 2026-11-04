// How an answer's light Markdown reads (AssistantMarkdown.swift): bold, italics and code; "- " lines become bullets and
// "# " headings bold, while a "#NVDA" ticker tag stays as written. Answers can quote what other people wrote, so
// nothing in them is a link, and nothing is ever HTML: the output is text runs that React escapes.

export interface Run {
  text: string
  bold?: boolean
  italic?: boolean
  code?: boolean
}

/** One line as runs: a bullet, a bold heading, or the line unchanged. */
export function parseLine(line: string): Run[] {
  const trimmed = line.replace(/^ +/, "")
  if (/^[-*] /.test(trimmed)) return [{ text: "• " }, ...inline(trimmed.slice(2))]
  const heading = /^#{1,6} (.*)$/.exec(trimmed)
  if (heading) return heading[1]!.trim() ? [{ text: heading[1]!.trim(), bold: true }] : []
  return inline(line)
}

// `code`, **bold**, *italic* or _italic_ (not inside a word, so snake_case stays), and [text](url), which keeps only its text.
const TOKEN = /`([^`\n]+)`|\*\*([^*\n]+)\*\*|\*([^*\n]+)\*|(?<![\p{L}\p{N}])_([^_\n]+)_(?![\p{L}\p{N}])|\[([^\]\n]*)\]\((?:[^()\n]|\([^()\n]*\))*\)/gu

function inline(text: string): Run[] {
  const runs: Run[] = []
  let from = 0
  for (const match of text.matchAll(TOKEN)) {
    if (match.index > from) runs.push({ text: text.slice(from, match.index) })
    const [, code, bold, star, underscore, link] = match
    if (code !== undefined) runs.push({ text: code, code: true })
    else if (bold !== undefined) runs.push({ text: bold, bold: true })
    else if (star !== undefined || underscore !== undefined) runs.push({ text: (star ?? underscore)!, italic: true })
    else runs.push({ text: link ?? "" })
    from = match.index + match[0].length
  }
  if (from < text.length) runs.push({ text: text.slice(from) })
  return runs
}

/** An answer as lines of runs. */
export const parseMarkdown = (text: string): Run[][] => text.split("\n").map(parseLine)
