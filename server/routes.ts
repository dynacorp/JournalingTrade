import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { insertTradeSchema } from "@shared/schema";
import { generateTradeAnalysis } from "./openai";
import { fromZodError } from "zod-validation-error";

export async function registerRoutes(
  httpServer: Server,
  app: Express
): Promise<Server> {
  
  // POST /api/trades - Ingest trade from MT5 or manual entry
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
      
      // Generate AI analysis if not provided
      let tradeData = validatedTrade;
      if (!validatedTrade.ai_summary) {
        const tempTrade = {
          ...validatedTrade,
          id: 0,
          created_at: new Date(),
        };
        
        const analysis = await generateTradeAnalysis(tempTrade as any);
        tradeData = {
          ...validatedTrade,
          ai_summary: analysis.summary,
          ai_execution: analysis.execution,
          ai_mistake: analysis.mistake,
          ai_improvement: analysis.improvement,
          ai_generated: true,
        };
      }
      
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
  
  // GET /api/trades/:id - Get single trade
  app.get("/api/trades/:id", async (req, res) => {
    try {
      const id = parseInt(req.params.id);
      const trade = await storage.getTrade(id);
      
      if (!trade) {
        return res.status(404).json({ error: "Trade not found" });
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

  return httpServer;
}
