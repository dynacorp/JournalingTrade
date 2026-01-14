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
