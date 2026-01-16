import { type User, type InsertUser, type Trade, type InsertTrade, type MT5Account, type InsertMT5Account, type WeeklyInsight, users, trades, mt5Accounts, appSettings, weeklyInsights } from "@shared/schema";
import { db } from "./db";
import { eq, and, gte, lte, desc } from "drizzle-orm";
import { randomBytes } from "crypto";

export interface IStorage {
  // User operations
  getUser(id: string): Promise<User | undefined>;
  getUserByUsername(username: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;
  
  // Trade operations
  getTrade(id: number): Promise<Trade | undefined>;
  getTradeByDealId(dealId: string, accountId: string): Promise<Trade | undefined>;
  getAllTrades(accountId?: string): Promise<Trade[]>;
  getTradesByDateRange(startDate: Date, endDate: Date, accountId?: string): Promise<Trade[]>;
  createTrade(trade: InsertTrade): Promise<Trade>;
  updateTrade(id: number, updates: Partial<InsertTrade>): Promise<Trade | undefined>;
  
  // MT5 Account operations
  getMT5Account(id: number): Promise<MT5Account | undefined>;
  getMT5AccountByIngestionKey(key: string): Promise<MT5Account | undefined>;
  getMT5AccountByAccountAndBroker(accountId: string, broker: string): Promise<MT5Account | undefined>;
  getAllMT5Accounts(): Promise<MT5Account[]>;
  createMT5Account(account: InsertMT5Account): Promise<MT5Account>;
  deleteMT5Account(id: number): Promise<boolean>;
  regenerateIngestionKey(id: number): Promise<MT5Account | undefined>;
  
  // App Settings operations
  getSetting(key: string): Promise<string | undefined>;
  setSetting(key: string, value: string): Promise<void>;
  
  // Weekly Insights operations
  getWeeklyInsight(weekStart: Date): Promise<WeeklyInsight | undefined>;
  getLatestWeeklyInsight(): Promise<WeeklyInsight | undefined>;
  createWeeklyInsight(insight: Omit<WeeklyInsight, "id" | "generated_at">): Promise<WeeklyInsight>;
}

export class DatabaseStorage implements IStorage {
  // User operations
  async getUser(id: string): Promise<User | undefined> {
    const result = await db.select().from(users).where(eq(users.id, id)).limit(1);
    return result[0];
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    const result = await db.select().from(users).where(eq(users.username, username)).limit(1);
    return result[0];
  }

  async createUser(insertUser: InsertUser): Promise<User> {
    const result = await db.insert(users).values(insertUser).returning();
    return result[0];
  }

  // Trade operations
  async getTrade(id: number): Promise<Trade | undefined> {
    const result = await db.select().from(trades).where(eq(trades.id, id)).limit(1);
    return result[0];
  }

  async getTradeByDealId(dealId: string, accountId: string): Promise<Trade | undefined> {
    const result = await db
      .select()
      .from(trades)
      .where(and(eq(trades.deal_id, dealId), eq(trades.account_id, accountId)))
      .limit(1);
    return result[0];
  }

  async getAllTrades(accountId?: string): Promise<Trade[]> {
    if (accountId) {
      return await db
        .select()
        .from(trades)
        .where(eq(trades.account_id, accountId))
        .orderBy(desc(trades.close_time));
    }
    return await db.select().from(trades).orderBy(desc(trades.close_time));
  }

  async getTradesByDateRange(
    startDate: Date,
    endDate: Date,
    accountId?: string
  ): Promise<Trade[]> {
    const conditions = [
      gte(trades.close_time, startDate),
      lte(trades.close_time, endDate)
    ];

    if (accountId) {
      conditions.push(eq(trades.account_id, accountId));
    }

    return await db
      .select()
      .from(trades)
      .where(and(...conditions))
      .orderBy(desc(trades.close_time));
  }

  async createTrade(trade: InsertTrade): Promise<Trade> {
    const tradeWithDates = {
      ...trade,
      open_time: new Date(trade.open_time),
      close_time: new Date(trade.close_time),
    };
    const result = await db.insert(trades).values(tradeWithDates).returning();
    return result[0];
  }

  async updateTrade(id: number, updates: Partial<InsertTrade>): Promise<Trade | undefined> {
    const updatesWithDates: any = { ...updates };
    if (updates.open_time) updatesWithDates.open_time = new Date(updates.open_time);
    if (updates.close_time) updatesWithDates.close_time = new Date(updates.close_time);
    
    const result = await db
      .update(trades)
      .set(updatesWithDates)
      .where(eq(trades.id, id))
      .returning();
    return result[0];
  }

  // MT5 Account operations
  async getMT5Account(id: number): Promise<MT5Account | undefined> {
    const result = await db.select().from(mt5Accounts).where(eq(mt5Accounts.id, id)).limit(1);
    return result[0];
  }

  async getMT5AccountByIngestionKey(key: string): Promise<MT5Account | undefined> {
    const result = await db
      .select()
      .from(mt5Accounts)
      .where(and(eq(mt5Accounts.ingestion_key, key), eq(mt5Accounts.is_active, true)))
      .limit(1);
    return result[0];
  }

  async getMT5AccountByAccountAndBroker(accountId: string, broker: string): Promise<MT5Account | undefined> {
    const result = await db
      .select()
      .from(mt5Accounts)
      .where(and(eq(mt5Accounts.account_id, accountId), eq(mt5Accounts.broker, broker)))
      .limit(1);
    return result[0];
  }

  async getAllMT5Accounts(): Promise<MT5Account[]> {
    return await db.select().from(mt5Accounts).orderBy(desc(mt5Accounts.created_at));
  }

  async createMT5Account(account: InsertMT5Account): Promise<MT5Account> {
    const ingestionKey = randomBytes(32).toString("hex");
    const result = await db
      .insert(mt5Accounts)
      .values({ ...account, ingestion_key: ingestionKey })
      .returning();
    return result[0];
  }

  async deleteMT5Account(id: number): Promise<boolean> {
    const result = await db.delete(mt5Accounts).where(eq(mt5Accounts.id, id)).returning();
    return result.length > 0;
  }

  async regenerateIngestionKey(id: number): Promise<MT5Account | undefined> {
    const newKey = randomBytes(32).toString("hex");
    const result = await db
      .update(mt5Accounts)
      .set({ ingestion_key: newKey })
      .where(eq(mt5Accounts.id, id))
      .returning();
    return result[0];
  }

  // App Settings operations
  async getSetting(key: string): Promise<string | undefined> {
    const result = await db
      .select()
      .from(appSettings)
      .where(eq(appSettings.key, key))
      .limit(1);
    return result[0]?.value;
  }

  async setSetting(key: string, value: string): Promise<void> {
    const existing = await this.getSetting(key);
    if (existing !== undefined) {
      await db
        .update(appSettings)
        .set({ value })
        .where(eq(appSettings.key, key));
    } else {
      await db.insert(appSettings).values({ key, value });
    }
  }

  // Weekly Insights operations
  async getWeeklyInsight(weekStart: Date): Promise<WeeklyInsight | undefined> {
    const result = await db
      .select()
      .from(weeklyInsights)
      .where(eq(weeklyInsights.week_start, weekStart))
      .limit(1);
    return result[0];
  }

  async getLatestWeeklyInsight(): Promise<WeeklyInsight | undefined> {
    const result = await db
      .select()
      .from(weeklyInsights)
      .orderBy(desc(weeklyInsights.week_start))
      .limit(1);
    return result[0];
  }

  async createWeeklyInsight(insight: Omit<WeeklyInsight, "id" | "generated_at">): Promise<WeeklyInsight> {
    const result = await db.insert(weeklyInsights).values(insight).returning();
    return result[0];
  }
}

export const storage = new DatabaseStorage();
