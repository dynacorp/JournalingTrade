import { format } from "date-fns";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { ChartSnapshotListItem } from "@/hooks/use-chart-snapshots";
import { TrendingUp, TrendingDown, Minus, Clock, CheckCircle, XCircle, AlertCircle, Trash2 } from "lucide-react";

interface SetupQueueProps {
  snapshots: ChartSnapshotListItem[];
  onSelectSnapshot: (snapshot: ChartSnapshotListItem) => void;
  selectedId?: number;
}

const statusConfig: Record<string, { icon: React.ElementType; color: string; label: string }> = {
  pending: { icon: Clock, color: "text-yellow-500", label: "Pending" },
  pre_analyzed: { icon: Clock, color: "text-yellow-500", label: "Pre-Analyzed" },
  queued_for_review: { icon: AlertCircle, color: "text-blue-500", label: "Review" },
  approved: { icon: AlertCircle, color: "text-blue-500", label: "Approved" },
  analyzed: { icon: CheckCircle, color: "text-emerald-500", label: "Analyzed" },
  no_setup: { icon: XCircle, color: "text-muted-foreground", label: "No Setup" },
  discarded: { icon: Trash2, color: "text-destructive", label: "Discarded" },
};

const biasConfig: Record<string, { icon: React.ElementType; color: string }> = {
  bullish: { icon: TrendingUp, color: "text-emerald-500" },
  bearish: { icon: TrendingDown, color: "text-red-500" },
  neutral: { icon: Minus, color: "text-muted-foreground" },
};

export function SetupQueue({ snapshots, onSelectSnapshot, selectedId }: SetupQueueProps) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
      {snapshots.map((snapshot) => {
        const status = statusConfig[snapshot.status] || statusConfig.pending;
        const bias = biasConfig[snapshot.pre_analysis_bias || "neutral"];
        const StatusIcon = status.icon;
        const BiasIcon = bias.icon;
        const isSelected = selectedId === snapshot.id;
        const score = snapshot.confluence_score ?? snapshot.pre_analysis_score ?? 0;

        return (
          <Card
            key={snapshot.id}
            onClick={() => onSelectSnapshot(snapshot)}
            className={cn(
              "cursor-pointer transition-all hover:shadow-md hover:border-primary/50",
              isSelected && "ring-2 ring-primary border-primary"
            )}
          >
            <CardContent className="p-4">
              {/* Header */}
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <Badge variant="outline" className="font-mono font-bold">
                    {snapshot.symbol}
                  </Badge>
                  <Badge variant="secondary" className="text-xs">
                    {snapshot.timeframe}
                  </Badge>
                </div>
                <div className={cn("flex items-center gap-1", status.color)}>
                  <StatusIcon className="w-4 h-4" />
                </div>
              </div>

              {/* Score Bar */}
              <div className="mb-3">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs text-muted-foreground">Confluence Score</span>
                  <span className={cn(
                    "text-sm font-bold",
                    score >= 70 ? "text-emerald-500" :
                    score >= 50 ? "text-yellow-500" : "text-muted-foreground"
                  )}>
                    {score.toFixed(0)}
                  </span>
                </div>
                <div className="h-1.5 bg-secondary rounded-full overflow-hidden">
                  <div
                    className={cn(
                      "h-full rounded-full transition-all",
                      score >= 70 ? "bg-emerald-500" :
                      score >= 50 ? "bg-yellow-500" : "bg-muted-foreground"
                    )}
                    style={{ width: `${score}%` }}
                  />
                </div>
              </div>

              {/* Bias & Direction */}
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-1.5">
                  <BiasIcon className={cn("w-4 h-4", bias.color)} />
                  <span className="text-sm capitalize">{snapshot.pre_analysis_bias || "—"}</span>
                </div>
                {snapshot.trade_direction && snapshot.trade_direction !== "none" && (
                  <Badge
                    variant={snapshot.trade_direction === "long" ? "default" : "destructive"}
                    className="text-xs"
                  >
                    {snapshot.trade_direction.toUpperCase()}
                  </Badge>
                )}
              </div>

              {/* Summary */}
              {snapshot.pre_analysis_summary && (
                <p className="text-xs text-muted-foreground line-clamp-2 mb-3">
                  {snapshot.pre_analysis_summary}
                </p>
              )}

              {/* Footer */}
              <div className="flex items-center justify-between text-xs text-muted-foreground pt-2 border-t border-border">
                <span>{format(new Date(snapshot.snapshot_time), "MMM d, HH:mm")}</span>
                {snapshot.is_journal_candidate && (
                  <Badge variant="outline" className="text-[10px] px-1.5 py-0 border-primary text-primary">
                    Journal
                  </Badge>
                )}
                {snapshot.linked_trade_id && (
                  <Badge variant="outline" className="text-[10px] px-1.5 py-0">
                    Linked
                  </Badge>
                )}
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
