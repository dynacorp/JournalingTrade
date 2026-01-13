import { useState } from "react";
import { Layout } from "@/components/layout";
import { CalendarPnL } from "@/components/calendar-pnl";
import { TradeDetail } from "@/components/trade-detail";
import { MOCK_TRADES, Trade } from "@/lib/mock-data";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Search, Filter, SlidersHorizontal, List, Grid3X3 } from "lucide-react";
import { cn } from "@/lib/utils";
import { format } from "date-fns";

export default function Journal() {
  const [view, setView] = useState<"calendar" | "list">("calendar");
  const [selectedTrade, setSelectedTrade] = useState<Trade | null>(null);
  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);

  // Filter trades based on date if selected in calendar
  const filteredTrades = selectedDate 
    ? MOCK_TRADES.filter(t => new Date(t.closeTime).toDateString() === selectedDate.toDateString())
    : MOCK_TRADES;

  return (
    <Layout>
      <div className="p-8 space-y-6 max-w-[1600px] mx-auto h-[calc(100vh-theme(spacing.8))] flex flex-col">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4 shrink-0">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Trading Journal</h1>
            <p className="text-muted-foreground">Review and analyze your execution history.</p>
          </div>
          
          <div className="flex items-center gap-2 bg-card border border-border p-1 rounded-lg">
            <button 
              onClick={() => setView("calendar")}
              className={cn(
                "p-2 rounded-md transition-all",
                view === "calendar" ? "bg-primary text-primary-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"
              )}
            >
              <Grid3X3 className="w-4 h-4" />
            </button>
            <button 
              onClick={() => setView("list")}
              className={cn(
                "p-2 rounded-md transition-all",
                view === "list" ? "bg-primary text-primary-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"
              )}
            >
              <List className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Filters Bar */}
        <div className="flex flex-col md:flex-row gap-4 items-center bg-card p-4 rounded-lg border border-border shrink-0">
          <div className="relative w-full md:w-64">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input placeholder="Search trades..." className="pl-9 bg-background" />
          </div>
          <div className="flex gap-2 w-full md:w-auto overflow-x-auto pb-2 md:pb-0">
            <Select defaultValue="all">
              <SelectTrigger className="w-[120px] bg-background">
                <SelectValue placeholder="Symbol" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Symbols</SelectItem>
                <SelectItem value="EURUSD">EURUSD</SelectItem>
                <SelectItem value="XAUUSD">XAUUSD</SelectItem>
              </SelectContent>
            </Select>
            <Select defaultValue="all">
              <SelectTrigger className="w-[120px] bg-background">
                <SelectValue placeholder="Setup" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Setups</SelectItem>
                <SelectItem value="breakout">Breakout</SelectItem>
                <SelectItem value="reversal">Reversal</SelectItem>
              </SelectContent>
            </Select>
            <Select defaultValue="all">
              <SelectTrigger className="w-[120px] bg-background">
                <SelectValue placeholder="Outcome" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All</SelectItem>
                <SelectItem value="win">Win</SelectItem>
                <SelectItem value="loss">Loss</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-auto min-h-0">
          {view === "calendar" ? (
            <div className="grid lg:grid-cols-3 gap-6 h-full">
              <div className="lg:col-span-2 overflow-auto">
                <CalendarPnL 
                  trades={MOCK_TRADES} 
                  onSelectDate={setSelectedDate}
                  selectedDate={selectedDate}
                />
              </div>
              <div className="bg-card border border-border rounded-lg p-4 h-full overflow-hidden flex flex-col">
                <h3 className="font-semibold mb-4 shrink-0">
                  {selectedDate ? `Trades for ${format(selectedDate, "MMM d, yyyy")}` : "Select a date to view trades"}
                </h3>
                <div className="space-y-3 overflow-auto flex-1 pr-2">
                  {filteredTrades.length === 0 ? (
                    <div className="text-sm text-muted-foreground text-center py-8">
                      No trades found for this selection.
                    </div>
                  ) : (
                    filteredTrades.map(trade => (
                      <div 
                        key={trade.id}
                        onClick={() => setSelectedTrade(trade)}
                        className="p-3 rounded-lg border border-border hover:bg-accent/50 cursor-pointer transition-colors group"
                      >
                        <div className="flex justify-between items-start mb-2">
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
                            {trade.netPnl > 0 ? "+" : ""}{trade.netPnl}
                          </span>
                        </div>
                        <div className="flex justify-between items-end">
                          <span className="text-xs text-muted-foreground">{trade.setup}</span>
                          <span className="text-xs font-mono text-muted-foreground">{format(new Date(trade.closeTime), "HH:mm")}</span>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          ) : (
            <div className="rounded-md border border-border bg-card">
              {/* Simple Table View */}
              <div className="w-full overflow-auto">
                <table className="w-full caption-bottom text-sm">
                  <thead className="[&_tr]:border-b">
                    <tr className="border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted">
                      <th className="h-12 px-4 text-left align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Date</th>
                      <th className="h-12 px-4 text-left align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Symbol</th>
                      <th className="h-12 px-4 text-left align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Side</th>
                      <th className="h-12 px-4 text-left align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Setup</th>
                      <th className="h-12 px-4 text-right align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Vol</th>
                      <th className="h-12 px-4 text-right align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Entry</th>
                      <th className="h-12 px-4 text-right align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Exit</th>
                      <th className="h-12 px-4 text-right align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Net P&L</th>
                    </tr>
                  </thead>
                  <tbody className="[&_tr:last-child]:border-0">
                    {MOCK_TRADES.map(trade => (
                      <tr 
                        key={trade.id} 
                        onClick={() => setSelectedTrade(trade)}
                        className="border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted cursor-pointer font-mono"
                      >
                        <td className="p-4 align-middle text-muted-foreground font-sans text-xs">{format(new Date(trade.closeTime), "MMM d HH:mm")}</td>
                        <td className="p-4 align-middle font-bold">{trade.symbol}</td>
                        <td className="p-4 align-middle">
                          <span className={cn(
                            "text-xs px-1.5 py-0.5 rounded font-bold",
                            trade.side === "BUY" ? "bg-primary/20 text-primary" : "bg-destructive/20 text-destructive"
                          )}>
                            {trade.side}
                          </span>
                        </td>
                        <td className="p-4 align-middle font-sans text-xs">{trade.setup}</td>
                        <td className="p-4 align-middle text-right">{trade.volume}</td>
                        <td className="p-4 align-middle text-right text-muted-foreground">{trade.openPrice}</td>
                        <td className="p-4 align-middle text-right text-muted-foreground">{trade.closePrice}</td>
                        <td className={cn(
                          "p-4 align-middle text-right font-bold",
                          trade.netPnl > 0 ? "text-profit" : "text-loss"
                        )}>
                          {trade.netPnl > 0 ? "+" : ""}{trade.netPnl}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
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
