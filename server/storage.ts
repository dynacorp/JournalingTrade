import { type User, type InsertUser, type Trade, type InsertTrade, users, trades } from "@shared/schema";
import { db } from "./db";
import { eq, and, gte, lte, desc } from "drizzle-orm";

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
    const result = await db.insert(trades).values(trade).returning();
    return result[0];
  }

  async updateTrade(id: number, updates: Partial<InsertTrade>): Promise<Trade | undefined> {
    const result = await db
      .update(trades)
      .set(updates)
      .where(eq(trades.id, id))
      .returning();
    return result[0];
  }
}

export const storage = new DatabaseStorage();
