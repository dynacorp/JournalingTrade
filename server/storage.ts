import { type User, type InsertUser, type Trade, type InsertTrade, type MT5Account, type InsertMT5Account, type WeeklyInsight, type ChartSnapshot, type InsertChartSnapshot, type ChartSnapshotStatus, users, trades, mt5Accounts, appSettings, weeklyInsights, chartSnapshots } from "@shared/schema";
import { db } from "./db";
import { eq, and, gte, lte, desc, lt, or, inArray } from "drizzle-orm";
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

  // Chart Snapshot operations
  getChartSnapshot(id: number): Promise<ChartSnapshot | undefined>;
  getChartSnapshotBySnapshotId(snapshotId: string): Promise<ChartSnapshot | undefined>;
  getAllChartSnapshots(params?: {
    status?: ChartSnapshotStatus;
    symbol?: string;
    timeframe?: string;
    startDate?: Date;
    endDate?: Date;
    accountId?: string;
  }): Promise<ChartSnapshot[]>;
  createChartSnapshot(snapshot: InsertChartSnapshot): Promise<ChartSnapshot>;
  updateChartSnapshot(id: number, updates: Partial<ChartSnapshot>): Promise<ChartSnapshot | undefined>;
  getChartSnapshotStats(): Promise<{
    pending: number;
    queued: number;
    analyzed: number;
    high_score_count: number;
  }>;
  autoMatchSnapshotToTrade(snapshotId: number): Promise<number | null>;
  getChartSnapshotsByGroupId(groupId: string): Promise<ChartSnapshot[]>;

  // Upsert snapshot (update if same symbol+timeframe+candle_time exists for LTF, or keep history for HTF)
  upsertChartSnapshot(snapshot: InsertChartSnapshot & { candle_time?: Date }, isHTF: boolean): Promise<ChartSnapshot>;

  // Find existing snapshot by symbol+timeframe+candle_time
  findSnapshotByCandleKey(symbol: string, timeframe: string, candleTime: Date): Promise<ChartSnapshot | undefined>;

  // Cleanup old LTF pending snapshots (keep only latest per symbol/timeframe)
  cleanupOldLTFSnapshots(maxAgeHours?: number): Promise<number>;

  // Delete a single snapshot
  deleteChartSnapshot(id: number): Promise<boolean>;

  // Delete all snapshots (with optional filters)
  deleteAllChartSnapshots(filters?: { status?: ChartSnapshotStatus; symbol?: string; timeframe?: string }): Promise<number>;
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
    const parseDate = (val: string | null | undefined): Date | null => {
      if (!val || val === "") return null;
      const d = new Date(val);
      return isNaN(d.getTime()) ? null : d;
    };
    
    const tradeWithDates = {
      ...trade,
      open_time: parseDate(trade.open_time),
      close_time: parseDate(trade.close_time),
    };
    const result = await db.insert(trades).values(tradeWithDates).returning();
    return result[0];
  }

  async updateTrade(id: number, updates: Partial<InsertTrade>): Promise<Trade | undefined> {
    const parseDate = (val: string | null | undefined): Date | null | undefined => {
      if (val === undefined) return undefined;
      if (!val || val === "") return null;
      const d = new Date(val);
      return isNaN(d.getTime()) ? null : d;
    };
    
    const updatesWithDates: any = { ...updates };
    if (updates.open_time !== undefined) updatesWithDates.open_time = parseDate(updates.open_time);
    if (updates.close_time !== undefined) updatesWithDates.close_time = parseDate(updates.close_time);
    
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

  // Chart Snapshot operations
  async getChartSnapshot(id: number): Promise<ChartSnapshot | undefined> {
    const result = await db
      .select()
      .from(chartSnapshots)
      .where(eq(chartSnapshots.id, id))
      .limit(1);
    return result[0];
  }

  async getChartSnapshotBySnapshotId(snapshotId: string): Promise<ChartSnapshot | undefined> {
    const result = await db
      .select()
      .from(chartSnapshots)
      .where(eq(chartSnapshots.snapshot_id, snapshotId))
      .limit(1);
    return result[0];
  }

  async getAllChartSnapshots(params?: {
    status?: ChartSnapshotStatus;
    symbol?: string;
    timeframe?: string;
    startDate?: Date;
    endDate?: Date;
    accountId?: string;
  }): Promise<ChartSnapshot[]> {
    const conditions: any[] = [];

    if (params?.status) {
      conditions.push(eq(chartSnapshots.status, params.status));
    }
    if (params?.symbol) {
      conditions.push(eq(chartSnapshots.symbol, params.symbol));
    }
    if (params?.timeframe) {
      conditions.push(eq(chartSnapshots.timeframe, params.timeframe));
    }
    if (params?.startDate) {
      conditions.push(gte(chartSnapshots.snapshot_time, params.startDate));
    }
    if (params?.endDate) {
      conditions.push(lte(chartSnapshots.snapshot_time, params.endDate));
    }
    if (params?.accountId) {
      conditions.push(eq(chartSnapshots.account_id, params.accountId));
    }

    if (conditions.length > 0) {
      return await db
        .select()
        .from(chartSnapshots)
        .where(and(...conditions))
        .orderBy(desc(chartSnapshots.created_at));
    }

    return await db
      .select()
      .from(chartSnapshots)
      .orderBy(desc(chartSnapshots.created_at));
  }

  async createChartSnapshot(snapshot: InsertChartSnapshot): Promise<ChartSnapshot> {
    const parseDate = (val: string | null | undefined): Date | null => {
      if (!val || val === "") return null;
      const d = new Date(val);
      return isNaN(d.getTime()) ? null : d;
    };

    const snapshotWithDates = {
      ...snapshot,
      snapshot_time: parseDate(snapshot.snapshot_time) || new Date(),
    };

    const result = await db.insert(chartSnapshots).values(snapshotWithDates).returning();
    return result[0];
  }

  async updateChartSnapshot(id: number, updates: Partial<ChartSnapshot>): Promise<ChartSnapshot | undefined> {
    const result = await db
      .update(chartSnapshots)
      .set(updates)
      .where(eq(chartSnapshots.id, id))
      .returning();
    return result[0];
  }

  async getChartSnapshotStats(): Promise<{
    pending: number;
    queued: number;
    analyzed: number;
    high_score_count: number;
  }> {
    const all = await db.select().from(chartSnapshots);

    return {
      pending: all.filter(s => s.status === "pending" || s.status === "pre_analyzed").length,
      queued: all.filter(s => s.status === "queued_for_review" || s.status === "approved").length,
      analyzed: all.filter(s => s.status === "analyzed" || s.status === "no_setup").length,
      high_score_count: all.filter(s => (s.confluence_score ?? 0) >= 70).length,
    };
  }

  async autoMatchSnapshotToTrade(snapshotId: number): Promise<number | null> {
    const snapshot = await this.getChartSnapshot(snapshotId);
    if (!snapshot) return null;

    // Find trades within +/- 4 hours of snapshot time
    const windowMs = 4 * 60 * 60 * 1000;
    const windowStart = new Date(snapshot.snapshot_time.getTime() - windowMs);
    const windowEnd = new Date(snapshot.snapshot_time.getTime() + windowMs);

    const candidateTrades = await this.getTradesByDateRange(windowStart, windowEnd);

    // Filter by symbol match
    const symbolMatches = candidateTrades.filter(
      t => t.symbol.toUpperCase() === snapshot.symbol.toUpperCase()
    );

    // If exactly one match, auto-link
    if (symbolMatches.length === 1) {
      await this.updateChartSnapshot(snapshotId, {
        linked_trade_id: symbolMatches[0].id,
        auto_linked: true,
      });
      return symbolMatches[0].id;
    }

    return null;
  }

  async getChartSnapshotsByGroupId(groupId: string): Promise<ChartSnapshot[]> {
    return await db
      .select()
      .from(chartSnapshots)
      .where(eq(chartSnapshots.group_id, groupId))
      .orderBy(desc(chartSnapshots.timeframe)); // HTF first (H4 > H1 > M15 > M5)
  }

  async findSnapshotByCandleKey(symbol: string, timeframe: string, candleTime: Date): Promise<ChartSnapshot | undefined> {
    const result = await db
      .select()
      .from(chartSnapshots)
      .where(
        and(
          eq(chartSnapshots.symbol, symbol),
          eq(chartSnapshots.timeframe, timeframe),
          eq(chartSnapshots.candle_time, candleTime)
        )
      )
      .limit(1);
    return result[0];
  }

  async upsertChartSnapshot(
    snapshot: InsertChartSnapshot & { candle_time?: Date },
    _isHTF: boolean  // Parameter kept for API compatibility but not used anymore
  ): Promise<ChartSnapshot> {
    const parseDate = (val: string | null | undefined): Date | null => {
      if (!val || val === "") return null;
      const d = new Date(val);
      return isNaN(d.getTime()) ? null : d;
    };

    const snapshotWithDates = {
      ...snapshot,
      snapshot_time: parseDate(snapshot.snapshot_time) || new Date(),
      candle_time: snapshot.candle_time || null,
    };

    // First, check if this exact snapshot_id already exists (duplicate submission)
    const existingById = await db
      .select()
      .from(chartSnapshots)
      .where(eq(chartSnapshots.snapshot_id, snapshotWithDates.snapshot_id))
      .limit(1);

    if (existingById[0]) {
      // Same snapshot_id already exists - update it with fresh data
      const updated = await db
        .update(chartSnapshots)
        .set({
          image_data: snapshotWithDates.image_data,
          snapshot_time: snapshotWithDates.snapshot_time,
          candle_time: snapshotWithDates.candle_time,
          group_id: snapshotWithDates.group_id || existingById[0].group_id,
          tf_type: snapshotWithDates.tf_type || existingById[0].tf_type,
        })
        .where(eq(chartSnapshots.id, existingById[0].id))
        .returning();
      return updated[0];
    }

    // Check for existing pending/pre_analyzed snapshot for this symbol+timeframe to replace
    const existingBySymbolTf = await db
      .select()
      .from(chartSnapshots)
      .where(
        and(
          eq(chartSnapshots.symbol, snapshotWithDates.symbol),
          eq(chartSnapshots.timeframe, snapshotWithDates.timeframe),
          // Only replace pending/pre_analyzed snapshots, not analyzed ones
          or(
            eq(chartSnapshots.status, "pending"),
            eq(chartSnapshots.status, "pre_analyzed"),
            eq(chartSnapshots.status, "queued_for_review")
          )
        )
      )
      .orderBy(desc(chartSnapshots.created_at))
      .limit(1);

    if (existingBySymbolTf[0]) {
      // Update existing snapshot with new data (replaces old one)
      const updated = await db
        .update(chartSnapshots)
        .set({
          snapshot_id: snapshotWithDates.snapshot_id,
          image_data: snapshotWithDates.image_data,
          snapshot_time: snapshotWithDates.snapshot_time,
          candle_time: snapshotWithDates.candle_time,
          group_id: snapshotWithDates.group_id || existingBySymbolTf[0].group_id,
          tf_type: snapshotWithDates.tf_type || existingBySymbolTf[0].tf_type,
          // Reset analysis since image changed
          status: "pending",
          pre_analysis_score: null,
          pre_analysis_summary: null,
          pre_analysis_bias: null,
          pre_analysis_at: null,
        })
        .where(eq(chartSnapshots.id, existingBySymbolTf[0].id))
        .returning();
      return updated[0];
    }

    // No existing record found, create new
    const result = await db.insert(chartSnapshots).values(snapshotWithDates).returning();
    return result[0];
  }

  async cleanupOldLTFSnapshots(maxAgeHours: number = 24): Promise<number> {
    const cutoffTime = new Date(Date.now() - maxAgeHours * 60 * 60 * 1000);

    // LTF timeframes (less than H1 = 60 minutes)
    const ltfTimeframes = ["M1", "M2", "M3", "M4", "M5", "M6", "M10", "M12", "M15", "M20", "M30"];

    // Delete old pending/pre_analyzed LTF snapshots
    const result = await db
      .delete(chartSnapshots)
      .where(
        and(
          inArray(chartSnapshots.timeframe, ltfTimeframes),
          or(
            eq(chartSnapshots.status, "pending"),
            eq(chartSnapshots.status, "pre_analyzed")
          ),
          lt(chartSnapshots.created_at, cutoffTime)
        )
      )
      .returning();

    return result.length;
  }

  async deleteChartSnapshot(id: number): Promise<boolean> {
    const result = await db
      .delete(chartSnapshots)
      .where(eq(chartSnapshots.id, id))
      .returning();
    return result.length > 0;
  }

  async deleteAllChartSnapshots(filters?: {
    status?: ChartSnapshotStatus;
    symbol?: string;
    timeframe?: string
  }): Promise<number> {
    const conditions: any[] = [];

    if (filters?.status) {
      conditions.push(eq(chartSnapshots.status, filters.status));
    }
    if (filters?.symbol) {
      conditions.push(eq(chartSnapshots.symbol, filters.symbol));
    }
    if (filters?.timeframe) {
      conditions.push(eq(chartSnapshots.timeframe, filters.timeframe));
    }

    let result;
    if (conditions.length > 0) {
      result = await db
        .delete(chartSnapshots)
        .where(and(...conditions))
        .returning();
    } else {
      // Delete ALL snapshots
      result = await db
        .delete(chartSnapshots)
        .returning();
    }

    return result.length;
  }
}

export const storage = new DatabaseStorage();
