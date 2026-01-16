import OpenAI from "openai";
import type { Trade } from "@shared/schema";

// the newest OpenAI model is "gpt-5" which was released August 7, 2025. do not change this unless explicitly requested by the user
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

interface TradeAnalysis {
  summary: string;
  execution: "Good" | "Bad" | "Neutral";
  mistake: string | null;
  improvement: string | null;
}

export interface WeeklyAnalysis {
  top_strength: string;
  main_leak: string;
  action_item: string;
}

export async function generateTradeAnalysis(trade: Trade): Promise<TradeAnalysis> {
  try {
    const maePercent = trade.risk ? (trade.mae / trade.risk) * 100 : null;
    const mfePoints = trade.mfe;
    const profitOrLoss = trade.net_pnl >= 0 ? "profit" : "loss";
    
    const prompt = `Analyze this trading performance:

Symbol: ${trade.symbol}
Side: ${trade.side}
Entry: ${trade.entry_price}, Exit: ${trade.close_price}
P&L: $${trade.net_pnl.toFixed(2)} (${profitOrLoss})
MAE (Max Drawdown): ${trade.mae} points ($${trade.mae_cash.toFixed(2)})
MFE (Max Favorable): ${mfePoints} points
${trade.risk ? `Planned Risk (SL): ${trade.risk} points - MAE was ${maePercent?.toFixed(1)}% of risk` : "No Stop Loss set"}
${trade.setup ? `Setup: ${trade.setup}` : ""}
${trade.notes ? `Notes: ${trade.notes}` : ""}

Provide a JSON response with:
{
  "summary": "2-3 sentence analysis of execution quality",
  "execution": "Good" or "Bad" or "Neutral",
  "mistake": "specific mistake if execution was Bad, otherwise null",
  "improvement": "actionable improvement tip, or null if execution was perfect"
}

Execution rating criteria:
- Good: MAE < 50% of risk (sniper entry), or profitable with low drawdown
- Bad: MAE > 80% of risk (poor entry), or large loss
- Neutral: Average execution (MAE 50-80% of risk)`;

    const response = await openai.chat.completions.create({
      model: "gpt-5",
      messages: [
        {
          role: "system",
          content: "You are an expert trading coach analyzing trade execution quality. Focus on entry timing (MAE), risk management, and actionable feedback."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      response_format: { type: "json_object" },
    });

    const result = JSON.parse(response.choices[0].message.content || "{}");

    return {
      summary: result.summary || "Trade analysis completed",
      execution: ["Good", "Bad", "Neutral"].includes(result.execution) 
        ? result.execution 
        : "Neutral",
      mistake: result.mistake || null,
      improvement: result.improvement || null,
    };
  } catch (error) {
    console.error("Failed to generate trade analysis:", error);
    return {
      summary: "AI analysis unavailable",
      execution: "Neutral",
      mistake: null,
      improvement: null,
    };
  }
}

export async function generateWeeklyAnalysis(trades: Trade[]): Promise<WeeklyAnalysis> {
  try {
    if (trades.length === 0) {
      return {
        top_strength: "No trades to analyze this week.",
        main_leak: "Start trading to get insights.",
        action_item: "Focus on following your trading plan.",
      };
    }

    const totalPnl = trades.reduce((sum, t) => sum + t.net_pnl, 0);
    const wins = trades.filter(t => t.net_pnl > 0);
    const losses = trades.filter(t => t.net_pnl < 0);
    const winRate = (wins.length / trades.length * 100).toFixed(1);
    
    const symbolStats = trades.reduce((acc, t) => {
      if (!acc[t.symbol]) acc[t.symbol] = { wins: 0, losses: 0, pnl: 0 };
      acc[t.symbol].pnl += t.net_pnl;
      if (t.net_pnl > 0) acc[t.symbol].wins++;
      else acc[t.symbol].losses++;
      return acc;
    }, {} as Record<string, { wins: number; losses: number; pnl: number }>);

    const avgMaePercent = trades
      .filter(t => t.risk && t.risk > 0)
      .reduce((sum, t) => sum + (t.mae / t.risk!) * 100, 0) / Math.max(1, trades.filter(t => t.risk).length);

    const prompt = `Analyze this week's trading performance:

Total Trades: ${trades.length}
Win Rate: ${winRate}%
Net P&L: $${totalPnl.toFixed(2)}
Wins: ${wins.length}, Losses: ${losses.length}

Symbol Performance:
${Object.entries(symbolStats).map(([symbol, stats]) => 
  `- ${symbol}: ${stats.wins}W/${stats.losses}L, P&L: $${stats.pnl.toFixed(2)}`
).join("\n")}

Average MAE (entry quality): ${avgMaePercent.toFixed(1)}% of risk

Biggest Win: $${Math.max(...trades.map(t => t.net_pnl)).toFixed(2)}
Biggest Loss: $${Math.min(...trades.map(t => t.net_pnl)).toFixed(2)}

Provide a JSON response with:
{
  "top_strength": "One specific strength the trader showed this week (be specific with symbols/setups)",
  "main_leak": "One specific weakness or pattern causing losses (be specific)",
  "action_item": "One concrete, actionable improvement for next week"
}

Keep each response to 1-2 sentences, be specific and actionable.`;

    const response = await openai.chat.completions.create({
      model: "gpt-5",
      messages: [
        {
          role: "system",
          content: "You are an expert trading coach providing weekly performance reviews. Be specific, data-driven, and actionable."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      response_format: { type: "json_object" },
    });

    const result = JSON.parse(response.choices[0].message.content || "{}");

    return {
      top_strength: result.top_strength || "Analysis unavailable",
      main_leak: result.main_leak || "Analysis unavailable",
      action_item: result.action_item || "Analysis unavailable",
    };
  } catch (error) {
    console.error("Failed to generate weekly analysis:", error);
    return {
      top_strength: "Weekly analysis unavailable",
      main_leak: "Please try again later",
      action_item: "Check your OpenAI API key settings",
    };
  }
}
