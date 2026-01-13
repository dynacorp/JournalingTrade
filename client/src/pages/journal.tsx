import { useState } from "react";
import { Layout } from "@/components/layout";
import { CalendarPnL } from "@/components/calendar-pnl";
import { TradeDetail } from "@/components/trade-detail";
import { MOCK_TRADES, Trade } from "@/lib/mock-data";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Search } from "lucide-react";
import { format } from "date-fns";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";

export default function Journal() {
  const [selectedTrade, setSelectedTrade] = useState<Trade | null>(null);
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);

  // Filter trades based on date if selected in calendar
  const filteredTrades = selectedDate 
    ? MOCK_TRADES.filter(t => new Date(t.closeTime).toDateString() === selectedDate.toDateString())
    : [];

  return (
    <Layout>
      <div className="p-8 space-y-6 max-w-[1600px] mx-auto h-[calc(100vh-theme(spacing.8))] flex flex-col">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4 shrink-0">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Trading Journal</h1>
            <p className="text-muted-foreground">Review and analyze your execution history.</p>
          </div>
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-auto min-h-0">
            <div className="grid lg:grid-cols-3 gap-6 h-full">
              <div className="lg:col-span-2 overflow-auto h-full flex flex-col">
                <CalendarPnL 
                  trades={MOCK_TRADES} 
                  onSelectDate={setSelectedDate}
                  selectedDate={selectedDate}
                  onSelectTrade={setSelectedTrade}
                />
              </div>
              
              {/* Daily Drill-down Sidebar */}
              <div className="bg-card border border-border rounded-lg p-4 h-full overflow-hidden flex flex-col shadow-sm">
                <div className="flex items-center justify-between mb-4 shrink-0">
                  <h3 className="font-semibold">
                    {selectedDate ? `Trades for ${format(selectedDate, "MMM d, yyyy")}` : "Select a date"}
                  </h3>
                  {selectedDate && (
                    <Badge variant="outline" className="font-mono">
                      {filteredTrades.length} trades
                    </Badge>
                  )}
                </div>
                
                <div className="space-y-3 overflow-auto flex-1 pr-2">
                  {!selectedDate ? (
                     <div className="flex flex-col items-center justify-center h-48 text-center text-muted-foreground p-4">
                       <p>Click a day on the calendar to view trade details.</p>
                     </div>
                  ) : filteredTrades.length === 0 ? (
                    <div className="text-sm text-muted-foreground text-center py-8">
                      No trades found for this day.
                    </div>
                  ) : (
                    filteredTrades.map(trade => (
                      <div 
                        key={trade.id}
                        onClick={() => setSelectedTrade(trade)}
                        className="p-3 rounded-lg border border-border hover:bg-accent/50 cursor-pointer transition-colors group relative overflow-hidden"
                      >
                         {/* Mini MAE bar on side */}
                         <div 
                           className={cn(
                             "absolute left-0 top-0 bottom-0 w-1",
                             (trade.mae / trade.risk) > 0.8 ? "bg-destructive" :
                             (trade.mae / trade.risk) > 0.5 ? "bg-yellow-500" : "bg-emerald-500"
                           )}
                         />

                        <div className="flex justify-between items-start mb-2 pl-2">
                          <div className="flex items-center gap-2">
                            <Badge variant={trade.side === "BUY" ? "default" : "destructive"} className="px-1.5 py-0 text-[10px]">
                              {trade.side}
                            </Badge>
                            <span className="font-mono font-bold text-sm">{trade.symbol}</span>
                          </div>
                          <span className={cn(
                            "font-mono font-medium text-sm",
                            trade.netPnl > 0 ? "text-profit" : "text-loss"
                          )}>
                            {trade.netPnl > 0 ? "+" : ""}{trade.netPnl.toFixed(0)}
                          </span>
                        </div>
                        <div className="flex justify-between items-end pl-2">
                          <span className="text-xs text-muted-foreground">{trade.setup}</span>
                          <div className="flex gap-2 text-xs font-mono text-muted-foreground">
                            <span>MAE: {trade.mae}</span>
                            <span>{format(new Date(trade.closeTime), "HH:mm")}</span>
                          </div>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
        </div>

        <TradeDetail 
          trade={selectedTrade} 
          isOpen={!!selectedTrade} 
          onClose={() => setSelectedTrade(null)} 
        />
      </div>
    </Layout>
  );
}
