import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { insertTradeSchema, insertMT5AccountSchema } from "@shared/schema";
import { generateTradeAnalysis, generateWeeklyAnalysis } from "./openai";
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

  return httpServer;
}
