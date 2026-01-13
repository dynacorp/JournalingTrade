import { useState, useMemo } from "react";
import { 
  format, 
  startOfMonth, 
  endOfMonth, 
  eachDayOfInterval, 
  isSameMonth, 
  isSameDay, 
  startOfWeek, 
  endOfWeek, 
  addDays,
  isToday
} from "date-fns";
import { ChevronLeft, ChevronRight, LayoutList, Calendar as CalendarIcon, Grid3X3, List } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { Trade } from "@/lib/mock-data";
import { Badge } from "@/components/ui/badge";

interface CalendarPnLProps {
  trades: Trade[];
  onSelectDate: (date: Date) => void;
  selectedDate?: Date;
  onSelectTrade?: (trade: Trade) => void;
}

export function CalendarPnL({ trades, onSelectDate, selectedDate, onSelectTrade }: CalendarPnLProps) {
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [viewMode, setViewMode] = useState<"calendar" | "list">("calendar");

  // Memoize calculations for performance
  const { weeks, monthlyPnL } = useMemo(() => {
    const monthStart = startOfMonth(currentMonth);
    const monthEnd = endOfMonth(currentMonth);
    const startDate = startOfWeek(monthStart);
    const endDate = endOfWeek(monthEnd);

    const dateFormat = "d";
    const rows = [];
    let days = [];
    let day = startDate;
    let formattedDate = "";

    // Generate weeks
    while (day <= endDate) {
      for (let i = 0; i < 7; i++) {
        formattedDate = format(day, dateFormat);
        const cloneDay = day;
        days.push(cloneDay);
        day = addDays(day, 1);
      }
      rows.push(days);
      days = [];
    }

    // Calculate Monthly PnL (only for this month's trades)
    const mPnL = trades
      .filter(t => isSameMonth(new Date(t.closeTime), currentMonth))
      .reduce((sum, t) => sum + t.netPnl, 0);

    return { weeks: rows, monthlyPnL: mPnL };
  }, [currentMonth, trades]);

  const getDayData = (date: Date) => {
    const dayTrades = trades.filter(t => isSameDay(new Date(t.closeTime), date));
    const dailyPnL = dayTrades.reduce((sum, t) => sum + t.netPnl, 0);
    const count = dayTrades.length;
    return { dailyPnL, count, trades: dayTrades };
  };

  const getWeekData = (weekDays: Date[]) => {
    let weekPnL = 0;
    let weekTrades = 0;
    
    weekDays.forEach(day => {
      const { dailyPnL, count } = getDayData(day);
      weekPnL += dailyPnL;
      weekTrades += count;
    });

    return { weekPnL, weekTrades };
  };

  // Get current month's trades for list view
  const currentMonthTrades = trades.filter(t => isSameMonth(new Date(t.closeTime), currentMonth));

  return (
    <div className="space-y-4 h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between shrink-0">
        <div className="flex items-center gap-4">
          <div className="flex items-center bg-card border border-border rounded-md shadow-sm">
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setCurrentMonth(prev => new Date(prev.setMonth(prev.getMonth() - 1)))}>
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <span className="w-32 text-center font-semibold font-mono text-sm">
              {format(currentMonth, "MMMM yyyy")}
            </span>
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setCurrentMonth(prev => new Date(prev.setMonth(prev.getMonth() + 1)))}>
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>

          {/* View Toggle */}
          <div className="flex items-center gap-1 bg-card border border-border rounded-md p-0.5">
            <Button 
              variant="ghost" 
              size="icon" 
              className={cn("h-7 w-7", viewMode === "calendar" && "bg-accent text-accent-foreground")}
              onClick={() => setViewMode("calendar")}
            >
              <Grid3X3 className="h-4 w-4" />
            </Button>
            <Button 
              variant="ghost" 
              size="icon" 
              className={cn("h-7 w-7", viewMode === "list" && "bg-accent text-accent-foreground")}
              onClick={() => setViewMode("list")}
            >
              <List className="h-4 w-4" />
            </Button>
          </div>
        </div>

        <div className="flex items-center gap-2 bg-card px-3 py-1.5 rounded-md border border-border shadow-sm">
           <span className="text-xs text-muted-foreground uppercase font-bold tracking-wider">Monthly P&L:</span>
           <span className={cn(
             "font-mono font-bold text-sm",
             monthlyPnL > 0 ? "text-profit" : "text-loss"
           )}>
             {monthlyPnL > 0 ? "+" : ""}{monthlyPnL.toFixed(2)}
           </span>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-auto bg-card border border-border rounded-lg shadow-sm">
        {viewMode === "calendar" ? (
          <div className="min-w-[800px]">
            {/* Days Header */}
            <div className="grid grid-cols-8 border-b border-border bg-muted/30">
              {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Total"].map((day, i) => (
                <div 
                  key={day} 
                  className={cn(
                    "p-3 text-center text-xs font-bold text-muted-foreground uppercase tracking-wider",
                    i < 7 ? "border-r border-border" : ""
                  )}
                >
                  {day}
                </div>
              ))}
            </div>

            {/* Weeks Rows */}
            <div className="divide-y divide-border">
              {weeks.map((week, i) => {
                const { weekPnL, weekTrades } = getWeekData(week);
                
                return (
                  <div key={i} className="grid grid-cols-8">
                    {/* Days */}
                    {week.map((date, dayIndex) => {
                      const { dailyPnL, count } = getDayData(date);
                      const hasTrades = count > 0;
                      const isPositive = dailyPnL > 0;
                      const isSelected = selectedDate && isSameDay(date, selectedDate);
                      const isCurrentMonth = isSameMonth(date, currentMonth);
                      const isTodayDate = isToday(date);

                      return (
                        <div 
                          key={date.toISOString()}
                          onClick={() => onSelectDate(date)}
                          className={cn(
                            "min-h-[100px] p-2 relative group cursor-pointer transition-all border-r border-border hover:bg-accent/30",
                            !isCurrentMonth && "bg-muted/10 opacity-60",
                            isSelected && "bg-accent/40 inset-shadow-sm ring-1 ring-inset ring-primary",
                            isTodayDate && "bg-accent/20"
                          )}
                        >
                          <div className="flex justify-between items-start mb-2">
                            <span className={cn(
                              "text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full transition-colors",
                              isTodayDate 
                                ? "bg-primary text-primary-foreground" 
                                : "text-muted-foreground group-hover:text-foreground"
                            )}>
                              {format(date, "d")}
                            </span>
                          </div>
                          
                          {hasTrades && (
                            <div className="flex flex-col gap-1 mt-1">
                              <span className={cn(
                                "font-mono font-bold text-sm tracking-tight",
                                isPositive ? "text-profit" : "text-loss"
                              )}>
                                {isPositive ? "+" : ""}{dailyPnL >= 1000 ? (dailyPnL/1000).toFixed(1) + 'k' : dailyPnL.toFixed(0)}
                              </span>
                              <span className="text-[10px] text-muted-foreground font-mono">
                                {count} trades
                              </span>
                            </div>
                          )}
                        </div>
                      );
                    })}

                    {/* Weekly Total Column */}
                    <div className="bg-muted/10 p-2 flex flex-col justify-center gap-1 border-l border-border/50">
                      <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
                        Week {i + 1}
                      </span>
                      {weekTrades > 0 && (
                        <>
                          <span className={cn(
                            "font-mono font-bold text-sm",
                            weekPnL > 0 ? "text-profit" : "text-loss"
                          )}>
                            {weekPnL > 0 ? "+" : ""}{weekPnL >= 1000 ? (weekPnL/1000).toFixed(1) + 'k' : weekPnL.toFixed(0)}
                          </span>
                          <span className="text-[10px] text-muted-foreground font-mono">
                            {weekTrades} trades
                          </span>
                        </>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ) : (
          <div className="w-full">
             <table className="w-full caption-bottom text-sm">
              <thead className="[&_tr]:border-b">
                <tr className="border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted">
                  <th className="h-10 px-4 text-left align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Date</th>
                  <th className="h-10 px-4 text-left align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Symbol</th>
                  <th className="h-10 px-4 text-center align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Side</th>
                  <th className="h-10 px-4 text-center align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Drawdown (MAE)</th>
                  <th className="h-10 px-4 text-right align-middle font-medium text-muted-foreground uppercase tracking-wider text-xs">Net P&L</th>
                </tr>
              </thead>
              <tbody>
                {currentMonthTrades.length > 0 ? currentMonthTrades.sort((a,b) => new Date(b.closeTime).getTime() - new Date(a.closeTime).getTime()).map((trade) => {
                   const maeRatio = Math.min(trade.mae / trade.risk, 1.2);
                   const maePercent = Math.round(maeRatio * 100);
                   
                   return (
                    <tr 
                      key={trade.id} 
                      className="border-b transition-colors hover:bg-muted/50 cursor-pointer"
                      onClick={() => onSelectTrade?.(trade)}
                    >
                      <td className="p-4 align-middle font-mono text-xs">{format(new Date(trade.closeTime), "dd MMM HH:mm")}</td>
                      <td className="p-4 align-middle font-bold text-xs">{trade.symbol}</td>
                      <td className="p-4 align-middle text-center">
                         <Badge variant={trade.side === "BUY" ? "default" : "destructive"} className="px-1.5 py-0 text-[10px]">
                            {trade.side}
                         </Badge>
                      </td>
                      <td className="p-4 align-middle">
                        <div className="w-full max-w-[120px] mx-auto space-y-1">
                          <div className="h-1.5 w-full bg-muted rounded-full overflow-hidden relative">
                            <div 
                              className={cn(
                                "h-full rounded-full",
                                maeRatio > 0.8 ? "bg-destructive" :
                                maeRatio > 0.5 ? "bg-yellow-500" :
                                "bg-emerald-500"
                              )}
                              style={{ width: `${Math.min(maePercent, 100)}%` }}
                            />
                          </div>
                          <div className="text-[10px] text-muted-foreground text-center">
                            {trade.mae}pts ({maePercent}%)
                          </div>
                        </div>
                      </td>
                      <td className={cn(
                        "p-4 align-middle text-right font-mono font-bold",
                        trade.netPnl > 0 ? "text-profit" : "text-loss"
                      )}>
                        {trade.netPnl > 0 ? "+" : ""}{trade.netPnl.toFixed(0)}
                      </td>
                    </tr>
                   );
                }) : (
                  <tr>
                    <td colSpan={5} className="p-4 text-center text-muted-foreground">No trades this month.</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
