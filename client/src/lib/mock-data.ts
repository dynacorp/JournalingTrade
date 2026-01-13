import { addDays, subDays, format, startOfMonth, endOfMonth, eachDayOfInterval, isWeekend } from "date-fns";

export type Trade = {
  id: string;
  symbol: string;
  side: "BUY" | "SELL";
  volume: number;
  openPrice: number;
  closePrice: number;
  openTime: string;
  closeTime: string;
  pnl: number;
  commission: number;
  swap: number;
  netPnl: number;
  tags: string[];
  setup: string;
  notes: string;
  aiSummary?: {
    summary: string;
    execution: "Good" | "Bad" | "Neutral";
    mistake: string | null;
    improvement: string;
  };
};

// Helper to generate realistic mock trades for the current month
const generateMockTrades = (): Trade[] => {
  const today = new Date();
  const start = startOfMonth(today);
  const end = endOfMonth(today);
  const days = eachDayOfInterval({ start, end });
  
  const trades: Trade[] = [];
  let tradeIdCounter = 1000;

  days.forEach(day => {
    if (isWeekend(day)) return; // Skip weekends usually
    
    // 60% chance to trade on a weekday
    if (Math.random() > 0.4) {
      const numTrades = Math.floor(Math.random() * 5) + 1; // 1-5 trades
      
      for (let i = 0; i < numTrades; i++) {
        const isWin = Math.random() > 0.45; // 55% win rate
        const pnl = isWin 
          ? Math.floor(Math.random() * 500) + 100 
          : -Math.floor(Math.random() * 300) - 50;
        
        trades.push({
          id: `TRD-${tradeIdCounter++}`,
          symbol: ["EURUSD", "GBPUSD", "XAUUSD", "NAS100", "US30"][Math.floor(Math.random() * 5)],
          side: Math.random() > 0.5 ? "BUY" : "SELL",
          volume: Math.floor(Math.random() * 20) / 10 + 0.1,
          openPrice: 0, // Mock values
          closePrice: 0,
          openTime: addDays(day, 0).toISOString(),
          closeTime: addDays(day, 0).toISOString(),
          pnl: pnl,
          commission: -5,
          swap: 0,
          netPnl: pnl - 5,
          tags: isWin ? ["Trend", "A+"] : ["Chop", "Mistake"],
          setup: isWin ? "Breakout" : "Reversal",
          notes: isWin ? "Great execution" : "Forced the trade",
          aiSummary: {
            summary: isWin ? "Clean move, followed plan." : "Entered too early against momentum.",
            execution: isWin ? "Good" : "Bad",
            mistake: isWin ? null : "FOMO",
            improvement: isWin ? "Add to winner next time" : "Wait for candle close"
          }
        });
      }
    }
  });

  return trades;
};

export const MOCK_TRADES: Trade[] = generateMockTrades();

export const MOCK_STATS = {
  equityCurve: [
    { date: "2024-01-01", equity: 10000 },
    { date: "2024-01-02", equity: 10150 },
    { date: "2024-01-03", equity: 10050 },
    { date: "2024-01-04", equity: 10400 },
    { date: "2024-01-05", equity: 10300 },
    { date: "2024-01-08", equity: 10700 },
    { date: "2024-01-09", equity: 11093 },
  ],
  winRate: 65,
  profitFactor: 2.1,
  avgR: 1.8,
  maxDrawdown: -4.5
};
