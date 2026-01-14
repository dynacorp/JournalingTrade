import { apiRequest } from "./queryClient";
import type { Trade } from "@shared/schema";

export interface TradeInput {
  deal_id: string;
  account_id: string;
  symbol: string;
  side: string;
  volume: number;
  entry_price: number;
  close_price: number;
  sl_price?: number | null;
  tp_price?: number | null;
  open_time: Date | string;
  close_time: Date | string;
  pnl: number;
  commission?: number;
  swap?: number;
  net_pnl: number;
  mae: number;
  mae_cash: number;
  mfe: number;
  risk?: number | null;
  risk_cash?: number | null;
  setup?: string;
  tags?: string[];
  notes?: string;
}

export async function createTrade(trade: TradeInput): Promise<Trade> {
  const res = await apiRequest("POST", "/api/trades", trade);
  return await res.json();
}

export async function getTrades(params?: {
  start_date?: string;
  end_date?: string;
  account_id?: string;
}): Promise<Trade[]> {
  const searchParams = new URLSearchParams();
  if (params?.start_date) searchParams.set("start_date", params.start_date);
  if (params?.end_date) searchParams.set("end_date", params.end_date);
  if (params?.account_id) searchParams.set("account_id", params.account_id);
  
  const url = `/api/trades${searchParams.toString() ? `?${searchParams}` : ""}`;
  const res = await apiRequest("GET", url);
  return await res.json();
}

export async function getTrade(id: number): Promise<Trade> {
  const res = await apiRequest("GET", `/api/trades/${id}`);
  return await res.json();
}

export async function updateTrade(id: number, updates: Partial<TradeInput>): Promise<Trade> {
  const res = await apiRequest("PATCH", `/api/trades/${id}`, updates);
  return await res.json();
}
