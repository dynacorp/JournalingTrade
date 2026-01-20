import { sql } from "drizzle-orm";
import { pgTable, text, varchar, real, timestamp, serial, boolean, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  username: text("username").notNull().unique(),
  password: text("password").notNull(),
});

export const appSettings = pgTable("app_settings", {
  id: serial("id").primaryKey(),
  key: varchar("key", { length: 100 }).notNull().unique(),
  value: text("value").notNull(),
});

export const weeklyInsights = pgTable("weekly_insights", {
  id: serial("id").primaryKey(),
  week_start: timestamp("week_start", { withTimezone: true }).notNull(),
  week_end: timestamp("week_end", { withTimezone: true }).notNull(),
  top_strength: text("top_strength"),
  main_leak: text("main_leak"),
  action_item: text("action_item"),
  trades_analyzed: real("trades_analyzed").default(0),
  total_pnl: real("total_pnl").default(0),
  win_rate: real("win_rate").default(0),
  generated_at: timestamp("generated_at", { withTimezone: true }).defaultNow().notNull(),
});

export const mt5Accounts = pgTable("mt5_accounts", {
  id: serial("id").primaryKey(),
  name: varchar("name", { length: 100 }).notNull(),
  account_id: varchar("account_id", { length: 100 }).notNull(),
  broker: varchar("broker", { length: 100 }).notNull(),
  initial_balance: real("initial_balance").notNull().default(0),
  ingestion_key: varchar("ingestion_key", { length: 64 }).notNull().unique(),
  is_active: boolean("is_active").default(true).notNull(),
  created_at: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

export const trades = pgTable("trades", {
  id: serial("id").primaryKey(),
  
  // MT5 Identity (for deduplication)
  deal_id: varchar("deal_id", { length: 100 }).notNull(),
  account_id: varchar("account_id", { length: 100 }).notNull(),
  
  // Trade Info
  symbol: varchar("symbol", { length: 50 }).notNull(),
  side: varchar("side", { length: 10 }).notNull(), // BUY or SELL
  volume: real("volume").notNull(),
  
  // Prices
  entry_price: real("entry_price").notNull(),
  close_price: real("close_price").notNull(),
  sl_price: real("sl_price"),
  tp_price: real("tp_price"),
  
  // Times
  open_time: timestamp("open_time", { withTimezone: true }),
  close_time: timestamp("close_time", { withTimezone: true }),
  
  // P&L
  pnl: real("pnl").notNull(),
  commission: real("commission").notNull().default(0),
  swap: real("swap").notNull().default(0),
  net_pnl: real("net_pnl").notNull(),
  
  // Account State (snapshot at trade close)
  balance: real("balance"),
  equity: real("equity"),
  
  // Risk & Drawdown (MAE/MFE)
  mae: real("mae").notNull(), // Maximum Adverse Excursion (points)
  mae_cash: real("mae_cash").notNull(), // MAE in cash
  mfe: real("mfe").notNull(), // Maximum Favorable Excursion (points)
  mfe_cash: real("mfe_cash"), // MFE in cash
  dd_pct: real("dd_pct"), // Drawdown percentage
  risk: real("risk"), // Planned Stop Loss distance (points) - Nullable
  risk_cash: real("risk_cash"), // Planned Stop Loss value (cash) - Nullable
  
  // Trade Metadata
  setup: varchar("setup", { length: 100 }),
  tags: text("tags").array().default(sql`ARRAY[]::text[]`),
  notes: text("notes"),
  
  // AI Summary
  ai_summary: text("ai_summary"),
  ai_execution: varchar("ai_execution", { length: 20 }), // Good, Bad, Neutral
  ai_mistake: text("ai_mistake"),
  ai_improvement: text("ai_improvement"),
  ai_generated: boolean("ai_generated").default(false),
  
  created_at: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

// Unique constraint on deal_id + account_id for deduplication
export const tradeUniqueConstraint = sql`
  CREATE UNIQUE INDEX IF NOT EXISTS unique_trade_deal ON trades(deal_id, account_id);
`;

export const insertTradeSchema = createInsertSchema(trades, {
  open_time: z.string().optional().nullable(),
  close_time: z.string().optional().nullable(),
}).omit({
  id: true,
  created_at: true,
});

export const insertUserSchema = createInsertSchema(users).pick({
  username: true,
  password: true,
});

export const insertMT5AccountSchema = createInsertSchema(mt5Accounts).omit({
  id: true,
  ingestion_key: true,
  created_at: true,
});

export type InsertTrade = z.infer<typeof insertTradeSchema>;
export type Trade = typeof trades.$inferSelect;
export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof users.$inferSelect;
export type InsertMT5Account = z.infer<typeof insertMT5AccountSchema>;
export type MT5Account = typeof mt5Accounts.$inferSelect;
export type WeeklyInsight = typeof weeklyInsights.$inferSelect;

// Chart Snapshots for AI Analysis
export const chartSnapshots = pgTable("chart_snapshots", {
  id: serial("id").primaryKey(),
  snapshot_id: varchar("snapshot_id", { length: 64 }).notNull().unique(),
  account_id: varchar("account_id", { length: 100 }).notNull(),

  // Chart Context
  symbol: varchar("symbol", { length: 50 }).notNull(),
  timeframe: varchar("timeframe", { length: 10 }).notNull(),
  snapshot_time: timestamp("snapshot_time", { withTimezone: true }).notNull(),
  candle_time: timestamp("candle_time", { withTimezone: true }), // The candle open time (for upsert key)

  // Multi-Timeframe Grouping
  group_id: varchar("group_id", { length: 100 }), // Links MTF snapshots together
  tf_type: varchar("tf_type", { length: 10 }), // "htf" (higher TF for bias) or "ltf" (lower TF for entry)

  // Image Storage (Base64)
  image_data: text("image_data").notNull(),

  // Status: pending | pre_analyzed | queued_for_review | approved | analyzed | discarded | no_setup
  status: varchar("status", { length: 20 }).notNull().default("pending"),

  // Pre-Analysis (lightweight, always runs)
  pre_analysis_score: real("pre_analysis_score"),
  pre_analysis_summary: text("pre_analysis_summary"),
  pre_analysis_bias: varchar("pre_analysis_bias", { length: 20 }),
  pre_analysis_at: timestamp("pre_analysis_at", { withTimezone: true }),

  // Full Analysis (gated, runs on approval or high score)
  full_analysis: text("full_analysis"), // JSON stringified FullAnalysisResult
  full_analysis_at: timestamp("full_analysis_at", { withTimezone: true }),

  // Confluence Scores (extracted from full analysis for querying)
  confluence_score: real("confluence_score"),
  market_structure_score: real("market_structure_score"),
  key_levels_score: real("key_levels_score"),
  liquidity_score: real("liquidity_score"),
  impulse_origin_score: real("impulse_origin_score"),
  imbalance_score: real("imbalance_score"),
  candle_action_score: real("candle_action_score"),

  // Entry Logic (extracted from full analysis)
  trade_direction: varchar("trade_direction", { length: 10 }), // long | short | none
  entry_zone: text("entry_zone"),
  invalidation_level: real("invalidation_level"),
  invalidation_reason: text("invalidation_reason"),

  // Trade Linking
  linked_trade_id: integer("linked_trade_id").references(() => trades.id),
  auto_linked: boolean("auto_linked").default(false),

  // Metadata
  user_notes: text("user_notes"),
  is_journal_candidate: boolean("is_journal_candidate").default(false),
  created_at: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

// Full analysis JSON structure type
export interface FullAnalysisResult {
  market_structure: {
    trend_state: "uptrend" | "downtrend" | "range" | "transitioning";
    structure_points: string[];
    bos_detected: boolean;
    choch_detected: boolean;
    score: number;
  };
  key_levels: {
    support_levels: number[];
    resistance_levels: number[];
    sr_flips: number[];
    session_levels: { high: number | null; low: number | null };
    score: number;
  };
  liquidity: {
    equal_highs: number[];
    equal_lows: number[];
    sweep_detected: boolean;
    failed_breakout: boolean;
    score: number;
  };
  impulse_origin: {
    origin_zones: { start: number; end: number }[];
    compression_detected: boolean;
    expansion_detected: boolean;
    score: number;
  };
  imbalance: {
    fvg_zones: { start: number; end: number; filled: boolean }[];
    rebalancing_in_progress: boolean;
    score: number;
  };
  candle_action: {
    rejection_wicks: string[];
    displacement_detected: boolean;
    acceptance_rejection: "acceptance" | "rejection" | "neutral";
    score: number;
  };
  entry_logic: {
    valid_setup: boolean;
    entry_zone: string;
    invalidation_level: number;
    invalidation_reason: string;
    trade_direction: "long" | "short" | "none";
    targets: number[];
    confluence_list: string[];
    confidence: number;
  };
  overall_assessment: string;
  weighted_score: number;
}

export type ChartSnapshotStatus =
  | "pending"
  | "pre_analyzed"
  | "queued_for_review"
  | "approved"
  | "analyzed"
  | "discarded"
  | "no_setup";

export const insertChartSnapshotSchema = createInsertSchema(chartSnapshots, {
  snapshot_time: z.string(),
}).omit({
  id: true,
  created_at: true,
  pre_analysis_score: true,
  pre_analysis_summary: true,
  pre_analysis_bias: true,
  pre_analysis_at: true,
  full_analysis: true,
  full_analysis_at: true,
  confluence_score: true,
  market_structure_score: true,
  key_levels_score: true,
  liquidity_score: true,
  impulse_origin_score: true,
  imbalance_score: true,
  candle_action_score: true,
  trade_direction: true,
  entry_zone: true,
  invalidation_level: true,
  invalidation_reason: true,
  linked_trade_id: true,
  auto_linked: true,
  is_journal_candidate: true,
});

export const ingestChartSnapshotSchema = z.object({
  snapshot_id: z.string().min(1).max(64),
  symbol: z.string().min(1).max(50),
  timeframe: z.string().min(1).max(10),
  snapshot_time: z.string(),
  candle_time: z.string().optional(), // The candle open time (for upsert key)
  image_data: z.string().min(1),
  group_id: z.string().max(100).optional(),
  tf_type: z.enum(["htf", "ltf"]).optional(),
});

export type InsertChartSnapshot = z.infer<typeof insertChartSnapshotSchema>;
export type ChartSnapshot = typeof chartSnapshots.$inferSelect;
