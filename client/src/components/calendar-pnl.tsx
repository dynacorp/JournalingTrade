import { useState } from "react";
import { format, startOfMonth, endOfMonth, eachDayOfInterval, isSameMonth, isSameDay, getDay } from "date-fns";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { Trade } from "@/lib/mock-data";

interface CalendarPnLProps {
  trades: Trade[];
  onSelectDate: (date: Date) => void;
  selectedDate?: Date;
}

export function CalendarPnL({ trades, onSelectDate, selectedDate }: CalendarPnLProps) {
  const [currentMonth, setCurrentMonth] = useState(new Date());

  const daysInMonth = eachDayOfInterval({
    start: startOfMonth(currentMonth),
    end: endOfMonth(currentMonth),
  });

  // Calculate padding days for the grid start (to align with weekday)
  const startDay = getDay(startOfMonth(currentMonth));
  const paddingDays = Array(startDay).fill(null);

  const getDayData = (date: Date) => {
    const dayTrades = trades.filter(t => isSameDay(new Date(t.closeTime), date));
    const dailyPnL = dayTrades.reduce((sum, t) => sum + t.netPnl, 0);
    const count = dayTrades.length;
    return { dailyPnL, count };
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold font-mono tracking-tight">
          {format(currentMonth, "MMMM yyyy")}
        </h2>
        <div className="flex gap-1">
          <Button variant="ghost" size="icon" onClick={() => setCurrentMonth(prev => new Date(prev.setMonth(prev.getMonth() - 1)))}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon" onClick={() => setCurrentMonth(prev => new Date(prev.setMonth(prev.getMonth() + 1)))}>
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-7 gap-px bg-border border border-border rounded-lg overflow-hidden">
        {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map(day => (
          <div key={day} className="bg-muted/50 p-2 text-center text-xs font-medium text-muted-foreground uppercase tracking-wider">
            {day}
          </div>
        ))}
        
        {paddingDays.map((_, i) => (
          <div key={`padding-${i}`} className="bg-card min-h-[100px]" />
        ))}

        {daysInMonth.map(date => {
          const { dailyPnL, count } = getDayData(date);
          const hasTrades = count > 0;
          const isPositive = dailyPnL > 0;
          const isSelected = selectedDate && isSameDay(date, selectedDate);

          return (
            <div 
              key={date.toISOString()}
              onClick={() => onSelectDate(date)}
              className={cn(
                "bg-card min-h-[100px] p-2 relative group cursor-pointer transition-colors hover:bg-accent/50",
                isSelected && "ring-2 ring-primary ring-inset z-10"
              )}
            >
              <div className="flex justify-between items-start mb-1">
                <span className={cn(
                  "text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full",
                  isSameDay(date, new Date()) ? "bg-primary text-primary-foreground" : "text-muted-foreground"
                )}>
                  {format(date, "d")}
                </span>
                {hasTrades && (
                  <span className="text-[10px] text-muted-foreground font-mono bg-muted px-1.5 py-0.5 rounded">
                    {count}t
                  </span>
                )}
              </div>
              
              {hasTrades && (
                <div className="flex flex-col items-end gap-1 mt-2">
                  <span className={cn(
                    "font-mono font-medium text-sm",
                    isPositive ? "text-profit" : "text-loss"
                  )}>
                    {isPositive ? "+" : ""}{dailyPnL.toFixed(2)}
                  </span>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
