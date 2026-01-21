import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { insertTradeSchema, insertMT5AccountSchema, ingestChartSnapshotSchema, type ChartSnapshotStatus } from "@shared/schema";
import { generateTradeAnalysis, generateWeeklyAnalysis } from "./openai";
import { processSnapshot, runAndSaveFullAnalysis, generateChartAnnotations, type TradingStyle } from "./chart-analysis";
import { fromZodError } from "zod-validation-error";
import { startOfWeek, endOfWeek, subWeeks, isSunday } from "date-fns";

export async function registerRoutes(
  httpServer: Server,
  app: Express
): Promise<Server> {
  
  // POST /api/trades/ingest - Secure endpoint for EA to send trades (requires ingestion_key)
  app.post("/api/trades/ingest", async (req, res) => {
    try {
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Missing or invalid authorization header" });
      }
      
      const ingestionKey = authHeader.substring(7);
      const mt5Account = await storage.getMT5AccountByIngestionKey(ingestionKey);
      
      if (!mt5Account) {
        return res.status(401).json({ error: "Invalid ingestion key" });
      }
      
      // Validate that the trade's account_id and broker match the MT5 account
      const { account_id, broker, ...tradeData } = req.body;
      
      if (account_id !== mt5Account.account_id) {
        return res.status(403).json({ error: "Account ID mismatch" });
      }
      
      const validatedTrade = insertTradeSchema.parse({
        ...tradeData,
        account_id: mt5Account.account_id,
      });
      
      // Check for duplicate trade (broker + account_id + deal_id)
      const existing = await storage.getTradeByDealId(
        validatedTrade.deal_id,
        validatedTrade.account_id
      );
      
      if (existing) {
        return res.status(409).json({ 
          error: "Trade already exists",
          trade: existing 
        });
      }
      
      // Save trade without AI analysis - AI will be generated on-demand when viewing the trade
      const finalTradeData = {
        ...validatedTrade,
        ai_generated: false,
      };
      
      const newTrade = await storage.createTrade(finalTradeData);
      res.status(201).json(newTrade);
    } catch (error: any) {
      if (error.name === "ZodError") {
        const validationError = fromZodError(error);
        return res.status(400).json({ error: validationError.message });
      }
      console.error("Error ingesting trade:", error);
      res.status(500).json({ error: "Failed to ingest trade" });
    }
  });

  // POST /api/trades - Internal trade creation (for manual entry)
  app.post("/api/trades", async (req, res) => {
    try {
      const validatedTrade = insertTradeSchema.parse(req.body);
      
      // Check for duplicate trade (same deal_id + account_id)
      const existing = await storage.getTradeByDealId(
        validatedTrade.deal_id,
        validatedTrade.account_id
      );
      
      if (existing) {
        return res.status(409).json({ 
          error: "Trade already exists",
          trade: existing 
        });
      }
      
      // Save trade without AI analysis - AI will be generated on-demand when viewing the trade
      const tradeData = {
        ...validatedTrade,
        ai_generated: false,
      };
      
      const newTrade = await storage.createTrade(tradeData);
      res.status(201).json(newTrade);
    } catch (error: any) {
      if (error.name === "ZodError") {
        const validationError = fromZodError(error);
        return res.status(400).json({ error: validationError.message });
      }
      console.error("Error creating trade:", error);
      res.status(500).json({ error: "Failed to create trade" });
    }
  });
  
  // GET /api/trades - Get all trades or filter by date range
  app.get("/api/trades", async (req, res) => {
    try {
      const { start_date, end_date, account_id } = req.query;
      
      let trades;
      if (start_date && end_date) {
        const startDate = new Date(start_date as string);
        const endDate = new Date(end_date as string);
        trades = await storage.getTradesByDateRange(
          startDate, 
          endDate,
          account_id as string | undefined
        );
      } else {
        trades = await storage.getAllTrades(account_id as string | undefined);
      }
      
      res.json(trades);
    } catch (error) {
      console.error("Error fetching trades:", error);
      res.status(500).json({ error: "Failed to fetch trades" });
    }
  });
  
  // GET /api/trades/:id - Get single trade (generates AI analysis on first view if enabled)
  app.get("/api/trades/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      let trade = await storage.getTrade(id);
      
      if (!trade) {
        return res.status(404).json({ error: "Trade not found" });
      }
      
      // Generate AI analysis on-demand if not already generated and AI is enabled
      if (!trade.ai_generated && !trade.ai_summary) {
        const aiEnabled = await storage.getSetting("ai_analysis_enabled");
        
        if (aiEnabled !== "false") {
          try {
            const analysis = await generateTradeAnalysis(trade);
            const updatedTrade = await storage.updateTrade(id, {
              ai_summary: analysis.summary,
              ai_execution: analysis.execution,
              ai_mistake: analysis.mistake,
              ai_improvement: analysis.improvement,
              ai_generated: true,
            } as any);
            
            if (updatedTrade) {
              trade = updatedTrade;
            }
          } catch (aiError) {
            console.error("AI analysis failed, will retry on next view:", aiError);
            // Don't mark as generated - will retry on next view
          }
        }
      }
      
      res.json(trade);
    } catch (error) {
      console.error("Error fetching trade:", error);
      res.status(500).json({ error: "Failed to fetch trade" });
    }
  });
  
  // PATCH /api/trades/:id - Update trade (for notes, tags, etc.)
  app.patch("/api/trades/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const updates = req.body;
      
      const updatedTrade = await storage.updateTrade(id, updates);
      
      if (!updatedTrade) {
        return res.status(404).json({ error: "Trade not found" });
      }
      
      res.json(updatedTrade);
    } catch (error) {
      console.error("Error updating trade:", error);
      res.status(500).json({ error: "Failed to update trade" });
    }
  });

  // ==================== MT5 ACCOUNTS ====================
  
  // GET /api/mt5-accounts - Get all MT5 accounts
  app.get("/api/mt5-accounts", async (req, res) => {
    try {
      const accounts = await storage.getAllMT5Accounts();
      res.json(accounts);
    } catch (error) {
      console.error("Error fetching MT5 accounts:", error);
      res.status(500).json({ error: "Failed to fetch MT5 accounts" });
    }
  });

  // POST /api/mt5-accounts - Create new MT5 account connection
  app.post("/api/mt5-accounts", async (req, res) => {
    try {
      const validated = insertMT5AccountSchema.parse(req.body);
      
      // Check if account already exists
      const existing = await storage.getMT5AccountByAccountAndBroker(
        validated.account_id,
        validated.broker
      );
      
      if (existing) {
        return res.status(409).json({ 
          error: "MT5 account already connected",
          account: existing
        });
      }
      
      const newAccount = await storage.createMT5Account(validated);
      res.status(201).json(newAccount);
    } catch (error: any) {
      if (error.name === "ZodError") {
        const validationError = fromZodError(error);
        return res.status(400).json({ error: validationError.message });
      }
      console.error("Error creating MT5 account:", error);
      res.status(500).json({ error: "Failed to create MT5 account" });
    }
  });

  // DELETE /api/mt5-accounts/:id - Delete MT5 account
  app.delete("/api/mt5-accounts/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const deleted = await storage.deleteMT5Account(id);
      
      if (!deleted) {
        return res.status(404).json({ error: "MT5 account not found" });
      }
      
      res.json({ success: true });
    } catch (error) {
      console.error("Error deleting MT5 account:", error);
      res.status(500).json({ error: "Failed to delete MT5 account" });
    }
  });

  // POST /api/mt5-accounts/:id/regenerate-key - Regenerate ingestion key
  app.post("/api/mt5-accounts/:id/regenerate-key", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const account = await storage.regenerateIngestionKey(id);
      
      if (!account) {
        return res.status(404).json({ error: "MT5 account not found" });
      }
      
      res.json(account);
    } catch (error) {
      console.error("Error regenerating key:", error);
      res.status(500).json({ error: "Failed to regenerate key" });
    }
  });

  // ==================== WEEKLY INSIGHTS ====================
  
  // GET /api/weekly-insight - Get the latest weekly insight (generates on Sunday if needed)
  app.get("/api/weekly-insight", async (req, res) => {
    try {
      const now = new Date();
      const today = isSunday(now);
      
      // Week runs Sunday to Saturday
      // Get the start of the current week (Sunday)
      const currentWeekStart = startOfWeek(now, { weekStartsOn: 0 });
      const currentWeekEnd = endOfWeek(now, { weekStartsOn: 0 });
      
      // For analysis, we analyze the PREVIOUS week (last Sunday to last Saturday)
      const previousWeekStart = subWeeks(currentWeekStart, 1);
      const previousWeekEnd = subWeeks(currentWeekEnd, 1);
      
      // Check if we have an insight for the previous week
      let insight = await storage.getWeeklyInsight(previousWeekStart);
      
      // If it's Sunday and we don't have an insight for last week, generate one
      if (!insight && today) {
        const aiEnabled = await storage.getSetting("ai_analysis_enabled");
        
        if (aiEnabled !== "false") {
          try {
            const trades = await storage.getTradesByDateRange(previousWeekStart, previousWeekEnd);
            const analysis = await generateWeeklyAnalysis(trades);
            
            const totalPnl = trades.reduce((sum, t) => sum + t.net_pnl, 0);
            const winRate = trades.length > 0 
              ? (trades.filter(t => t.net_pnl > 0).length / trades.length) * 100 
              : 0;
            
            insight = await storage.createWeeklyInsight({
              week_start: previousWeekStart,
              week_end: previousWeekEnd,
              top_strength: analysis.top_strength,
              main_leak: analysis.main_leak,
              action_item: analysis.action_item,
              trades_analyzed: trades.length,
              total_pnl: totalPnl,
              win_rate: winRate,
            });
          } catch (error) {
            console.error("Failed to generate weekly insight:", error);
          }
        }
      }
      
      // If still no insight, get the latest one we have
      if (!insight) {
        insight = await storage.getLatestWeeklyInsight();
      }
      
      res.json(insight || null);
    } catch (error) {
      console.error("Error fetching weekly insight:", error);
      res.status(500).json({ error: "Failed to fetch weekly insight" });
    }
  });

  // POST /api/weekly-insight/generate - Force generate weekly insight (only works on Sundays)
  app.post("/api/weekly-insight/generate", async (req, res) => {
    try {
      const now = new Date();
      
      // Enforce Sunday-only generation
      if (!isSunday(now)) {
        return res.status(403).json({ 
          error: "Weekly insights can only be generated on Sundays",
          next_sunday: startOfWeek(now, { weekStartsOn: 0 }).toISOString()
        });
      }
      
      const aiEnabled = await storage.getSetting("ai_analysis_enabled");
      
      if (aiEnabled === "false") {
        return res.status(400).json({ error: "AI analysis is disabled" });
      }
      
      const currentWeekStart = startOfWeek(now, { weekStartsOn: 0 });
      const currentWeekEnd = endOfWeek(now, { weekStartsOn: 0 });
      const previousWeekStart = subWeeks(currentWeekStart, 1);
      const previousWeekEnd = subWeeks(currentWeekEnd, 1);
      
      // Check if already exists
      const existing = await storage.getWeeklyInsight(previousWeekStart);
      if (existing) {
        return res.json(existing);
      }
      
      const trades = await storage.getTradesByDateRange(previousWeekStart, previousWeekEnd);
      const analysis = await generateWeeklyAnalysis(trades);
      
      const totalPnl = trades.reduce((sum, t) => sum + t.net_pnl, 0);
      const winRate = trades.length > 0 
        ? (trades.filter(t => t.net_pnl > 0).length / trades.length) * 100 
        : 0;
      
      const insight = await storage.createWeeklyInsight({
        week_start: previousWeekStart,
        week_end: previousWeekEnd,
        top_strength: analysis.top_strength,
        main_leak: analysis.main_leak,
        action_item: analysis.action_item,
        trades_analyzed: trades.length,
        total_pnl: totalPnl,
        win_rate: winRate,
      });
      
      res.status(201).json(insight);
    } catch (error) {
      console.error("Error generating weekly insight:", error);
      res.status(500).json({ error: "Failed to generate weekly insight" });
    }
  });

  // ==================== APP SETTINGS ====================
  
  // GET /api/settings/:key - Get a setting value
  app.get("/api/settings/:key", async (req, res) => {
    try {
      const { key } = req.params;
      const value = await storage.getSetting(key);
      res.json({ key, value: value ?? null });
    } catch (error) {
      console.error("Error fetching setting:", error);
      res.status(500).json({ error: "Failed to fetch setting" });
    }
  });

  // PUT /api/settings/:key - Set a setting value
  app.put("/api/settings/:key", async (req, res) => {
    try {
      const { key } = req.params;
      const { value } = req.body;

      if (typeof value !== "string") {
        return res.status(400).json({ error: "Value must be a string" });
      }

      await storage.setSetting(key, value);
      res.json({ key, value });
    } catch (error) {
      console.error("Error saving setting:", error);
      res.status(500).json({ error: "Failed to save setting" });
    }
  });

  // ==================== CHART SNAPSHOTS ====================

  // POST /api/chart-snapshots/ingest - EA sends chart screenshot (requires ingestion_key)
  // Uses upsert logic: HTF keeps candle history, LTF keeps only latest per symbol/timeframe
  app.post("/api/chart-snapshots/ingest", async (req, res) => {
    try {
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Missing or invalid authorization header" });
      }

      const ingestionKey = authHeader.substring(7);
      const mt5Account = await storage.getMT5AccountByIngestionKey(ingestionKey);

      if (!mt5Account) {
        return res.status(401).json({ error: "Invalid ingestion key" });
      }

      const validated = ingestChartSnapshotSchema.parse(req.body);

      // Determine if this is HTF (H1 and above) or LTF
      const htfTimeframes = ["H1", "H2", "H3", "H4", "H6", "H8", "H12", "D1", "W1", "MN1"];
      const isHTF = htfTimeframes.includes(validated.timeframe);

      // Parse candle_time if provided
      const candleTime = validated.candle_time ? new Date(validated.candle_time) : undefined;

      // Use upsert logic:
      // - HTF: keeps each candle's snapshot (updates if same candle_time exists)
      // - LTF: keeps only the latest snapshot per symbol/timeframe (replaces pending ones)
      const snapshot = await storage.upsertChartSnapshot(
        {
          ...validated,
          account_id: mt5Account.account_id,
          status: "pending",
          candle_time: candleTime,
        },
        isHTF
      );

      // Process snapshot asynchronously (pre-analysis + optional auto full analysis)
      // Only run if status is pending (new or reset)
      if (snapshot.status === "pending") {
        processSnapshot(snapshot.id).catch(err => {
          console.error("Background snapshot processing failed:", err);
        });
      }

      // Periodically cleanup old LTF snapshots (1% chance per request to avoid overhead)
      if (Math.random() < 0.01) {
        storage.cleanupOldLTFSnapshots(24).catch(err => {
          console.error("LTF cleanup failed:", err);
        });
      }

      res.status(snapshot.status === "pending" ? 201 : 200).json({
        id: snapshot.id,
        snapshot_id: snapshot.snapshot_id,
        status: snapshot.status,
        message: snapshot.status === "pending" ? "Snapshot received, analysis queued" : "Snapshot updated"
      });
    } catch (error: any) {
      if (error.name === "ZodError") {
        const validationError = fromZodError(error);
        return res.status(400).json({ error: validationError.message });
      }
      console.error("Error ingesting chart snapshot:", error);
      res.status(500).json({ error: "Failed to ingest chart snapshot" });
    }
  });

  // GET /api/chart-snapshots - List snapshots with filters
  app.get("/api/chart-snapshots", async (req, res) => {
    try {
      const { status, symbol, timeframe, start_date, end_date, account_id } = req.query;

      const params: {
        status?: ChartSnapshotStatus;
        symbol?: string;
        timeframe?: string;
        startDate?: Date;
        endDate?: Date;
        accountId?: string;
      } = {};

      if (status) params.status = status as ChartSnapshotStatus;
      if (symbol) params.symbol = symbol as string;
      if (timeframe) params.timeframe = timeframe as string;
      if (start_date) params.startDate = new Date(start_date as string);
      if (end_date) params.endDate = new Date(end_date as string);
      if (account_id) params.accountId = account_id as string;

      const snapshots = await storage.getAllChartSnapshots(params);

      // Don't send image_data in list response to reduce payload size
      const sanitized = snapshots.map(s => ({
        ...s,
        image_data: undefined,
        has_image: !!s.image_data,
      }));

      res.json(sanitized);
    } catch (error) {
      console.error("Error fetching chart snapshots:", error);
      res.status(500).json({ error: "Failed to fetch chart snapshots" });
    }
  });

  // GET /api/chart-snapshots/stats - Get queue statistics
  app.get("/api/chart-snapshots/stats", async (req, res) => {
    try {
      const stats = await storage.getChartSnapshotStats();
      res.json(stats);
    } catch (error) {
      console.error("Error fetching snapshot stats:", error);
      res.status(500).json({ error: "Failed to fetch snapshot stats" });
    }
  });

  // GET /api/chart-snapshots/group/:groupId - Get all snapshots in a group
  app.get("/api/chart-snapshots/group/:groupId", async (req, res) => {
    try {
      const { groupId } = req.params;
      const snapshots = await storage.getChartSnapshotsByGroupId(groupId);

      // Parse full_analysis JSON for each
      const withParsedAnalysis = snapshots.map(snapshot => {
        let parsedAnalysis = null;
        if (snapshot.full_analysis) {
          try {
            parsedAnalysis = JSON.parse(snapshot.full_analysis);
          } catch {
            parsedAnalysis = null;
          }
        }
        let parsedAnnotations = null;
        if (snapshot.visual_annotations) {
          try {
            parsedAnnotations = JSON.parse(snapshot.visual_annotations);
          } catch {
            parsedAnnotations = null;
          }
        }
        return {
          ...snapshot,
          full_analysis_parsed: parsedAnalysis,
          visual_annotations_parsed: parsedAnnotations,
        };
      });

      res.json(withParsedAnalysis);
    } catch (error) {
      console.error("Error fetching snapshot group:", error);
      res.status(500).json({ error: "Failed to fetch snapshot group" });
    }
  });

  // GET /api/chart-snapshots/:id - Get single snapshot with full details
  app.get("/api/chart-snapshots/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const snapshot = await storage.getChartSnapshot(id);

      if (!snapshot) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      // Parse full_analysis JSON if present
      let parsedAnalysis = null;
      if (snapshot.full_analysis) {
        try {
          parsedAnalysis = JSON.parse(snapshot.full_analysis);
        } catch {
          parsedAnalysis = null;
        }
      }

      // Parse visual_annotations JSON if present
      let parsedAnnotations = null;
      if (snapshot.visual_annotations) {
        try {
          parsedAnnotations = JSON.parse(snapshot.visual_annotations);
        } catch {
          parsedAnnotations = null;
        }
      }

      // If part of a group, include group snapshots
      let groupSnapshots = null;
      if (snapshot.group_id) {
        const group = await storage.getChartSnapshotsByGroupId(snapshot.group_id);
        groupSnapshots = group.map(s => ({
          id: s.id,
          timeframe: s.timeframe,
          tf_type: s.tf_type,
          status: s.status,
          pre_analysis_score: s.pre_analysis_score,
          pre_analysis_bias: s.pre_analysis_bias,
          confluence_score: s.confluence_score,
          trade_direction: s.trade_direction,
        }));
      }

      res.json({
        ...snapshot,
        full_analysis_parsed: parsedAnalysis,
        visual_annotations_parsed: parsedAnnotations,
        group_snapshots: groupSnapshots,
      });
    } catch (error) {
      console.error("Error fetching chart snapshot:", error);
      res.status(500).json({ error: "Failed to fetch chart snapshot" });
    }
  });

  // PATCH /api/chart-snapshots/:id - Update snapshot (notes, etc.)
  app.patch("/api/chart-snapshots/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { user_notes } = req.body;

      const updated = await storage.updateChartSnapshot(id, { user_notes });

      if (!updated) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      res.json(updated);
    } catch (error) {
      console.error("Error updating chart snapshot:", error);
      res.status(500).json({ error: "Failed to update chart snapshot" });
    }
  });

  // POST /api/chart-snapshots/:id/approve - Approve snapshot for full analysis
  app.post("/api/chart-snapshots/:id/approve", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const snapshot = await storage.getChartSnapshot(id);

      if (!snapshot) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      // Update status to approved
      await storage.updateChartSnapshot(id, { status: "approved" });

      // Run full analysis
      const analyzed = await runAndSaveFullAnalysis(id);

      res.json(analyzed);
    } catch (error) {
      console.error("Error approving chart snapshot:", error);
      res.status(500).json({ error: "Failed to approve chart snapshot" });
    }
  });

  // POST /api/chart-snapshots/:id/discard - Mark snapshot as discarded
  app.post("/api/chart-snapshots/:id/discard", async (req, res) => {
    try {
      const id = parseInt(req.params.id);

      const updated = await storage.updateChartSnapshot(id, { status: "discarded" });

      if (!updated) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      res.json(updated);
    } catch (error) {
      console.error("Error discarding chart snapshot:", error);
      res.status(500).json({ error: "Failed to discard chart snapshot" });
    }
  });

  // POST /api/chart-snapshots/:id/analyze - Force/re-run full analysis
  app.post("/api/chart-snapshots/:id/analyze", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { tradingStyle } = req.body as { tradingStyle?: TradingStyle };
      const snapshot = await storage.getChartSnapshot(id);

      if (!snapshot) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      // Run full analysis (re-run even if already analyzed)
      const analyzed = await runAndSaveFullAnalysis(id, tradingStyle || "daytrading");

      res.json(analyzed);
    } catch (error) {
      console.error("Error analyzing chart snapshot:", error);
      res.status(500).json({ error: "Failed to analyze chart snapshot" });
    }
  });

  // POST /api/chart-snapshots/:id/annotate - Generate visual annotations for a chart
  app.post("/api/chart-snapshots/:id/annotate", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { force, tradingStyle } = req.body as { force?: boolean; tradingStyle?: TradingStyle };
      const snapshot = await storage.getChartSnapshot(id);

      if (!snapshot) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      // Check if we already have annotations and not forcing regeneration
      if (snapshot.visual_annotations && !force) {
        try {
          const existingAnnotations = JSON.parse(snapshot.visual_annotations);
          return res.json({
            snapshot_id: id,
            symbol: snapshot.symbol,
            timeframe: snapshot.timeframe,
            annotations: existingAnnotations,
            summary: "Loaded from cache",
            cached: true,
          });
        } catch (e) {
          // If parsing fails, regenerate
        }
      }

      // Parse existing analysis if available
      let existingAnalysis = undefined;
      if (snapshot.full_analysis) {
        try {
          existingAnalysis = JSON.parse(snapshot.full_analysis);
        } catch (e) {
          // Ignore parsing errors
        }
      }

      // Build price context from snapshot
      const priceContext = {
        price_high: snapshot.price_high,
        price_low: snapshot.price_low,
        current_price: snapshot.current_price,
        visible_bars: snapshot.visible_bars,
      };

      // Generate visual annotations with price context
      const annotations = await generateChartAnnotations(
        snapshot.image_data,
        snapshot.symbol,
        snapshot.timeframe,
        existingAnalysis,
        priceContext,
        tradingStyle || "daytrading"
      );

      // Persist the annotations to the database
      await storage.updateChartSnapshot(id, {
        visual_annotations: JSON.stringify(annotations.annotations),
        visual_annotations_at: new Date(),
      });

      res.json({
        snapshot_id: id,
        symbol: snapshot.symbol,
        timeframe: snapshot.timeframe,
        ...annotations,
        cached: false,
      });
    } catch (error) {
      console.error("Error generating chart annotations:", error);
      res.status(500).json({ error: "Failed to generate chart annotations" });
    }
  });

  // POST /api/chart-snapshots/group/:groupId/analyze - Analyze all snapshots in group (HTF first, then LTF)
  app.post("/api/chart-snapshots/group/:groupId/analyze", async (req, res) => {
    try {
      const { groupId } = req.params;
      const { tradingStyle } = req.body as { tradingStyle?: TradingStyle };
      const selectedStyle = tradingStyle || "daytrading";
      const snapshots = await storage.getChartSnapshotsByGroupId(groupId);

      if (snapshots.length === 0) {
        return res.status(404).json({ error: "No snapshots found in group" });
      }

      // Separate HTF and LTF
      const htfSnapshots = snapshots.filter(s => s.tf_type === "htf");
      const ltfSnapshots = snapshots.filter(s => s.tf_type === "ltf");

      const results: any[] = [];

      // Analyze HTF first (for bias/structure context)
      for (const htf of htfSnapshots) {
        await storage.updateChartSnapshot(htf.id, { status: "approved" });
        const analyzed = await runAndSaveFullAnalysis(htf.id, selectedStyle);
        if (analyzed) results.push(analyzed);
      }

      // Then analyze LTF (entry) with HTF context
      for (const ltf of ltfSnapshots) {
        await storage.updateChartSnapshot(ltf.id, { status: "approved" });
        const analyzed = await runAndSaveFullAnalysis(ltf.id, selectedStyle);
        if (analyzed) results.push(analyzed);
      }

      // Generate visual annotations for ALL timeframes in the group
      for (const snapshot of [...htfSnapshots, ...ltfSnapshots]) {
        try {
          // Get the updated snapshot with full analysis
          const updatedSnapshot = await storage.getChartSnapshot(snapshot.id);
          if (!updatedSnapshot) continue;

          // Parse existing analysis if available
          let existingAnalysis = undefined;
          if (updatedSnapshot.full_analysis) {
            try {
              existingAnalysis = JSON.parse(updatedSnapshot.full_analysis);
            } catch (e) {
              // Ignore parsing errors
            }
          }

          // Build price context from snapshot
          const priceContext = {
            price_high: updatedSnapshot.price_high,
            price_low: updatedSnapshot.price_low,
            current_price: updatedSnapshot.current_price,
            visible_bars: updatedSnapshot.visible_bars,
          };

          // Generate visual annotations with price context and trading style
          const annotations = await generateChartAnnotations(
            updatedSnapshot.image_data,
            updatedSnapshot.symbol,
            updatedSnapshot.timeframe,
            existingAnalysis,
            priceContext,
            selectedStyle
          );

          // Persist annotations
          await storage.updateChartSnapshot(snapshot.id, {
            visual_annotations: JSON.stringify(annotations.annotations),
            visual_annotations_at: new Date(),
          });
        } catch (annotationError) {
          console.error(`Error generating annotations for snapshot ${snapshot.id}:`, annotationError);
          // Continue with other snapshots even if one fails
        }
      }

      // Get updated results with annotations
      const finalResults = await storage.getChartSnapshotsByGroupId(groupId);

      res.json({
        group_id: groupId,
        analyzed_count: results.length,
        snapshots: finalResults.map(s => ({
          id: s.id,
          timeframe: s.timeframe,
          tf_type: s.tf_type,
          status: s.status,
          confluence_score: s.confluence_score,
          trade_direction: s.trade_direction,
          has_annotations: !!s.visual_annotations,
        })),
      });
    } catch (error) {
      console.error("Error analyzing snapshot group:", error);
      res.status(500).json({ error: "Failed to analyze snapshot group" });
    }
  });

  // POST /api/chart-snapshots/:id/link-trade - Manually link snapshot to trade
  app.post("/api/chart-snapshots/:id/link-trade", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { trade_id } = req.body;

      if (!trade_id || typeof trade_id !== "number") {
        return res.status(400).json({ error: "trade_id is required and must be a number" });
      }

      // Verify trade exists
      const trade = await storage.getTrade(trade_id);
      if (!trade) {
        return res.status(404).json({ error: "Trade not found" });
      }

      const updated = await storage.updateChartSnapshot(id, {
        linked_trade_id: trade_id,
        auto_linked: false,
      });

      if (!updated) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      res.json(updated);
    } catch (error) {
      console.error("Error linking snapshot to trade:", error);
      res.status(500).json({ error: "Failed to link snapshot to trade" });
    }
  });

  // POST /api/chart-snapshots/:id/unlink-trade - Remove trade link
  app.post("/api/chart-snapshots/:id/unlink-trade", async (req, res) => {
    try {
      const id = parseInt(req.params.id);

      const updated = await storage.updateChartSnapshot(id, {
        linked_trade_id: null,
        auto_linked: false,
      });

      if (!updated) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      res.json(updated);
    } catch (error) {
      console.error("Error unlinking snapshot from trade:", error);
      res.status(500).json({ error: "Failed to unlink snapshot from trade" });
    }
  });

  // POST /api/chart-snapshots/:id/mark-journal - Mark/unmark as journal candidate
  app.post("/api/chart-snapshots/:id/mark-journal", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const { is_journal_candidate } = req.body;

      if (typeof is_journal_candidate !== "boolean") {
        return res.status(400).json({ error: "is_journal_candidate must be a boolean" });
      }

      const updated = await storage.updateChartSnapshot(id, { is_journal_candidate });

      if (!updated) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      res.json(updated);
    } catch (error) {
      console.error("Error marking snapshot as journal candidate:", error);
      res.status(500).json({ error: "Failed to update snapshot" });
    }
  });

  // DELETE /api/chart-snapshots - Delete all snapshots (with optional filters)
  // NOTE: This route MUST come before /:id route to avoid matching issues
  app.delete("/api/chart-snapshots", async (req, res) => {
    console.log("DELETE /api/chart-snapshots called, query:", req.query);
    try {
      const { status, symbol, timeframe } = req.query;

      const filters: { status?: any; symbol?: string; timeframe?: string } = {};

      if (status) filters.status = status as string;
      if (symbol) filters.symbol = symbol as string;
      if (timeframe) filters.timeframe = timeframe as string;

      console.log("Calling deleteAllChartSnapshots with filters:", filters);

      const deletedCount = await storage.deleteAllChartSnapshots(
        Object.keys(filters).length > 0 ? filters : undefined
      );

      console.log("Deleted count:", deletedCount);

      res.json({
        success: true,
        deleted_count: deletedCount,
        message: `Deleted ${deletedCount} snapshot(s)`
      });
    } catch (error) {
      console.error("Error deleting chart snapshots:", error);
      res.status(500).json({ error: "Failed to delete chart snapshots" });
    }
  });

  // DELETE /api/chart-snapshots/:id - Delete a single snapshot
  app.delete("/api/chart-snapshots/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);

      const deleted = await storage.deleteChartSnapshot(id);

      if (!deleted) {
        return res.status(404).json({ error: "Snapshot not found" });
      }

      res.json({ success: true, message: "Snapshot deleted" });
    } catch (error) {
      console.error("Error deleting chart snapshot:", error);
      res.status(500).json({ error: "Failed to delete chart snapshot" });
    }
  });

  return httpServer;
}
