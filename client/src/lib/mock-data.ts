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
  // Risk & Drawdown fields
  mae: number; // Maximum Adverse Excursion (points/pips)
  mae_cash: number; // Maximum Adverse Excursion (cash value)
  mfe: number; // Maximum Favorable Excursion (points/pips)
  risk: number | null; // Planned Stop Loss distance (points/pips) - Null if no SL
  risk_cash: number | null; // Planned Stop Loss value (cash) - Null if no SL
  entry_price: number; 
  sl_price: number | null;
  tp_price: number | null;
  
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
        const side = Math.random() > 0.5 ? "BUY" : "SELL";
        const hasSL = Math.random() > 0.2; // 20% trades have NO SL
        
        // Mock points calculation (simplified)
        const riskPointsBase = Math.floor(Math.random() * 20) + 10; // 10-30 points standard risk
        const riskPoints = hasSL ? riskPointsBase : null;
        
        // If No SL, we still need a "virtual risk" for reward calculation logic, or just random
        const virtualRisk = riskPointsBase;
        
        const rewardPoints = isWin 
          ? virtualRisk * (Math.random() * 2 + 1) // 1R to 3R
          : -Math.min(virtualRisk * (Math.random() * 0.5 + 0.8), virtualRisk); // 0.8R to 1R loss
        
        const openPrice = side === "BUY" ? 1.0850 : 1.0900; // Simplified
        const riskAmount = 100; // $100 risk per trade (standard)
        
        // Value per point calculation
        const valuePerPoint = riskAmount / virtualRisk;
        
        const pnl = (rewardPoints * valuePerPoint);

        // MAE generation
        let maePoints = 0;
        if (isWin) {
           maePoints = Math.random() * (virtualRisk * 0.8);
        } else {
           // If loss and Has SL -> hit SL (approx)
           if (hasSL) {
             maePoints = virtualRisk * (Math.random() * 0.2 + 0.9);
           } else {
             // If loss and NO SL -> could be huge drawdown
             maePoints = virtualRisk * (Math.random() * 3 + 1); // 1x to 4x virtual risk
           }
        }

        // MFE generation
        const mfePoints = isWin
          ? rewardPoints * (Math.random() * 0.2 + 1)
          : Math.random() * (virtualRisk * 0.5);

        trades.push({
          id: `TRD-${tradeIdCounter++}`,
          symbol: ["EURUSD", "GBPUSD", "XAUUSD", "NAS100", "US30"][Math.floor(Math.random() * 5)],
          side,
          volume: Math.floor(Math.random() * 20) / 10 + 0.1,
          openPrice,
          closePrice: openPrice + (side === "BUY" ? rewardPoints * 0.0001 : -rewardPoints * 0.0001),
          openTime: addDays(day, 0).toISOString(),
          closeTime: addDays(day, 0).toISOString(),
          pnl: Number(pnl.toFixed(2)),
          commission: -5,
          swap: 0,
          netPnl: Number((pnl - 5).toFixed(2)),
          tags: isWin ? ["Trend", "A+"] : !hasSL ? ["No SL", "Risky"] : ["Chop"],
          setup: isWin ? "Breakout" : "Reversal",
          notes: !hasSL ? "Managed manually without hard SL." : "Standard execution.",
          
          mae: Number(maePoints.toFixed(1)),
          mae_cash: Number((maePoints * valuePerPoint).toFixed(2)),
          mfe: Number(mfePoints.toFixed(1)),
          
          risk: riskPoints ? Number(riskPoints.toFixed(1)) : null,
          risk_cash: riskPoints ? Number((riskPoints * valuePerPoint).toFixed(2)) : null,
          
          entry_price: openPrice,
          sl_price: hasSL ? (side === "BUY" ? openPrice - (riskPoints! * 0.0001) : openPrice + (riskPoints! * 0.0001)) : null,
          tp_price: hasSL ? (side === "BUY" ? openPrice + (riskPoints! * 2 * 0.0001) : openPrice - (riskPoints! * 2 * 0.0001)) : null,

          aiSummary: {
            summary: isWin ? "Clean move, followed plan." : "Entered too early against momentum.",
            execution: isWin ? "Good" : "Bad",
            mistake: !hasSL ? "Trading without SL" : null,
            improvement: !hasSL ? "Always define max risk" : "Wait for candle close"
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
