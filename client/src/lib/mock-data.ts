import { addDays, subDays, format } from "date-fns";

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

export const MOCK_TRADES: Trade[] = [
  {
    id: "TRD-1001",
    symbol: "EURUSD",
    side: "BUY",
    volume: 1.0,
    openPrice: 1.0850,
    closePrice: 1.0890,
    openTime: new Date(new Date().setHours(9, 30)).toISOString(),
    closeTime: new Date(new Date().setHours(11, 45)).toISOString(),
    pnl: 400,
    commission: -7,
    swap: 0,
    netPnl: 393,
    tags: ["Trend Follow", "A+ Setup"],
    setup: "Breakout",
    notes: "Clean breakout of Asian range.",
    aiSummary: {
      summary: "Caught the morning breakout perfectly. Entry was precise.",
      execution: "Good",
      mistake: null,
      improvement: "Could have held longer for the second leg up."
    }
  },
  {
    id: "TRD-1002",
    symbol: "GBPUSD",
    side: "SELL",
    volume: 0.5,
    openPrice: 1.2750,
    closePrice: 1.2780,
    openTime: subDays(new Date(), 1).toISOString(),
    closeTime: subDays(new Date(), 1).toISOString(),
    pnl: -150,
    commission: -3.5,
    swap: 0,
    netPnl: -153.5,
    tags: ["Reversal", "FOMO"],
    setup: "Double Top",
    notes: "Entered too early before confirmation.",
    aiSummary: {
      summary: "Attempted to fade the rally without confirmation. Stopped out.",
      execution: "Bad",
      mistake: "Entry was premature. Fighting the trend.",
      improvement: "Wait for candle close below support."
    }
  },
  {
    id: "TRD-1003",
    symbol: "XAUUSD",
    side: "BUY",
    volume: 0.1,
    openPrice: 2020.50,
    closePrice: 2035.00,
    openTime: subDays(new Date(), 2).toISOString(),
    closeTime: subDays(new Date(), 2).toISOString(),
    pnl: 145,
    commission: -1,
    swap: 0,
    netPnl: 144,
    tags: ["Scalp", "News"],
    setup: "Support Bounce",
    notes: "Quick scalp on gold news.",
    aiSummary: {
      summary: "Good reaction trade to news event. Quick profit taking.",
      execution: "Good",
      mistake: null,
      improvement: "Volume size could be increased for high conviction."
    }
  },
  {
    id: "TRD-1004",
    symbol: "NAS100",
    side: "SELL",
    volume: 0.2,
    openPrice: 17500,
    closePrice: 17450,
    openTime: subDays(new Date(), 3).toISOString(),
    closeTime: subDays(new Date(), 3).toISOString(),
    pnl: 100,
    commission: -2,
    swap: -1,
    netPnl: 97,
    tags: ["Intraday"],
    setup: "Pullback",
    notes: "Standard pullback short.",
  },
  {
    id: "TRD-1005",
    symbol: "US30",
    side: "BUY",
    volume: 0.5,
    openPrice: 38000,
    closePrice: 37900,
    openTime: subDays(new Date(), 4).toISOString(),
    closeTime: subDays(new Date(), 4).toISOString(),
    pnl: -500,
    commission: -3.5,
    swap: 0,
    netPnl: -503.5,
    tags: ["Mistake"],
    setup: "Range",
    notes: "Choppy market, got whipsawed.",
    aiSummary: {
      summary: "Got caught in the chop. Overtraded the range.",
      execution: "Bad",
      mistake: "Overtrading in low volatility.",
      improvement: "Sit on hands during lunch hour chop."
    }
  }
];

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
