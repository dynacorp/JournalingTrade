import { sql } from "drizzle-orm";
import { pgTable, text, varchar, real, timestamp, serial, boolean } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  username: text("username").notNull().unique(),
  password: text("password").notNull(),
});

export const mt5Accounts = pgTable("mt5_accounts", {
  id: serial("id").primaryKey(),
  name: varchar("name", { length: 100 }).notNull(),
  account_id: varchar("account_id", { length: 100 }).notNull(),
  broker: varchar("broker", { length: 100 }).notNull(),
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
  symbol: varchar("symbol", { length: 20 }).notNull(),
  side: varchar("side", { length: 10 }).notNull(), // BUY or SELL
  volume: real("volume").notNull(),
  
  // Prices
  entry_price: real("entry_price").notNull(),
  close_price: real("close_price").notNull(),
  sl_price: real("sl_price"),
  tp_price: real("tp_price"),
  
  // Times
  open_time: timestamp("open_time", { withTimezone: true }).notNull(),
  close_time: timestamp("close_time", { withTimezone: true }).notNull(),
  
  // P&L
  pnl: real("pnl").notNull(),
  commission: real("commission").notNull().default(0),
  swap: real("swap").notNull().default(0),
  net_pnl: real("net_pnl").notNull(),
  
  // Risk & Drawdown (MAE/MFE)
  mae: real("mae").notNull(), // Maximum Adverse Excursion (points)
  mae_cash: real("mae_cash").notNull(), // MAE in cash
  mfe: real("mfe").notNull(), // Maximum Favorable Excursion (points)
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

export const insertTradeSchema = createInsertSchema(trades).omit({
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
