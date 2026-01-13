import { 
  Sheet, 
  SheetContent, 
} from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Trade } from "@/lib/mock-data";
import { format } from "date-fns";
import { Sparkles, AlertTriangle, CheckCircle2, TrendingDown, Target, ShieldAlert } from "lucide-react";
import { cn } from "@/lib/utils";
import { Progress } from "@/components/ui/progress";

interface TradeDetailProps {
  trade: Trade | null;
  isOpen: boolean;
  onClose: () => void;
}

export function TradeDetail({ trade, isOpen, onClose }: TradeDetailProps) {
  if (!trade) return null;

  const isWin = trade.netPnl > 0;
  
  // Calculate percentages for the drawdown visualization
  // Total range = Risk + MFE (visualize the full excursion of the trade)
  const maeRatio = Math.min(trade.mae / trade.risk, 1.2); // Cap at 120% for visual
  const mfeRatio = trade.mfe / trade.risk;
  
  const maePercent = Math.round(maeRatio * 100);

  return (
    <Sheet open={isOpen} onOpenChange={onClose}>
      <SheetContent className="w-full sm:max-w-xl p-0 gap-0 border-l-border">
        <ScrollArea className="h-full">
          {/* Header */}
          <div className="p-6 border-b border-border bg-card/50">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <Badge variant={trade.side === "BUY" ? "default" : "destructive"} className="px-2 py-0.5 text-xs font-bold uppercase tracking-wider">
                  {trade.side}
                </Badge>
                <h2 className="text-2xl font-mono font-bold tracking-tight">{trade.symbol}</h2>
              </div>
              <div className="text-right">
                <div className={`text-2xl font-mono font-bold ${isWin ? "text-profit" : "text-loss"}`}>
                  {isWin ? "+" : ""}{trade.netPnl.toFixed(2)}
                </div>
                <div className="text-xs text-muted-foreground">Net P&L</div>
              </div>
            </div>
            
            <div className="grid grid-cols-4 gap-4 mt-6">
              <div>
                <div className="text-xs text-muted-foreground mb-1 uppercase tracking-wider">Volume</div>
                <div className="font-mono font-medium">{trade.volume}</div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground mb-1 uppercase tracking-wider">Entry</div>
                <div className="font-mono font-medium">{trade.entry_price.toFixed(4)}</div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground mb-1 uppercase tracking-wider">Exit</div>
                <div className="font-mono font-medium">{trade.closePrice.toFixed(4)}</div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground mb-1 uppercase tracking-wider">R-Mult</div>
                <div className={cn("font-mono font-medium", isWin ? "text-profit" : "text-loss")}>
                  {(trade.pnl / 100).toFixed(1)}R
                </div>
              </div>
            </div>
          </div>

          {/* Drawdown & MAE Analysis (New Section) */}
          <div className="p-6 border-b border-border">
            <div className="flex items-center gap-2 mb-4 text-foreground">
              <ShieldAlert className="w-4 h-4 text-primary" />
              <h3 className="text-sm font-semibold uppercase tracking-wider">Drawdown Analysis (MAE)</h3>
            </div>

            <div className="space-y-6">
              {/* Visual Bar */}
              <div className="space-y-2">
                <div className="flex justify-between text-xs font-medium">
                  <span className="text-muted-foreground">Entry</span>
                  <span className="text-destructive">Stop Loss Risk ({trade.risk} pts)</span>
                </div>
                
                {/* Custom Risk Meter */}
                <div className="relative h-4 bg-muted rounded-full overflow-hidden w-full">
                  {/* Heat Bar (MAE) */}
                  <div 
                    className={cn(
                      "absolute top-0 left-0 h-full transition-all duration-500 rounded-full",
                      maeRatio > 1 ? "bg-destructive" : // Hit SL
                      maeRatio > 0.8 ? "bg-orange-500" : // High heat
                      maeRatio > 0.5 ? "bg-yellow-500" : // Moderate heat
                      "bg-emerald-500" // Low heat (Sniper entry)
                    )}
                    style={{ width: `${Math.min(maePercent, 100)}%` }}
                  />
                  
                  {/* Stop Loss Marker Line */}
                  <div className="absolute top-0 right-0 w-0.5 h-full bg-destructive z-10" />
                </div>

                <div className="flex justify-between items-start text-xs font-mono pt-1">
                  <div>
                    <span className="text-muted-foreground">Max Adverse: </span>
                    <span className={cn(
                      "font-bold",
                      maeRatio > 0.8 ? "text-destructive" : "text-foreground"
                    )}>
                      {trade.mae} pts ({maePercent}%)
                    </span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Max Favorable: </span>
                    <span className="text-profit font-bold">
                      {trade.mfe} pts
                    </span>
                  </div>
                </div>
              </div>

              {/* Interpretation Box */}
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-accent/30 rounded-lg p-3 border border-border">
                  <div className="text-xs text-muted-foreground uppercase tracking-wider mb-1">Drawdown Efficiency</div>
                  <div className="text-sm font-medium">
                    {maeRatio < 0.2 ? "sniper entry (no heat)" :
                     maeRatio < 0.5 ? "Clean entry (normal noise)" :
                     maeRatio < 0.9 ? "Heavy drawdown (held thru)" :
                     "Stopped out / Failed"}
                  </div>
                </div>
                <div className="bg-accent/30 rounded-lg p-3 border border-border">
                   <div className="text-xs text-muted-foreground uppercase tracking-wider mb-1">Excursion Ratio</div>
                   <div className="text-sm font-medium font-mono">
                     1:{ (trade.mfe / (trade.mae || 1)).toFixed(1) }
                   </div>
                </div>
              </div>
            </div>
          </div>

          {/* AI Analysis Section */}
          <div className="p-6 bg-accent/20 border-b border-border">
            <div className="flex items-center gap-2 mb-4 text-primary">
              <Sparkles className="w-4 h-4" />
              <h3 className="text-sm font-semibold uppercase tracking-wider">AI Trade Analysis</h3>
            </div>
            
            {trade.aiSummary ? (
              <div className="space-y-4">
                <div className="bg-card border border-border rounded-lg p-4 shadow-sm">
                  <div className="flex items-start gap-3">
                    {trade.aiSummary.execution === "Good" ? (
                      <CheckCircle2 className="w-5 h-5 text-profit mt-0.5" />
                    ) : trade.aiSummary.execution === "Bad" ? (
                      <AlertTriangle className="w-5 h-5 text-loss mt-0.5" />
                    ) : (
                      <div className="w-5 h-5 rounded-full border-2 border-muted-foreground mt-0.5" />
                    )}
                    <div>
                      <h4 className="font-medium text-sm mb-1">{trade.aiSummary.summary}</h4>
                      {trade.aiSummary.mistake && (
                        <p className="text-xs text-loss mt-2 flex items-center gap-1.5 font-medium bg-loss/10 p-2 rounded">
                          <AlertTriangle className="w-3 h-3" />
                          Mistake: {trade.aiSummary.mistake}
                        </p>
                      )}
                      {trade.aiSummary.improvement && (
                        <p className="text-xs text-muted-foreground mt-2 italic">
                          "Tip: {trade.aiSummary.improvement}"
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <div className="text-sm text-muted-foreground italic text-center py-4">
                Analysis pending...
              </div>
            )}
          </div>

          {/* Details */}
          <div className="p-6 space-y-8">
            <div className="space-y-3">
              <h3 className="text-sm font-medium text-muted-foreground uppercase tracking-wider">Trade Setup & Tags</h3>
              <div className="flex flex-wrap gap-2">
                <Badge variant="outline" className="bg-background">{trade.setup}</Badge>
                {trade.tags.map(tag => (
                  <Badge key={tag} variant="secondary" className="opacity-80">{tag}</Badge>
                ))}
              </div>
            </div>

            <div className="space-y-3">
              <h3 className="text-sm font-medium text-muted-foreground uppercase tracking-wider">Manual Notes</h3>
              <div className="p-4 rounded-md bg-muted/30 border border-border text-sm leading-relaxed font-mono">
                {trade.notes}
              </div>
            </div>

            <div className="space-y-3">
              <h3 className="text-sm font-medium text-muted-foreground uppercase tracking-wider">Execution Data</h3>
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="flex justify-between py-2 border-b border-border border-dashed">
                  <span className="text-muted-foreground">Open Time</span>
                  <span className="font-mono">{format(new Date(trade.openTime), "MMM d, HH:mm:ss")}</span>
                </div>
                <div className="flex justify-between py-2 border-b border-border border-dashed">
                  <span className="text-muted-foreground">Close Time</span>
                  <span className="font-mono">{format(new Date(trade.closeTime), "MMM d, HH:mm:ss")}</span>
                </div>
                <div className="flex justify-between py-2 border-b border-border border-dashed">
                  <span className="text-muted-foreground">Commission</span>
                  <span className="font-mono text-loss">{trade.commission}</span>
                </div>
                <div className="flex justify-between py-2 border-b border-border border-dashed">
                  <span className="text-muted-foreground">Swap</span>
                  <span className="font-mono text-loss">{trade.swap}</span>
                </div>
              </div>
            </div>
          </div>
        </ScrollArea>
      </SheetContent>
    </Sheet>
  );
}
