import { WalletIcon, RefreshCwIcon, MoreHorizontalIcon, ChevronsUpDownIcon, MinusIcon, DownloadIcon, TableIcon, FileTextIcon, Undo2Icon, TrendingUp, TrendingDown, HistoryIcon, CircleCheckIcon, AlertCircleIcon } from "lucide-react";

/** Chrome glyphs, unsized: the owning Button, menu item or tile sizes them. */
// prettier-ignore
export const UI_ICONS = {
  wallet:    <WalletIcon aria-hidden="true" />,
  refresh:   <RefreshCwIcon aria-hidden="true" />,
  more:      <MoreHorizontalIcon aria-hidden="true" />,
  markers:   <ChevronsUpDownIcon aria-hidden="true" />,
  average:   <MinusIcon aria-hidden="true" />,
  download:  <DownloadIcon aria-hidden="true" />,
  table:     <TableIcon aria-hidden="true" />,
  summary:   <FileTextIcon aria-hidden="true" />,
  reset:     <Undo2Icon aria-hidden="true" />,
}

/** Tooltip row glyphs at the house glyph size, for a row's 16px slot. */
// prettier-ignore
export const ROW_ICONS = {
  up:    <TrendingUp className="size-4" aria-hidden="true" />,
  down:  <TrendingDown className="size-4" aria-hidden="true" />,
  since: <HistoryIcon className="size-4" aria-hidden="true" />,
}

/** The trend glyphs at badge size: the Badge sizes its own icons. */
// prettier-ignore
export const BADGE_TREND_ICONS = {
  up:   <TrendingUp aria-hidden="true" />,
  down: <TrendingDown aria-hidden="true" />,
}

export const TOAST_SUCCESS_ICON = (
  <CircleCheckIcon className="text-success size-4" aria-hidden="true" />
)

export const TOAST_ERROR_ICON = (
  <AlertCircleIcon className="text-destructive size-4" aria-hidden="true" />
)
