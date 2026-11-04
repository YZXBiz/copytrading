import type { TradingValidation } from "../../../shared/contract"
import { Badge } from "@/components/reui/badge"
import { Frame, FrameDescription, FrameHeader, FramePanel, FrameTitle } from "@/components/reui/frame"
import { Item, ItemActions, ItemContent, ItemDescription, ItemGroup, ItemTitle } from "@/components/ui/item"
import { checkDetail, checkTitle } from "./words"

/** Each connection and what its test found, with what to do about a failure (ValidationResultsSection.swift). */
export function CheckResults({ report, modelName }: { report: TradingValidation["report"]; modelName: string }) {
  return (
    <Frame spacing="sm">
      <FrameHeader>
        <FrameTitle>Connection checks</FrameTitle>
        <FrameDescription>{report.cost_notice}</FrameDescription>
      </FrameHeader>
      <FramePanel>
        <ItemGroup>
          {report.checks.map((check, index) => {
            const detail = checkDetail(check, modelName)
            return (
              <Item key={`${check.name}:${check.subject ?? index}`} variant="outline" size="xs" role="listitem">
                <ItemContent>
                  <ItemTitle>{checkTitle(check)}</ItemTitle>
                  {detail && <ItemDescription className={check.state === "failed" ? "text-destructive" : undefined}>{detail}</ItemDescription>}
                </ItemContent>
                <ItemActions>
                  <Badge variant={check.state === "ready" ? "success-light" : check.state === "failed" ? "warning-light" : "outline"}>
                    {check.state === "ready" ? "Ready" : check.state === "failed" ? "Needs attention" : "Not configured"}
                  </Badge>
                </ItemActions>
              </Item>
            )
          })}
        </ItemGroup>
      </FramePanel>
    </Frame>
  )
}
